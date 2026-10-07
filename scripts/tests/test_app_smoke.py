import contextlib
import importlib.util
import io
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('app_smoke', Path(__file__).parents[1] / 'run-app-smoke.py')
smoke = importlib.util.module_from_spec(spec)
spec.loader.exec_module(smoke)


def response(error=None, code='ACTION_FAILED'):
    if error:
        payload = {'didError': True, 'error': error,
                   'data': {'uiError': {'code': code, 'message': error}}}
    else:
        payload = {'didError': False, 'error': None, 'data': {'capture': {'screenHash': 'ready'}}}
    return subprocess.CompletedProcess([], 0, stdout=json.dumps(payload), stderr='diagnostic stderr')


class AppSmokeReadRetryTests(unittest.TestCase):
    def test_transient_ui_reads_recover_and_preserve_both_diagnostics(self):
        for command in ('wait-for-ui', 'snapshot-ui'):
            with self.subTest(command=command), tempfile.TemporaryDirectory() as directory:
                directory = Path(directory)
                failed = response('Failed to poll runtime UI snapshot.')
                succeeded = response()
                with (patch.object(smoke.subprocess, 'run', side_effect=[failed, succeeded]) as run,
                      contextlib.redirect_stdout(io.StringIO())):
                    result = smoke.invoke_mcp(directory, 6, 'ui-automation', command, {'simulatorId': 'fixture'})
                self.assertEqual('ready', result['capture']['screenHash'])
                self.assertEqual(2, run.call_count)
                self.assertEqual(run.call_args_list[0], run.call_args_list[1])
                self.assertEqual(failed.stdout, (directory / f'06-{command}.json').read_text())
                self.assertEqual(failed.stderr, (directory / f'06-{command}.log').read_text())
                self.assertEqual(succeeded.stdout, (directory / f'06-{command}-retry-1.json').read_text())
                self.assertEqual(succeeded.stderr, (directory / f'06-{command}-retry-1.log').read_text())

    def test_persistent_poll_failure_remains_failed_after_one_retry(self):
        failed = response('Failed to poll runtime UI snapshot.')
        with tempfile.TemporaryDirectory() as directory:
            with (patch.object(smoke.subprocess, 'run', side_effect=[failed, failed]) as run,
                  contextlib.redirect_stdout(io.StringIO())):
                with self.assertRaisesRegex(ValueError, 'Failed to poll runtime UI snapshot'):
                    smoke.invoke_mcp(Path(directory), 6, 'ui-automation', 'wait-for-ui', {})
            self.assertEqual(2, run.call_count)
            self.assertEqual(4, len(list(Path(directory).iterdir())))

    def test_mutating_commands_are_never_replayed(self):
        for workflow, command in [('ui-automation', 'tap'), ('simulator', 'launch-app'), ('simulator', 'record-video')]:
            with self.subTest(command=command), tempfile.TemporaryDirectory() as directory:
                with (patch.object(smoke.subprocess, 'run', return_value=response(
                    'Failed to poll runtime UI snapshot.')) as run,
                      contextlib.redirect_stdout(io.StringIO())):
                    with self.assertRaises(ValueError):
                        smoke.invoke_mcp(Path(directory), 6, workflow, command, {})
                self.assertEqual(1, run.call_count)

    def test_predicate_timeout_and_semantic_failures_are_not_retried(self):
        for code, message in [('WAIT_TIMEOUT', "Timed out after 20000ms waiting for UI predicate 'exists'."),
                              ('WAIT_TIMEOUT', "Timed out after 60000ms waiting for UI predicate 'settled'."),
                              ('TARGET_NOT_FOUND', 'The requested element was not found.'),
                              ('TARGET_NOT_FOUND', 'Failed to poll runtime UI snapshot.'),
                              ('SNAPSHOT_PARSE_FAILED', 'Failed to parse runtime UI snapshot.'),
                              ('ACTION_FAILED', 'A different action failed.')]:
            with self.subTest(code=code, message=message), tempfile.TemporaryDirectory() as directory:
                with (patch.object(smoke.subprocess, 'run', return_value=response(message, code)) as run,
                      contextlib.redirect_stdout(io.StringIO())):
                    with self.assertRaises(ValueError):
                        smoke.invoke_mcp(Path(directory), 6, 'ui-automation', 'wait-for-ui', {})
                self.assertEqual(1, run.call_count)


class AppSmokeJourneyTests(unittest.TestCase):
    def test_navigation_uses_latest_checkpoint_capture_after_each_mutation(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            screenshot = directory / 'fixture.jpeg'
            screenshot.write_bytes(b'screenshot fixture')
            current = 'Home'
            taps = []
            generation = 0
            latest = None
            photographed = None

            def capture():
                nonlocal generation
                generation += 1
                prefix = f'{current}-{generation}-'
                return {'elements': [
                    *[{'ref': prefix + 'tab-' + label, 'label': label, 'role': 'tab', 'actions': ['tap'],
                       'value': '1' if current == label else '0'} for label in ('Home', 'People', 'Insights')],
                    {'ref': 'heading', 'identifier': current, 'role': 'other', 'state': {'visible': True}},
                    {'ref': prefix + 'add-gift', 'label': 'Add a gift', 'role': 'button', 'actions': ['tap']},
                    *([{'ref': 'name', 'identifier': 'add-gift.name', 'role': 'text-field'}]
                      if current == 'Add a gift' else [])]}

            def backend(_directory, _sequence, workflow, command, parameters):
                nonlocal current, latest, photographed
                if command == 'list':
                    return {'simulators': [{'isAvailable': True, 'name': 'iPhone 17 Pro', 'state': 'Booted',
                                            'runtime': 'iOS 26.5', 'simulatorId': 'fixture'}]}
                if command == 'snapshot-ui':
                    latest = {'elements': [e for e in capture()['elements'] if e['role'] != 'tab']}
                    return {'capture': latest}
                if command == 'wait-for-ui':
                    ready = capture()
                    if parameters['predicate'] == 'exists':
                        self.assertTrue(any(all(element.get(key) == parameters[key]
                                                for key in ('label', 'identifier', 'role') if key in parameters)
                                            for element in ready['elements']))
                    latest = ready
                    return {'capture': ready}
                if command == 'tap':
                    ref = parameters['elementRef']
                    self.assertIsNotNone(photographed)
                    self.assertIn(ref, [element['ref'] for element in photographed['elements']])
                    matches = [element for element in latest['elements'] if element['ref'] == ref]
                    self.assertEqual(1, len(matches))
                    self.assertIn('tap', matches[0]['actions'])
                    current = matches[0]['label']
                    taps.append(current)
                    latest = None
                    photographed = None
                if command == 'screenshot':
                    photographed = latest
                    return {'artifacts': {'screenshotPath': str(screenshot)}}
                if command == 'record-video' and parameters.get('stop'):
                    Path(parameters['outputFile']).write_bytes(b'video fixture')
                return {}

            def normalize_image(command, **kwargs):
                Path(command[-1]).write_bytes(b'normalized image fixture')
                return subprocess.CompletedProcess(command, 0)

            def native_output(command, **kwargs):
                if command[0] == 'git':
                    return 'a' * 40
                path = Path(command[-1])
                if path.name == 'InfoPlist.strings':
                    name = 'Who Gave' if path.parent.name == 'en.lproj' else 'кто че'
                    return json.dumps({'CFBundleDisplayName': name, 'CFBundleName': name})
                return json.dumps({'NSUserActivityTypes': ['com.apple.corespotlightitem']})

            with (patch.object(smoke, 'invoke_mcp', side_effect=backend),
                  patch.object(smoke.subprocess, 'run', side_effect=normalize_image),
                  patch.object(smoke.subprocess, 'check_output', side_effect=native_output)):
                smoke.run(directory)
            metadata = json.loads((directory / 'metadata.json').read_text())
            self.assertEqual('success', metadata['journey_outcome'])
            self.assertEqual('success', metadata['export_outcome'])
            self.assertEqual(['home', 'people', 'insights', 'add-gift'],
                             [checkpoint['name'] for checkpoint in metadata['checkpoints']])
            self.assertEqual(['People', 'Insights', 'Add a gift'], taps)

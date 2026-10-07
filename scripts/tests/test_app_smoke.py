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
    def test_postcondition_matching_rejects_wrong_state(self):
        capture = {'elements': [{'identifier': 'home', 'role': 'other'}]}
        with self.assertRaises(ValueError):
            smoke.assert_picker_closed(capture, 'add-gift.from', 'CI Giver')

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
        for workflow, command in [('ui-automation', 'tap'), ('ui-automation', 'batch'), ('simulator', 'launch-app'), ('simulator', 'record-video')]:
            with self.subTest(command=command), tempfile.TemporaryDirectory() as directory:
                with (patch.object(smoke.subprocess, 'run', return_value=response(
                    'Failed to poll runtime UI snapshot.')) as run,
                      contextlib.redirect_stdout(io.StringIO())):
                    with self.assertRaises(ValueError):
                        smoke.invoke_mcp(Path(directory), 6, workflow, command, {})
                self.assertEqual(1, run.call_count)

    def test_batch_transport_timeout_is_not_replayed_and_keeps_diagnostics(self):
        payload = {'didError': True,
                   'error': 'Daemon invocation failed: Daemon request timed out after 30000ms',
                   'data': {'category': 'runtime', 'code': 'DAEMON_TRANSPORT_FAILED'}}
        failed = subprocess.CompletedProcess([], 1, stdout=json.dumps(payload), stderr='transport diagnostic')
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            with (patch.object(smoke.subprocess, 'run', return_value=failed) as run,
                  contextlib.redirect_stdout(io.StringIO())):
                with self.assertRaisesRegex(ValueError, 'Daemon request timed out after 30000ms') as raised:
                    smoke.invoke_mcp(directory, 11, 'ui-automation', 'batch',
                                     {'steps': [{'action': 'tap', 'elementRef': 'e52'}]})
            self.assertEqual('DAEMON_TRANSPORT_FAILED', raised.exception.code)
            self.assertEqual(1, run.call_count)
            self.assertEqual(failed.stdout, (directory / '11-batch.json').read_text())
            self.assertEqual(failed.stderr, (directory / '11-batch.log').read_text())

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
    def test_calendar_week_count_search_is_bounded_and_reaches_a_different_month_shape(self):
        start = smoke.calendar_week_count("February 2029")
        months = ["March 2029", "April 2029", "May 2029", "June 2029", "July 2029",
                  "August 2029", "September 2029", "October 2029", "November 2029",
                  "December 2029", "January 2030", "February 2030"]
        self.assertTrue(any(smoke.calendar_week_count(month) != start for month in months))

    def test_navigation_uses_latest_checkpoint_capture_after_each_mutation(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            screenshot = directory / 'fixture.jpeg'
            screenshot.write_bytes(b'screenshot fixture')
            current = 'Home'
            calendar_page = 0
            currency_selected = False
            taps = []
            generation = 0
            latest = None
            photographed = None
            timed_out_people_tap = False
            batch_calls = []

            def capture():
                nonlocal generation
                generation += 1
                prefix = f'{current}-{generation}-'
                elements = [
                    *[{'ref': prefix + 'tab-' + label, 'label': label, 'role': 'tab', 'actions': ['tap'],
                       'value': '1' if current == label else '0'} for label in ('Home', 'People', 'Insights')],
                    {'ref': 'heading', 'identifier': current, 'role': 'other', 'state': {'visible': True}},
                    {'ref': prefix + 'add-gift', 'label': 'Add a gift', 'role': 'button', 'actions': ['tap']},
                    {'ref': 'name', 'identifier': 'add-gift.name', 'role': 'text-field'},
                    {'ref': 'details', 'identifier': 'add-gift.details', 'role': 'button', 'actions': ['tap']},
                    {'ref': 'value', 'identifier': 'add-gift.value', 'role': 'text-field'},
                    {'ref': 'scroll', 'identifier': 'add-gift.scroll', 'role': 'scroll-view', 'actions': ['swipe']},
                    {'ref': 'date', 'identifier': 'add-gift.date', 'role': 'button', 'actions': ['tap']},
                    {'ref': 'calendar', 'identifier': 'date-picker.calendar', 'role': 'other', 'actions': ['swipe']},
                    {'ref': 'month', 'label': (['October 2026', 'November 2026', 'December 2026', 'January 2027'][min(calendar_page, 3)]), 'role': 'static-text'},
                    {'ref': 'today', 'identifier': 'date-picker.today', 'role': 'button', 'actions': ['tap']},
                    {'ref': 'from', 'identifier': 'add-gift.from', 'value': 'CI Giver', 'role': 'button', 'actions': ['tap']},
                    {'ref': 'to', 'identifier': 'add-gift.to', 'value': 'CI Receiver', 'role': 'button', 'actions': ['tap']},
                    {'ref': 'query', 'identifier': 'person-picker.query', 'role': 'text-field'},
                    {'ref': 'add-person', 'identifier': 'person-picker.add', 'role': 'button', 'actions': ['tap']},
                    {'ref': 'person-a', 'identifier': 'person-picker.person.a', 'label': 'CI Giver', 'role': 'button', 'actions': ['tap']},
                    {'ref': 'person-b', 'identifier': 'person-picker.person.b', 'label': 'CI Receiver', 'role': 'button', 'actions': ['tap']},
                    {'ref': 'save', 'identifier': 'add-gift.save', 'role': 'button', 'actions': ['tap']},
                    {'ref': 'gift', 'label': 'CI acceptance book', 'role': 'static-text'},
                    {'ref': 'duplicate-gift', 'label': 'CI duplicate reuse', 'role': 'static-text'},
                    {'ref': 'settings', 'label': 'Settings', 'role': 'button', 'actions': ['tap']},
                    {'ref': 'settings-screen', 'identifier': 'settings.screen', 'role': 'other'},
                    {'ref': 'currency', 'identifier': 'settings.currency', 'value': ('AUD' if currency_selected else 'USD'), 'role': 'button', 'actions': ['tap']},
                    {'ref': 'currency-list', 'identifier': 'settings.currency.list', 'role': 'scroll-view', 'actions': ['swipe']},
                    {'ref': 'aud', 'identifier': 'settings.currency.AUD', 'value': 'AUD', 'role': 'button', 'actions': ['tap']},
                    {'ref': 'licenses-link', 'identifier': 'settings.third-party-licenses', 'role': 'button', 'actions': ['tap']},
                    {'ref': 'licenses-screen', 'identifier': 'settings.third-party-licenses.screen', 'role': 'other'},
                    {'ref': 'license-heading', 'label': 'Archivo license', 'role': 'static-text'}]
                if current != 'Add a gift':
                    elements = [e for e in elements if e.get('identifier') != 'add-gift.name']
                return {'elements': elements}

            def backend(_directory, _sequence, workflow, command, parameters):
                nonlocal current, latest, photographed, calendar_page, timed_out_people_tap, currency_selected
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
                    if parameters['predicate'] == 'settled':
                        photographed = ready
                    return {'capture': ready}
                if command == 'tap':
                    self.fail('Smoke navigation must avoid the observed AXe selector tap path')
                if command == 'batch':
                    self.assertEqual(1, len(parameters['steps']))
                    self.assertEqual('tap', parameters['steps'][0]['action'])
                    ref = parameters['steps'][0]['elementRef']
                    matches = [element for element in latest['elements'] if element['ref'] == ref]
                    self.assertEqual(1, len(matches))
                    self.assertIn('tap', matches[0]['actions'])
                    batch_calls.append(ref)
                    if matches[0].get('identifier') == 'settings.currency.AUD':
                        currency_selected = True
                    if matches[0].get('identifier') == 'add-gift.save':
                        current = 'Home'
                    if matches[0].get('label') == 'People' and not timed_out_people_tap:
                        timed_out_people_tap = True
                        current = 'People'
                        taps.append('People')
                        raise smoke.MCPInvocationError(
                            "XcodeBuildMCP failed: Daemon invocation failed: Daemon request timed out after 30000ms",
                            code="DAEMON_TRANSPORT_FAILED")
                    if matches[0].get('label') in ('Home', 'People', 'Insights', 'Add a gift'):
                        self.assertIsNotNone(photographed)
                        self.assertIn(ref, [element['ref'] for element in photographed['elements']])
                    if matches[0].get('label') in ('Home', 'People', 'Insights', 'Add a gift'):
                        current = matches[0]['label']
                        taps.append(current)
                    latest = None
                    photographed = None
                if command in ('type-text', 'swipe', 'launch-app', 'stop'):
                    if command == 'swipe':
                        if parameters.get('direction') == 'left':
                            calendar_page += 1
                        else:
                            calendar_page = max(0, calendar_page - 1)
                    return {}
                if command == 'screenshot':
                    photographed = latest
                    return {'artifacts': {'screenshotPath': str(screenshot)}}
                if command == 'record-video' and parameters.get('stop'):
                    Path(parameters['outputFile']).write_bytes(b'video fixture')
                return {}

            def normalize_image(command, **kwargs):
                Path(command[-1]).write_bytes(b'normalized image fixture')
                return subprocess.CompletedProcess(command, 0)

            with (patch.object(smoke, 'invoke_mcp', side_effect=backend),
                  patch.object(smoke, 'entity_names', return_value={
                      'gift': 'CI acceptance book', 'giver': 'CI Giver',
                      'receiver': 'CI Receiver', 'duplicate': 'CI duplicate reuse'}),
                  patch.object(smoke.subprocess, 'run', side_effect=normalize_image),
                  patch.object(smoke.subprocess, 'check_output', return_value='a' * 40)):
                smoke.run(directory)
            metadata = json.loads((directory / 'metadata.json').read_text())
            self.assertEqual('success', metadata['journey_outcome'])
            self.assertEqual('success', metadata['export_outcome'])
            self.assertEqual(['home', 'people', 'insights', 'home',
                              'add-gift-compact', 'add-gift-details',
                              'add-gift-value-scrolled', 'calendar-october-2026',
                              'calendar-january-2027', 'details-after-calendar',
                              'add-gift-endpoints', 'saved-gift',
                              'relaunch-persistence', 'duplicate-person-reuse',
                              'settings', 'licenses'],
                             [checkpoint['name'] for checkpoint in metadata['checkpoints']])
            self.assertEqual(['People', 'Insights', 'Home', 'Add a gift', 'Add a gift'], taps)
            self.assertEqual(1, sum(ref.endswith('tab-People') for ref in batch_calls))

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
    def test_daemon_status_requires_running_workspace_match(self):
        with tempfile.TemporaryDirectory() as directory:
            calls = []
            def runner(command, **kwargs):
                calls.append(command)
                if command[2] == 'start':
                    return subprocess.CompletedProcess(command, 0, stdout='', stderr='')
                return subprocess.CompletedProcess(command, 0, stdout=json.dumps([
                    {'workspaceRoot': str(Path.cwd().resolve()), 'status': 'running'}]), stderr='')
            smoke.ensure_daemon(Path(directory), timeout=1, command_runner=runner, sleeper=lambda _: None)
            self.assertEqual(2, len(calls))

    def test_daemon_status_zero_exit_requires_running_current_workspace(self):
        for status, workspace in [('stale', str(Path.cwd().resolve())), ('running', '/another/workspace')]:
            with self.subTest(status=status, workspace=workspace), tempfile.TemporaryDirectory() as directory:
                calls = []
                def runner(command, **kwargs):
                    calls.append(command)
                    if command[2] == 'start':
                        return subprocess.CompletedProcess(command, 0, stdout='', stderr='')
                    return subprocess.CompletedProcess(command, 0, stdout=json.dumps([
                        {'workspaceRoot': workspace, 'status': status}]), stderr='')
                with patch.object(smoke.time, 'monotonic', side_effect=[0, 0, 2]):
                    with self.assertRaises(ValueError):
                        smoke.ensure_daemon(Path(directory), timeout=1, command_runner=runner, sleeper=lambda _: None)
                self.assertEqual(['start', 'list'], [command[2] for command in calls])
                self.assertTrue((Path(directory) / 'daemon-list-timeout.log').is_file())

    def test_read_transport_timeout_retries_once(self):
        payload = {'didError': True, 'error': 'Daemon invocation failed: Daemon request timed out after 30000ms',
                   'data': {'code': 'DAEMON_TRANSPORT_FAILED'}}
        failed = subprocess.CompletedProcess([], 1, stdout=json.dumps(payload), stderr='transport')
        succeeded = response()
        with tempfile.TemporaryDirectory() as directory:
            with (patch.object(smoke.subprocess, 'run', side_effect=[failed, succeeded]) as run,
                  contextlib.redirect_stdout(io.StringIO())):
                result = smoke.invoke_mcp(Path(directory), 4, 'ui-automation', 'wait-for-ui', {})
        self.assertEqual('ready', result['capture']['screenHash'])
        self.assertEqual(2, run.call_count)

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
    def run_fixture(self, *, calendar_counts=(5, 6), native_failure=False):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            invocations = []
            result = directory / "external-result.xcresult"
            result.mkdir()
            (result / "fixture-result").write_text("native result")

            def mcp(_directory, _sequence, workflow, command, parameters):
                invocations.append((command, parameters))
                if command == 'list':
                    return {'simulators': [{'isAvailable': True, 'name': 'iPhone 17 Pro', 'state': 'Booted',
                                            'runtime': 'iOS 26.5', 'simulatorId': 'fixture'}]}
                if command == 'test':
                    if native_failure:
                        payload = {'didError': True, 'error': 'Native assertion failed',
                                   'data': {'artifacts': {'xcresultPath': str(result)}}}
                        smoke.checked_output(subprocess.CompletedProcess([], 1, json.dumps(payload), ''))
                    return {'artifacts': {'xcresultPath': str(result)}}
                if command == 'record-video' and parameters.get('stop'):
                    Path(parameters['outputFile']).write_bytes(b'video')
                return {}

            def export(command, **kwargs):
                attachment_dir = directory / 'attachments'
                attachment_dir.mkdir(parents=True, exist_ok=True)
                names = ['home-start', 'people', 'insights', 'gift-compact-keyboard', 'details-value',
                         'gift-saved', 'gift-after-relaunch', 'settings-currency', 'licenses', 'calendar-reverse']
                names += [f'calendar-{count}-weeks' for count in calendar_counts]
                attachments = []
                for index, name in enumerate(names):
                    filename = f'exported-{index}.png'
                    (attachment_dir / filename).write_bytes(b'image')
                    attachments.append({'exportedFileName': filename,
                                        'suggestedHumanReadableName': f'{name}_1.png'})
                (attachment_dir / 'manifest.json').write_text(json.dumps([{'attachments': attachments}]))
                return subprocess.CompletedProcess(command, 0, stdout='', stderr='')

            with (patch.object(smoke, 'invoke_mcp', side_effect=mcp),
                  patch.object(smoke, 'ensure_daemon'),
                  patch.object(smoke.subprocess, 'run', side_effect=export),
                  patch.object(smoke.subprocess, 'check_output', return_value='a' * 40)):
                if native_failure or len(set(calendar_counts)) < 2:
                    with self.assertRaises(ValueError):
                        smoke.run(directory)
                else:
                    smoke.run(directory)
            metadata = json.loads((directory / 'metadata.json').read_text())
            self.assertEqual(1, sum(command == 'test' for command, _ in invocations))
            self.assertTrue((directory / 'Acceptance.xcresult' / 'fixture-result').is_file())
            self.assertTrue((directory / 'attachments/home-start.png').is_file())
            return metadata

    def test_named_native_attachments_and_distinct_calendar_counts_pass(self):
        metadata = self.run_fixture()
        self.assertEqual('success', metadata['journey_outcome'])
        self.assertEqual('success', metadata['export_outcome'])
        self.assertEqual('home-start', metadata['checkpoints'][0]['name'])

    def test_missing_distinct_calendar_evidence_rejects_publication(self):
        metadata = self.run_fixture(calendar_counts=(5,))
        self.assertEqual('failure', metadata['export_outcome'])
        self.assertIn('two calendar checkpoints with distinct week counts', metadata['missing_checkpoints'])

    def test_failed_native_test_keeps_result_and_exports_diagnostics(self):
        metadata = self.run_fixture(native_failure=True)
        self.assertEqual('failure', metadata['journey_outcome'])
        self.assertEqual('failure', metadata['export_outcome'])
        self.assertIn('Native assertion failed', metadata['native_test_error'])


if __name__ == "__main__":
    unittest.main()

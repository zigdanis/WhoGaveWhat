import importlib.util
import json
import os
import plistlib
import re
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import time
import unittest
from unittest.mock import Mock, patch

spec = importlib.util.spec_from_file_location('app_smoke', Path(__file__).parents[1] / 'run-app-smoke.py')
smoke = importlib.util.module_from_spec(spec)
spec.loader.exec_module(smoke)


def signing_fixture(label):
    if label == 'simulator-signing-info':
        return plistlib.dumps({'CFBundleIdentifier': 'org.example.launcher'}).decode()
    if label == 'simulator-signing-display':
        return 'Identifier=org.example.launcher\nSignature=adhoc\n'
    return ''


class SimulatorIdentityTests(unittest.TestCase):
    def test_real_bundle_identifier_and_signature_from_either_output_stream_are_verified(self):
        for details_in_stderr in (False, True):
            with self.subTest(stderr=details_in_stderr), tempfile.TemporaryDirectory() as temporary:
                def native(_directory, label, command, timeout):
                    self.assertEqual(30, timeout)
                    output = signing_fixture(label)
                    if label == 'simulator-signing-display' and details_in_stderr:
                        return subprocess.CompletedProcess(command, 0, '', output)
                    return subprocess.CompletedProcess(command, 0, output, '')
                metadata = {}
                with patch.object(smoke, 'run_command', side_effect=native):
                    smoke.verify_built_simulator_identity(Path(temporary), metadata)
                self.assertEqual(dict(verified=True, bundle_identifier='org.example.launcher',
                                      signing_identifier='org.example.launcher', signature='adhoc'),
                                 metadata['simulator_signing'])

    def test_missing_mismatched_nonadhoc_or_invalid_signature_cannot_be_verified(self):
        for failure in ('missing-bundle', 'missing-identifier', 'wrong-identifier', 'missing-signature',
                        'wrong-signature', 'verification-failed', 'unsigned'):
            with self.subTest(failure=failure), tempfile.TemporaryDirectory() as temporary:
                def native(_directory, label, command, _timeout):
                    output = signing_fixture(label)
                    if label == 'simulator-signing-info' and failure == 'missing-bundle':
                        output = plistlib.dumps({}).decode()
                    if label == 'simulator-signing-display':
                        if failure == 'unsigned':
                            raise smoke.NativeCommandError('code object is not signed at all')
                        if failure == 'missing-identifier':
                            output = 'Signature=adhoc\n'
                        if failure == 'wrong-identifier':
                            output = 'Identifier=OtherExecutable\nSignature=adhoc\n'
                        if failure == 'missing-signature':
                            output = 'Identifier=org.example.launcher\n'
                        if failure == 'wrong-signature':
                            output = 'Identifier=org.example.launcher\nSignature=unexpected\n'
                    if label == 'simulator-signing-verify' and failure == 'verification-failed':
                        raise smoke.NativeCommandError('signature verification failed')
                    return subprocess.CompletedProcess(command, 0, '', output) if label == 'simulator-signing-display' \
                        else subprocess.CompletedProcess(command, 0, output, '')
                metadata = {}
                with patch.object(smoke, 'run_command', side_effect=native), self.assertRaises(ValueError):
                    smoke.verify_built_simulator_identity(Path(temporary), metadata)
                self.assertFalse(metadata['simulator_signing']['verified'])

    def test_identity_failure_blocks_success_and_preserves_original_native_failure(self):
        for native_failure in (False, True):
            with self.subTest(native_failure=native_failure), tempfile.TemporaryDirectory() as temporary:
                directory = Path(temporary)
                def native(_directory, label, command, _timeout):
                    if label == 'simulator-list':
                        output = json.dumps({'devices': {'runtime': [dict(
                            name='iPhone 17 Pro', udid='sim-id', state='Booted', isAvailable=True)]}})
                    else:
                        output = signing_fixture(label)
                    if label == 'xcodebuild-test':
                        (directory / 'Acceptance.xcresult').mkdir()
                        self.assertIn('CODE_SIGNING_ALLOWED=YES', command)
                        self.assertIn('CODE_SIGN_IDENTITY=-', command)
                        if native_failure:
                            raise smoke.NativeCommandError('original native assertion')
                    if label == 'simulator-signing-verify':
                        raise smoke.NativeCommandError('invalid built app signature')
                    return subprocess.CompletedProcess(command, 0, output, '')
                def stop(_directory, _recording):
                    (directory / 'clip.mp4').write_bytes(b'mp4')
                with patch.object(smoke.subprocess, 'check_output', return_value='a' * 40), \
                        patch.object(smoke, 'run_command', side_effect=native), \
                        patch.object(smoke, 'start_recording', return_value=(Mock(), Mock())), \
                        patch.object(smoke, 'stop_recording', side_effect=stop), \
                        patch.object(smoke, '_export_xcresult_attachments',
                                     side_effect=lambda _result, attachments, _directory: attachments.mkdir()), \
                        patch.object(smoke, '_export_named_checkpoints', return_value=[]):
                    expected = 'original native assertion' if native_failure else 'invalid built app signature'
                    with self.assertRaisesRegex(ValueError, expected):
                        smoke.run(directory)
                metadata = json.loads((directory / 'metadata.json').read_text())
                self.assertEqual('invalid built app signature', metadata['simulator_identity_error'])
                self.assertFalse(metadata['simulator_signing']['verified'])
                self.assertEqual('failure', metadata['journey_outcome'])
                self.assertEqual('failure', metadata['export_outcome'])
                if native_failure:
                    self.assertEqual('original native assertion', metadata['native_test_error'])
                self.assertFalse((directory / 'DerivedData').exists())


class FreshCISimulatorTests(unittest.TestCase):
    source_id = 'AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA'
    created_id = 'BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB'
    runtime_id = 'com.apple.CoreSimulator.SimRuntime.iOS-26-4'
    device_type = 'com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro'

    def source_payload(self):
        return {'devices': {self.runtime_id: [dict(
            name='iPhone 17 Pro', udid=self.source_id, state='Shutdown', isAvailable=True,
            deviceTypeIdentifier=self.device_type)]}}

    def runtimes_payload(self, name='iOS 26.4', device_name='iPhone 17 Pro'):
        return {'runtimes': [dict(
            name=name, identifier=self.runtime_id, isAvailable=True, buildversion='23E244',
            supportedDeviceTypes=[dict(name='iPhone 17 Pro Max', identifier=self.device_type + '-Max'),
                                  dict(name=device_name, identifier=self.device_type)])]}

    def test_fresh_fixture_requires_ci_and_explicit_runtime_before_native_actions(self):
        for environment, runtime in (({}, 'iOS 26.4'), ({'GITHUB_ACTIONS': 'false'}, 'iOS 26.4'),
                                     ({'GITHUB_ACTIONS': 'true'}, None)):
            with self.subTest(environment=environment, runtime=runtime), tempfile.TemporaryDirectory() as temporary, \
                    patch.dict(os.environ, environment, clear=True), patch.object(smoke, 'run_command') as native:
                with self.assertRaisesRegex(ValueError, 'requires GitHub Actions and an explicit --runtime'):
                    smoke.run(Path(temporary), runtime=runtime, fresh_ci_simulator=True)
                native.assert_not_called()

    def test_fixture_rejects_missing_exact_phone_runtime_and_conflicting_booted_runtime_before_create(self):
        conflict = self.source_payload()
        conflict['devices']['com.apple.CoreSimulator.SimRuntime.iOS-26-5'] = [dict(
            name='iPhone 16', udid='conflict', state='Booted', isAvailable=True)]
        duplicate_runtime = self.runtimes_payload()
        duplicate_runtime['runtimes'].append(dict(duplicate_runtime['runtimes'][0], identifier='other'))
        for payload, runtimes in ((self.source_payload(), self.runtimes_payload(device_name='iPhone 16')),
                                  (self.source_payload(), self.runtimes_payload(name='iOS 26.5')),
                                  (self.source_payload(), duplicate_runtime),
                                  (conflict, self.runtimes_payload())):
            with self.subTest(payload=payload, runtimes=runtimes), patch.object(
                    smoke, 'run_command', return_value=subprocess.CompletedProcess(
                        [], 0, json.dumps(runtimes), '')) as native:
                metadata = {}
                with self.assertRaises(ValueError):
                    smoke.create_ci_simulator(Path('/unused'), payload, 'iOS 26.4', metadata)
                self.assertEqual([] if payload is conflict else ['simulator-runtimes'],
                                 [call.args[1] for call in native.call_args_list])
                self.assertNotIn('simulator_fixture', metadata)

    def test_fixture_creates_the_requested_model_on_a_runtime_without_default_devices(self):
        calls = []
        created_name = None
        def native(_directory, label, command, timeout):
            nonlocal created_name
            calls.append(label)
            if label == 'simulator-runtimes':
                self.assertEqual(['xcrun', 'simctl', 'list', 'runtimes', 'available', '--json'], command)
                output = json.dumps(self.runtimes_payload(name='iOS 27.1', device_name='iPhone 18 Pro'))
            elif label == 'simulator-create':
                self.assertEqual([self.device_type, self.runtime_id], command[-2:])
                created_name = command[3]
                output = self.created_id
            else:
                output = json.dumps({'devices': {self.runtime_id: [dict(
                    name=created_name, udid=self.created_id, state='Shutdown', isAvailable=True,
                    deviceTypeIdentifier=self.device_type)]}})
            return subprocess.CompletedProcess(command, 0, output, '')
        metadata = {}
        with patch.object(smoke, 'run_command', side_effect=native):
            simulator = smoke.create_ci_simulator(Path('/unused'), {'devices': {}}, 'iOS 27.1', metadata,
                                                  'iPhone 18 Pro')
        self.assertEqual(['simulator-runtimes', 'simulator-create', 'simulator-created-list'], calls)
        self.assertEqual((self.created_id, 'iOS 27.1', self.runtime_id),
                         (simulator['udid'], simulator['runtime'], simulator['runtime_identifier']))
        fixture = metadata['simulator_fixture']
        self.assertEqual(('iPhone 18 Pro', self.device_type, '23E244', True),
                         (fixture['device_name'], fixture['device_type_identifier'], fixture['runtime_build'],
                          fixture['creation_verified']))

    def test_failed_creation_or_verification_never_takes_ownership_of_an_existing_device(self):
        for failure in ('create-error', 'invalid-udid', 'existing-udid', 'list-error', 'wrong-runtime'):
            with self.subTest(failure=failure), tempfile.TemporaryDirectory() as temporary:
                metadata = {}
                calls = []
                def native(_directory, label, command, timeout):
                    calls.append(command)
                    if label == 'simulator-runtimes':
                        output = json.dumps(self.runtimes_payload())
                    elif label == 'simulator-create':
                        self.assertEqual(60, timeout)
                        if failure == 'create-error':
                            raise smoke.NativeCommandError('create timed out')
                        output = 'invalid' if failure == 'invalid-udid' else (
                            self.source_id if failure == 'existing-udid' else self.created_id)
                    elif label == 'simulator-created-list':
                        if failure == 'list-error':
                            raise smoke.NativeCommandError('list timed out')
                        output = json.dumps({'devices': {'wrong-runtime': []}})
                    elif label == 'simulator-created-state':
                        output = json.dumps({'devices': {self.runtime_id: [dict(
                            udid=self.created_id, state='Shutdown')]}})
                    else:
                        output = ''
                    return subprocess.CompletedProcess(command, 0, output, '')
                with patch.object(smoke, 'run_command', side_effect=native), self.assertRaises(ValueError):
                    smoke.create_ci_simulator(Path(temporary), self.source_payload(), 'iOS 26.4', metadata)
                with patch.object(smoke, 'run_command', side_effect=native):
                    smoke.cleanup_ci_simulator(Path(temporary), metadata)
                fixture = metadata['simulator_fixture']
                self.assertFalse(fixture['creation_verified'])
                mutations = [command for command in calls if command[2] in ('shutdown', 'delete')]
                self.assertEqual([['xcrun', 'simctl', 'delete', self.created_id]]
                                 if failure in ('list-error', 'wrong-runtime') else [], mutations)
                self.assertNotIn(self.source_id, [command[-1] for command in mutations])

    def test_native_failure_retains_strict_suite_and_provenance_then_exports_before_owned_cleanup(self):
        for discovery_only, cleanup_failure in ((False, False), (True, False), (False, True)):
            with self.subTest(discovery_only=discovery_only, cleanup_failure=cleanup_failure), \
                    tempfile.TemporaryDirectory() as temporary:
                directory = Path(temporary)
                events = []
                metadata_in_flight = None
                created_name = None
                def native(_directory, label, command, timeout):
                    nonlocal created_name
                    events.append(label)
                    output = signing_fixture(label)
                    if label == 'simulator-list':
                        output = json.dumps(self.source_payload())
                    elif label == 'simulator-runtimes':
                        output = json.dumps(self.runtimes_payload())
                    elif label == 'simulator-create':
                        self.assertEqual(['xcrun', 'simctl', 'create'], command[:3])
                        self.assertEqual([self.device_type, self.runtime_id], command[-2:])
                        self.assertEqual(60, timeout)
                        created_name = command[3]
                        output = self.created_id + '\n'
                    elif label in ('simulator-created-list', 'simulator-created-state'):
                        self.assertEqual(30, timeout)
                        payload = self.source_payload()
                        payload['devices'][self.runtime_id].append(dict(
                            name=created_name, udid=self.created_id, state='Shutdown' if label.endswith('list') else 'Booted',
                            isAvailable=True, deviceTypeIdentifier=self.device_type, dataPath=temporary))
                        output = json.dumps(payload)
                    elif label == 'xcodebuild-test':
                        self.assertEqual(900 if discovery_only else 1800, timeout)
                        self.assertIn(f'platform=iOS Simulator,id={self.created_id}', command)
                        self.assertIn('CODE_SIGNING_ALLOWED=YES', command)
                        self.assertIn('CODE_SIGN_IDENTITY=-', command)
                        self.assertIn('-collect-test-diagnostics never', ' '.join(command))
                        self.assertNotIn('-skip-testing:WhoGaveWhatUITests/AppDiscoveryUITests', command)
                        self.assertEqual(discovery_only, f'-only-testing:{smoke.SPOTLIGHT_DIAGNOSTIC_TEST}' in command)
                        self.assertEqual(not discovery_only, f'-skip-testing:{smoke.SPOTLIGHT_DIAGNOSTIC_TEST}' in command)
                        (directory / 'Acceptance.xcresult').mkdir()
                        raise smoke.NativeCommandError('original Calendar catalog assertion')
                    elif label in ('app-discovery-index-log', 'spotlight-pipeline-log'):
                        self.assertEqual(self.created_id, command[3])
                    elif label in ('simulator-created-shutdown', 'simulator-created-delete'):
                        self.assertEqual(self.created_id, command[-1])
                        if cleanup_failure and label == 'simulator-created-delete':
                            raise smoke.NativeCommandError('delete timed out')
                    return subprocess.CompletedProcess(command, 0, output, '')
                def prepare(_directory, simulator, metadata):
                    nonlocal metadata_in_flight
                    metadata_in_flight = metadata
                    events.append('prepare-languages')
                    self.assertEqual((self.created_id, 'Shutdown', 'iOS 26.4'),
                                     (simulator['udid'], simulator['state'], simulator['runtime']))
                    self.assertTrue(metadata['simulator_fixture']['creation_verified'])
                def record(_directory, simulator_id, _video, display=None):
                    self.assertEqual(self.created_id, simulator_id)
                    events.append('record-start')
                    return Mock(), Mock()
                def stop(_directory, _recording):
                    events.append('record-stop')
                def export(*_args):
                    events.append('export-attachments')
                with patch.dict(os.environ, {'GITHUB_ACTIONS': 'true'}), \
                        patch.object(smoke.subprocess, 'check_output', return_value='a' * 40), \
                        patch.object(smoke, 'run_command', side_effect=native), \
                        patch.object(smoke, 'prepare_disposable_languages', side_effect=prepare), \
                        patch.object(smoke, 'start_recording', side_effect=record), \
                        patch.object(smoke, 'stop_recording', side_effect=stop), \
                        patch.object(smoke, '_export_xcresult_attachments', side_effect=export):
                    with self.assertRaisesRegex(smoke.NativeCommandError, 'original Calendar catalog assertion'):
                        smoke.run(directory, verify_app_names=True, discovery_only=discovery_only,
                                  runtime='iOS 26.4', fresh_ci_simulator=True)
                metadata = json.loads((directory / 'metadata.json').read_text())
                self.assertEqual('failure', metadata['journey_outcome'])
                self.assertEqual('failure', metadata['export_outcome'])
                self.assertEqual('original Calendar catalog assertion', metadata['native_test_error'])
                self.assertEqual(self.created_id, metadata['simulator_id'])
                fixture = metadata['simulator_fixture']
                self.assertEqual(('iPhone 17 Pro', self.device_type, self.runtime_id),
                                 (fixture['device_name'], fixture['device_type_identifier'], fixture['runtime_identifier']))
                self.assertIsNone(metadata['requested_device'], 'no model was requested; the fixture uses the default')
                self.assertEqual('failure' if cleanup_failure else 'success', fixture['cleanup_outcome'])
                self.assertEqual(cleanup_failure, 'cleanup_error' in fixture)
                self.assertTrue(metadata['simulator_signing']['verified'])
                self.assertEqual(list(smoke.APP_DISCOVERY_CHECKPOINT_NAMES) if discovery_only else
                                 list(smoke.PLANNED_CHECKPOINT_NAMES + smoke.APP_LANGUAGE_CHECKPOINT_NAMES),
                                 metadata['planned_checkpoint_names'])
                self.assertEqual(21, len(smoke.APP_DISCOVERY_CHECKPOINT_NAMES))
                for before, after in (('simulator-create', 'simulator-created-list'),
                                      ('simulator-created-list', 'prepare-languages'),
                                      ('app-discovery-index-log', 'simulator-created-shutdown'),
                                      ('spotlight-pipeline-log', 'simulator-created-shutdown'),
                                      ('export-attachments', 'simulator-created-shutdown'),
                                      ('simulator-created-shutdown', 'simulator-created-delete')):
                    self.assertLess(events.index(before), events.index(after))
                self.assertNotIn('record-start', events, 'video is recorded only for a requested clip')
                self.assertEqual(metadata_in_flight['simulator_fixture'], fixture)

    def test_checkpoint_export_failure_keeps_native_error_and_owned_teardown(self):
        original_copy = smoke.shutil.copy2
        for export_failure in ('malformed-manifest', 'copy-error'):
            for native_failure in (False, True):
                with self.subTest(export_failure=export_failure, native_failure=native_failure), \
                        tempfile.TemporaryDirectory() as temporary:
                    directory = Path(temporary)
                    events = []
                    created_name = None
                    def native(_directory, label, command, _timeout):
                        nonlocal created_name
                        events.append(label)
                        output = signing_fixture(label)
                        if label == 'simulator-list':
                            output = json.dumps(self.source_payload())
                        elif label == 'simulator-runtimes':
                            output = json.dumps(self.runtimes_payload())
                        elif label == 'simulator-create':
                            created_name = command[3]
                            output = self.created_id
                        elif label in ('simulator-created-list', 'simulator-created-state'):
                            output = json.dumps({'devices': {self.runtime_id: [dict(
                                name=created_name, udid=self.created_id, state='Shutdown', isAvailable=True,
                                deviceTypeIdentifier=self.device_type)]}})
                        elif label == 'xcodebuild-test':
                            (directory / 'Acceptance.xcresult').mkdir()
                            (directory / 'DerivedData').mkdir()
                            if native_failure:
                                raise smoke.NativeCommandError('original native assertion')
                        return subprocess.CompletedProcess(command, 0, output, '')
                    def export(_result, attachments, _directory):
                        events.append('export-attachments')
                        attachments.mkdir()
                        manifest = attachments / 'manifest.json'
                        if export_failure == 'malformed-manifest':
                            manifest.write_text('{broken')
                        else:
                            (attachments / 'source.png').write_bytes(b'png')
                            manifest.write_text(json.dumps([{'attachments': [{
                                'exportedFileName': 'source.png', 'suggestedHumanReadableName': 'home-start_1.png'}]}]))
                    def stop(_directory, _recording):
                        (directory / 'clip.mp4').write_bytes(b'mp4')
                    with patch.dict(os.environ, {'GITHUB_ACTIONS': 'true'}), \
                            patch.object(smoke.subprocess, 'check_output', return_value='a' * 40), \
                            patch.object(smoke, 'run_command', side_effect=native), \
                            patch.object(smoke, 'prepare_disposable_languages'), \
                            patch.object(smoke, 'verify_built_app_names'), \
                            patch.object(smoke, 'start_recording', return_value=(Mock(), Mock())), \
                            patch.object(smoke, 'stop_recording', side_effect=stop), \
                            patch.object(smoke, '_export_xcresult_attachments', side_effect=export), \
                            patch.object(smoke.shutil, 'copy2', side_effect=OSError('screenshot copy failed')
                                         if export_failure == 'copy-error' else original_copy):
                        expected = 'original native assertion' if native_failure else 'Native acceptance evidence export is incomplete'
                        with self.assertRaisesRegex(ValueError, expected):
                            smoke.run(directory, verify_app_names=True, runtime='iOS 26.4', fresh_ci_simulator=True)
                    metadata = json.loads((directory / 'metadata.json').read_text())
                    self.assertEqual('failure', metadata['export_outcome'])
                    self.assertEqual('success', metadata['simulator_fixture']['cleanup_outcome'])
                    self.assertIn('export_error', metadata)
                    if native_failure:
                        self.assertEqual('original native assertion', metadata['native_test_error'])
                    self.assertFalse((directory / 'DerivedData').exists())
                    self.assertLess(events.index('export-attachments'), events.index('simulator-created-delete'))
                    self.assertLess(events.index('spotlight-pipeline-log'), events.index('simulator-created-delete'))

    def test_teardown_attempts_metadata_after_unexpected_cleanup_error_and_removes_derived_data_after_write_error(self):
        original_write = Path.write_text
        for failure in ('cleanup', 'metadata-write'):
            with self.subTest(failure=failure), tempfile.TemporaryDirectory() as temporary:
                directory = Path(temporary)
                writes = []
                def native(_directory, label, command, _timeout):
                    output = signing_fixture(label)
                    if label == 'simulator-list':
                        output = json.dumps(self.source_payload())
                    if label == 'xcodebuild-test':
                        (directory / 'DerivedData').mkdir()
                        (directory / 'attachments').mkdir()
                    return subprocess.CompletedProcess(command, 0, output, '')
                def write(path, contents, *args, **kwargs):
                    writes.append(path)
                    if failure == 'metadata-write':
                        raise OSError('metadata disk full')
                    return original_write(path, contents, *args, **kwargs)
                def stop(_directory, _recording):
                    (directory / 'clip.mp4').write_bytes(b'mp4')
                with patch.object(smoke.subprocess, 'check_output', return_value='a' * 40), \
                        patch.object(smoke, 'run_command', side_effect=native), \
                        patch.object(smoke, 'start_recording', return_value=(Mock(), Mock())), \
                        patch.object(smoke, 'stop_recording', side_effect=stop), \
                        patch.object(smoke, '_export_named_checkpoints', return_value=[]), \
                        patch.object(smoke, 'cleanup_ci_simulator', side_effect=RuntimeError('unexpected cleanup failure')
                                     if failure == 'cleanup' else None) as cleanup, \
                        patch.object(Path, 'write_text', autospec=True, side_effect=write):
                    with self.assertRaisesRegex(RuntimeError if failure == 'cleanup' else OSError,
                                                'unexpected cleanup failure' if failure == 'cleanup' else 'metadata disk full'):
                        smoke.run(directory, runtime='iOS 26.4')
                cleanup.assert_called_once()
                self.assertEqual([directory / 'metadata.json'], writes)
                self.assertFalse((directory / 'DerivedData').exists())
                if failure == 'cleanup':
                    metadata = json.loads((directory / 'metadata.json').read_text())
                    self.assertEqual('failure', metadata['export_outcome'])


class NativeCommandTests(unittest.TestCase):
    def test_command_logs_output_and_rejects_failure_with_process_diagnostics(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            failed = subprocess.CompletedProcess(['xcodebuild'], 65, stdout='build output', stderr='compile error')
            fake_process = Mock()
            fake_process.communicate.return_value = ('build output', 'compile error')
            fake_process.returncode = 65
            with patch.object(smoke.subprocess, 'Popen', return_value=fake_process), \
                    patch.object(smoke.subprocess, 'run', return_value=subprocess.CompletedProcess([], 0, 'pid list', '')):
                with self.assertRaisesRegex(smoke.NativeCommandError, 'exited 65'):
                    smoke.run_command(directory, 'build', ['xcodebuild'], 20)
            self.assertIn('compile error', (directory / 'build.log').read_text())
            self.assertEqual('pid list', (directory / 'build-processes.log').read_text())

    @unittest.skipUnless(os.name == 'posix', 'process-group cleanup requires POSIX')
    def test_timeout_kills_child_processes_before_returning(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            heartbeat = directory / 'child-heartbeat'
            child = "import pathlib,time; p=pathlib.Path(%r); " % str(heartbeat) + \
                    "exec(\"while True: p.open('a').write('x'); time.sleep(.02)\")"
            parent = "import subprocess,sys,time; subprocess.Popen([sys.executable, '-c', %r]); time.sleep(30)" % child
            with patch.object(smoke, '_diagnose_processes'):
                with self.assertRaisesRegex(smoke.NativeCommandError, 'timed out after 0.5s'):
                    smoke.run_command(directory, 'bounded', [sys.executable, '-c', parent], 0.5)
            first = heartbeat.read_text()
            time.sleep(0.1)
            self.assertEqual(first, heartbeat.read_text())

    @unittest.skipUnless(os.name == 'posix', 'process-group cleanup requires POSIX')
    def test_denied_group_kill_bounds_inherited_pipes_and_preserves_timeout_logs(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            child_pid = directory / 'child.pid'
            child = "import pathlib,time; pathlib.Path(%r).write_text(str(__import__('os').getpid())); time.sleep(30)" % str(child_pid)
            parent = "import subprocess,sys,time; print('partial stdout', flush=True); " + \
                     "print('partial stderr', file=sys.stderr, flush=True); " + \
                     "subprocess.Popen([sys.executable, '-c', %r]); time.sleep(30)" % child
            def denied_killpg(_pid, _signal):
                raise PermissionError('group signal denied')

            def diagnostics(path, label):
                (path / f'{label}-processes.log').write_text('process list captured')

            started = time.monotonic()
            try:
                with patch.object(smoke.os, 'killpg', side_effect=denied_killpg), \
                        patch.object(smoke, '_diagnose_processes', side_effect=diagnostics):
                    with self.assertRaisesRegex(smoke.NativeCommandError, 'timed out after 1s'):
                        smoke.run_command(directory, 'bounded', [sys.executable, '-c', parent], 1)
                self.assertLess(time.monotonic() - started, 10)
                log = (directory / 'bounded.log').read_text()
                self.assertIn('partial stdout', log)
                self.assertIn('partial stderr', log)
                self.assertIn('group signal denied', log)
                self.assertEqual('process list captured', (directory / 'bounded-processes.log').read_text())
                self.assertTrue(child_pid.is_file())
            finally:
                if child_pid.exists():
                    try:
                        os.kill(int(child_pid.read_text()), signal.SIGKILL)
                    except ProcessLookupError:
                        pass

    def test_nonzero_command_output_is_preserved(self):
        with tempfile.TemporaryDirectory() as temporary:
            with patch.object(smoke.subprocess, 'Popen') as popen, patch.object(smoke, '_diagnose_processes'):
                process = popen.return_value
                process.communicate.return_value = ('stdout detail', 'stderr detail')
                process.returncode = 65
                with self.assertRaisesRegex(smoke.NativeCommandError, 'stderr detail'):
                    smoke.run_command(Path(temporary), 'native', ['xcodebuild'], 10)
            log = (Path(temporary) / 'native.log').read_text()
            self.assertIn('stdout detail', log)
            self.assertIn('stderr detail', log)

    def test_simulator_selection_reuses_booted_phone_else_latest_17_pro(self):
        payload = {'devices': {
            'com.apple.CoreSimulator.SimRuntime.iOS-26-4': [
                {'name': 'iPhone 17 Pro', 'udid': 'newer', 'state': 'Shutdown', 'isAvailable': True}],
            'com.apple.CoreSimulator.SimRuntime.iOS-26-2': [
                {'name': 'iPhone 16', 'udid': 'booted', 'state': 'Booted', 'isAvailable': True}],
        }}
        self.assertEqual('booted', smoke.select_simulator(payload)['udid'])
        payload['devices']['com.apple.CoreSimulator.SimRuntime.iOS-26-2'][0]['state'] = 'Shutdown'
        self.assertEqual('newer', smoke.select_simulator(payload)['udid'])
        with self.assertRaisesRegex(ValueError, 'No available'):
            smoke.select_simulator({'devices': {}})

    def test_requested_model_reuses_only_a_booted_phone_of_that_model(self):
        payload = {'devices': {
            'com.apple.CoreSimulator.SimRuntime.iOS-27-0': [
                dict(name='iPhone 18 Pro', udid='booted-pro', state='Booted', isAvailable=True)],
            'com.apple.CoreSimulator.SimRuntime.iOS-27-1': [
                dict(name='iPhone Duo', udid='duo', state='Shutdown', isAvailable=True)],
        }}
        self.assertEqual('booted-pro', smoke.select_simulator(payload)['udid'])
        self.assertEqual('booted-pro', smoke.select_simulator(payload, device_name='iPhone 18 Pro')['udid'])
        with self.assertRaisesRegex(ValueError, r'Booted iPhone \(iPhone 18 Pro\) is not the requested iPhone Duo'):
            smoke.select_simulator(payload, device_name='iPhone Duo')
        payload['devices']['com.apple.CoreSimulator.SimRuntime.iOS-27-0'][0]['state'] = 'Shutdown'
        self.assertEqual('duo', smoke.select_simulator(payload, device_name='iPhone Duo')['udid'])
        with self.assertRaisesRegex(ValueError, 'No available booted iPhone or iPhone 17 Pro'):
            smoke.select_simulator(payload)

    def test_explicit_runtime_selects_existing_exact_17_pro_instead_of_newer_runtime(self):
        payload = {'devices': {
            'com.apple.CoreSimulator.SimRuntime.iOS-26-4': [
                dict(name='iPhone 17 Pro', udid='requested', state='Shutdown', isAvailable=True)],
            'com.apple.CoreSimulator.SimRuntime.iOS-26-5': [
                dict(name='iPhone 17 Pro', udid='newer', state='Shutdown', isAvailable=True)],
        }}
        self.assertEqual('newer', smoke.select_simulator(payload)['udid'])
        selected = smoke.select_simulator(payload, requested_runtime='iOS 26.4')
        self.assertEqual(('requested', 'iOS 26.4'), (selected['udid'], selected['runtime']))

    def test_explicit_runtime_reuses_matching_booted_phone_and_rejects_conflict(self):
        payload = {'devices': {
            'com.apple.CoreSimulator.SimRuntime.iOS-26-4': [
                dict(name='iPhone 16', udid='booted', state='Booted', isAvailable=True),
                dict(name='iPhone 17 Pro', udid='shutdown', state='Shutdown', isAvailable=True)],
            'com.apple.CoreSimulator.SimRuntime.iOS-26-5': [
                dict(name='iPhone 17 Pro', udid='requested-shutdown', state='Shutdown', isAvailable=True)],
        }}
        self.assertEqual('booted', smoke.select_simulator(payload, requested_runtime='iOS 26.4')['udid'])
        with self.assertRaisesRegex(ValueError, 'Booted iPhone booted uses iOS 26.4, not requested iOS 26.5'):
            smoke.select_simulator(payload, requested_runtime='iOS 26.5')

    def test_explicit_runtime_requires_available_exact_17_pro_without_fallback(self):
        for requested_devices in ([],
                                  [dict(name='iPhone 17 Pro', udid='unavailable', state='Shutdown', isAvailable=False)],
                                  [dict(name='iPhone 17 Pro Max', udid='wrong-model', state='Shutdown', isAvailable=True)]):
            payload = {'devices': {
                'com.apple.CoreSimulator.SimRuntime.iOS-26-4': requested_devices,
                'com.apple.CoreSimulator.SimRuntime.iOS-26-5': [
                    dict(name='iPhone 17 Pro', udid='newer', state='Shutdown', isAvailable=True)],
            }}
            with self.subTest(devices=requested_devices), self.assertRaisesRegex(ValueError, 'requested runtime iOS 26.4'):
                smoke.select_simulator(payload, requested_runtime='iOS 26.4')
        with self.assertRaisesRegex(ValueError, 'requested runtime iOS-26-4'):
            smoke.select_simulator(payload, requested_runtime='iOS-26-4')

    def test_runtime_selection_failure_records_request_before_any_simulator_mutation(self):
        for payload in ({'devices': {}}, {'devices': {
                'com.apple.CoreSimulator.SimRuntime.iOS-26-5': [
                    dict(name='iPhone 17 Pro', udid='booted', state='Booted', isAvailable=True)],
                'com.apple.CoreSimulator.SimRuntime.iOS-26-4': [
                    dict(name='iPhone 17 Pro', udid='requested-shutdown', state='Shutdown', isAvailable=True)]}}):
            with self.subTest(payload=payload), tempfile.TemporaryDirectory() as temporary:
                directory = Path(temporary)
                with patch.object(smoke.subprocess, 'check_output', return_value='a' * 40), \
                        patch.object(smoke, 'run_command', return_value=subprocess.CompletedProcess(
                            [], 0, json.dumps(payload), '')) as native, \
                        patch.object(smoke, 'prepare_disposable_languages') as prepare, \
                        patch.object(smoke, 'start_recording') as recording:
                    with self.assertRaises(ValueError):
                        smoke.run(directory, verify_app_names=True, runtime='iOS 26.4')
                self.assertEqual(['simulator-list'], [call.args[1] for call in native.call_args_list])
                prepare.assert_not_called()
                recording.assert_not_called()
                metadata = json.loads((directory / 'metadata.json').read_text())
                self.assertEqual('iOS 26.4', metadata['requested_runtime'])
                self.assertNotIn('simulator_id', metadata)
                self.assertNotIn('runtime', metadata)
                self.assertEqual('failure', metadata['journey_outcome'])
                self.assertEqual('failure', metadata['export_outcome'])

    def test_video_recording_is_stopped_with_sigint_and_log_is_closed(self):
        with tempfile.TemporaryDirectory() as temporary:
            process = Mock()
            process.poll.return_value = None
            process.returncode = -signal.SIGINT
            with patch.object(smoke.subprocess, 'Popen', return_value=process), patch.object(smoke.time, 'sleep'):
                recording = smoke.start_recording(Path(temporary), 'sim-id', Path(temporary) / 'journey.mp4')
            smoke.stop_recording(Path(temporary), recording)
            process.send_signal.assert_called_once_with(signal.SIGINT)
            process.wait.assert_called_once_with(timeout=30)
            self.assertTrue(recording[1].closed)

    def test_multi_display_model_records_its_mapped_display(self):
        with tempfile.TemporaryDirectory() as temporary:
            process = Mock()
            process.poll.return_value = None
            with patch.object(smoke.subprocess, 'Popen', return_value=process) as popen, \
                    patch.object(smoke.time, 'sleep'):
                recording = smoke.start_recording(Path(temporary), 'sim-id', Path(temporary) / 'clip.mp4',
                                                  display=smoke.RECORDING_DISPLAYS['iPhone Duo'])
                recording[1].close()
                smoke.start_recording(Path(temporary), 'sim-id', Path(temporary) / 'clip.mp4')[1].close()
            duo, single = (call.args[0] for call in popen.call_args_list)
            self.assertEqual(['xcrun', 'simctl', 'io', 'sim-id', 'recordVideo', '--codec=h264', '--display=primary',
                              str(Path(temporary) / 'clip.mp4')], duo)
            self.assertNotIn('--display', ' '.join(single))
        self.assertEqual({'iPhone Duo': 'primary'}, smoke.RECORDING_DISPLAYS)

    def test_requested_clip_on_iphone_duo_records_the_outer_display(self):
        clip_test = 'WhoGaveWhatUITests/AdaptiveGiftJourneyUITests/testAdaptiveGiftJourney'
        runtime_id = 'com.apple.CoreSimulator.SimRuntime.iOS-27-1'
        duo_type = 'com.apple.CoreSimulator.SimDeviceType.iPhone-Duo'
        created_id = '11111111-2222-3333-4444-555555555555'
        for fresh in (False, True):
            with self.subTest(fresh=fresh), tempfile.TemporaryDirectory() as temporary:
                directory = Path(temporary)
                displays = []
                created_name = None

                def native(_directory, label, command, _timeout, **_kwargs):
                    nonlocal created_name
                    output = signing_fixture(label)
                    if label == 'simulator-list':
                        devices = [] if fresh else [dict(name='iPhone Duo', udid='duo-id', state='Booted', isAvailable=True)]
                        output = json.dumps({'devices': {runtime_id: devices}})
                    elif label == 'simulator-runtimes':
                        output = json.dumps({'runtimes': [dict(
                            name='iOS 27.1', identifier=runtime_id, isAvailable=True, buildversion='24A94425',
                            supportedDeviceTypes=[dict(name='iPhone Duo', identifier=duo_type)])]})
                    elif label == 'simulator-create':
                        created_name = command[3]
                        output = created_id + '\n'
                    elif label in ('simulator-created-list', 'simulator-created-state'):
                        output = json.dumps({'devices': {runtime_id: [dict(
                            name=created_name, udid=created_id, state='Shutdown', isAvailable=True,
                            deviceTypeIdentifier=duo_type)]}})
                    return subprocess.CompletedProcess(command, 0, output, '')

                def record(_directory, simulator_id, _video, display=None):
                    displays.append((simulator_id, display))
                    return Mock(), Mock()

                with patch.dict(os.environ, {'GITHUB_ACTIONS': 'true'}), \
                        patch.object(smoke.subprocess, 'check_output', return_value='a' * 40), \
                        patch.object(smoke, 'run_command', side_effect=native), \
                        patch.object(smoke, 'start_recording', side_effect=record), \
                        patch.object(smoke, 'stop_recording'), \
                        patch.object(smoke, 'verify_built_simulator_identity'):
                    with self.assertRaises(ValueError):
                        # No screenshots are exported here, so the evidence stays incomplete after the clip.
                        smoke.run(directory, runtime='iOS 27.1' if fresh else None, fresh_ci_simulator=fresh,
                                  video_test=clip_test, device_name='iPhone Duo')
                self.assertEqual([(created_id if fresh else 'duo-id', 'primary')], displays)

    def test_video_timeout_terminates_and_kills_stuck_recorder(self):
        with tempfile.TemporaryDirectory() as temporary:
            process = Mock()
            process.poll.return_value = None
            process.wait.side_effect = [subprocess.TimeoutExpired('recordVideo', 30),
                                        subprocess.TimeoutExpired('recordVideo', 5), None]
            process.returncode = -9
            with patch.object(smoke.subprocess, 'Popen', return_value=process), patch.object(smoke.time, 'sleep'), \
                    patch.object(smoke, '_diagnose_processes'):
                recording = smoke.start_recording(Path(temporary), 'sim-id', Path(temporary) / 'journey.mp4')
                with self.assertRaisesRegex(smoke.NativeCommandError, 'did not stop'):
                    smoke.stop_recording(Path(temporary), recording)
            process.terminate.assert_called_once()
            process.kill.assert_called_once()
            self.assertTrue(recording[1].closed)


class EvidenceExportTests(unittest.TestCase):
    def test_localization_drift_fails_acceptance_before_derived_data_cleanup(self):
        for drift in (False, True):
            with self.subTest(drift=drift), tempfile.TemporaryDirectory() as temporary:
                directory = Path(temporary).resolve()
                labels = []

                def native(_directory, label, command, timeout, **kwargs):
                    labels.append(label)
                    if label == 'simulator-list':
                        return subprocess.CompletedProcess(command, 0, json.dumps({'devices': {
                            'com.apple.CoreSimulator.SimRuntime.iOS-27-0': [
                                dict(name='iPhone 17 Pro', udid='sim-id', state='Booted', isAvailable=True)]}}), '')
                    if label == 'xcodebuild-test':
                        (directory / 'DerivedData').mkdir()
                        (directory / 'attachments').mkdir()
                    if label == 'localization-check':
                        self.assertTrue((directory / 'DerivedData').is_dir())
                        self.assertEqual(str(directory / 'DerivedData'), command[command.index('--derived-data') + 1])
                        self.assertIn('--check', command)
                        if drift:
                            raise smoke.NativeCommandError('String Catalog is out of sync')
                    return subprocess.CompletedProcess(command, 0, signing_fixture(label), '')

                with patch.object(smoke.subprocess, 'check_output', return_value='a' * 40), \
                        patch.object(smoke, 'run_command', side_effect=native), \
                        patch.object(smoke, '_export_named_checkpoints', return_value=[]):
                    if drift:
                        with self.assertRaisesRegex(smoke.NativeCommandError, 'String Catalog is out of sync'):
                            smoke.run(directory, check_localizations=True)
                    else:
                        smoke.run(directory, check_localizations=True)
                self.assertLess(labels.index('xcodebuild-test'), labels.index('localization-check'))
                self.assertFalse((directory / 'DerivedData').exists())
                metadata = json.loads((directory / 'metadata.json').read_text())
                self.assertEqual('failure' if drift else 'success', metadata['export_outcome'])

    def test_repeated_run_clears_stale_evidence_and_preserves_unrelated_files(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            result = directory / 'Acceptance.xcresult'
            generations = []
            test_number = 0

            def native(_directory, label, command, _timeout, **_kwargs):
                nonlocal test_number
                if label == 'simulator-list':
                    return subprocess.CompletedProcess(command, 0, json.dumps({'devices': {
                        'com.apple.CoreSimulator.SimRuntime.iOS-26-4': [
                            {'name': 'iPhone 17 Pro', 'udid': 'sim-id', 'state': 'Booted', 'isAvailable': True}]}}), '')
                if label == 'xcodebuild-test':
                    test_number += 1
                    self.assertFalse(result.exists(), 'runner must remove the previous result bundle before xcodebuild')
                    result.mkdir()
                    (result / 'generation').write_text(str(test_number))
                    generations.append(test_number)
                    if test_number == 2:
                        raise smoke.NativeCommandError('second native test failed')
                return subprocess.CompletedProcess(command, 0, signing_fixture(label), '')

            def make_recording(_directory, _simulator_id, _video_path, display=None):
                recorder = Mock()
                recorder.poll.return_value = None
                recorder.returncode = -signal.SIGINT
                log = (directory / 'record-video.log').open('w')
                return recorder, log

            real_stop_recording = smoke.stop_recording
            def stop_recording(_directory, recording):
                real_stop_recording(_directory, recording)
                if test_number == 1:
                    (directory / 'clip.mp4').write_bytes(b'first-run-video')

            def export(_result, attachments, _directory):
                attachments.mkdir(parents=True, exist_ok=True)
                names = (list(smoke.PLANNED_CHECKPOINT_NAMES) if test_number == 1 else ['home-start'])
                exported = []
                for index, name in enumerate(names):
                    filename = f'checkpoint-{index}.png'
                    (attachments / filename).write_bytes(b'new' if test_number == 2 else b'first')
                    exported.append({'exportedFileName': filename, 'suggestedHumanReadableName': name + '_1.png'})
                (attachments / 'manifest.json').write_text(json.dumps([{'attachments': exported}]))

            unrelated = directory / 'notes.txt'
            unrelated.write_text('keep this file')
            patches = (
                patch.object(smoke.subprocess, 'check_output', return_value='a' * 40),
                patch.object(smoke, 'run_command', side_effect=native),
                patch.object(smoke, 'start_recording', side_effect=make_recording),
                patch.object(smoke, 'stop_recording', side_effect=stop_recording),
                patch.object(smoke, '_export_xcresult_attachments', side_effect=export),
            )
            clip_test = 'WhoGaveWhatUITests/AdaptiveGiftJourneyUITests/testAdaptiveGiftJourney'
            with patches[0], patches[1], patches[2], patches[3], patches[4]:
                smoke.run(directory, video_test=clip_test)
                self.assertTrue((directory / 'clip.mp4').is_file())
                self.assertTrue((directory / 'attachments/person-edited.png').is_file())
                (directory / 'index.html').write_text('old successful report')
                for label in ('app-discovery-index-log', 'spotlight-pipeline-log',
                              'simulator-signing-info', 'simulator-signing-display', 'simulator-signing-verify'):
                    for suffix in ('.log', '-processes.log'):
                        (directory / f'{label}{suffix}').write_text('old-head diagnostics')
                with self.assertRaisesRegex(smoke.NativeCommandError, 'second native test failed'):
                    smoke.run(directory, video_test=clip_test)

            metadata = json.loads((directory / 'metadata.json').read_text())
            self.assertEqual([1, 2], generations)
            self.assertEqual('failure', metadata['journey_outcome'])
            self.assertNotEqual('success', metadata['export_outcome'])
            self.assertEqual('feature-acceptance', metadata['evidence_kind'])
            self.assertEqual(
                'Core journey: quick gift with an inferred icon, detailed gift, person add, edit, photo and delete, and Insights before and after This is me',
                metadata['scenario'],
            )
            self.assertFalse((directory / 'clip.mp4').exists())
            self.assertFalse((directory / 'index.html').exists())
            for label in ('app-discovery-index-log', 'spotlight-pipeline-log',
                          'simulator-signing-info', 'simulator-signing-display', 'simulator-signing-verify'):
                for suffix in ('.log', '-processes.log'):
                    self.assertFalse((directory / f'{label}{suffix}').exists())
            self.assertFalse((directory / 'attachments/person-edited.png').exists())
            self.assertEqual(b'new', (directory / 'attachments/home-start.png').read_bytes())
            self.assertEqual('2', (result / 'generation').read_text())
            self.assertEqual('keep this file', unrelated.read_text())

    def test_failed_native_journey_skips_requested_clip_and_preserves_result_and_metadata(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            result = directory / 'Acceptance.xcresult'
            metadata_path = directory / 'metadata.json'
            log = directory / 'recorder.log'
            log.touch()
            recorder = Mock()
            recorder.poll.return_value = None
            recorder.returncode = -signal.SIGINT
            recording = (recorder, log.open('w'))
            named = list(smoke.PLANNED_CHECKPOINT_NAMES)

            def native(directory, label, command, timeout, **kwargs):
                if label == 'simulator-list':
                    return subprocess.CompletedProcess(command, 0, json.dumps({'devices': {
                        'com.apple.CoreSimulator.SimRuntime.iOS-26-4': [
                            {'name': 'iPhone 17 Pro', 'udid': 'sim-id', 'state': 'Booted', 'isAvailable': True}]}}), '')
                if label == 'xcodebuild-test':
                    result.mkdir()
                    raise smoke.NativeCommandError('xcodebuild-test exited 65: assertion failed')
                return subprocess.CompletedProcess(command, 0, '', '')

            def export(_result, attachments, _directory):
                attachments.mkdir(parents=True, exist_ok=True)
                exported = []
                for index, name in enumerate(named):
                    filename = f'{index}.png'
                    (attachments / filename).write_bytes(b'png')
                    exported.append({'exportedFileName': filename, 'suggestedHumanReadableName': name + '_1.png'})
                (attachments / 'manifest.json').write_text(json.dumps([{'attachments': exported}]))

            with patch.object(smoke.subprocess, 'check_output', return_value='a' * 40), \
                    patch.object(smoke, 'run_command', side_effect=native), \
                    patch.object(smoke, 'start_recording', return_value=recording) as start, \
                    patch.object(smoke, '_export_xcresult_attachments', side_effect=export):
                with self.assertRaisesRegex(smoke.NativeCommandError, 'assertion failed'):
                    smoke.run(directory, video_test='WhoGaveWhatUITests/AdaptiveGiftJourneyUITests/testAdaptiveGiftJourney')
            start.assert_not_called()
            metadata = json.loads(metadata_path.read_text())
            self.assertEqual('failure', metadata['journey_outcome'])
            self.assertIn('assertion failed', metadata['native_test_error'])
            self.assertEqual(len(named), len(metadata['checkpoints']))
            self.assertTrue((result).is_dir())
            self.assertTrue((directory / 'attachments/home-start.png').is_file())
            self.assertFalse((directory / 'clip.mp4').exists())

    def test_requested_clip_records_one_built_test_after_the_suite_passes(self):
        clip_test = 'WhoGaveWhatUITests/AdaptiveGiftJourneyUITests/testAdaptiveGiftJourney'
        named = list(smoke.PLANNED_CHECKPOINT_NAMES)
        for clip_failure in (False, True):
            with self.subTest(clip_failure=clip_failure), tempfile.TemporaryDirectory() as temporary:
                directory = Path(temporary)
                events = []

                def native(_directory, label, command, _timeout, **_kwargs):
                    events.append(label)
                    if label == 'simulator-list':
                        return subprocess.CompletedProcess(command, 0, json.dumps({'devices': {
                            'com.apple.CoreSimulator.SimRuntime.iOS-26-4': [
                                {'name': 'iPhone 17 Pro', 'udid': 'sim-id', 'state': 'Booted', 'isAvailable': True}]}}), '')
                    if label == 'xcodebuild-test':
                        (directory / 'Acceptance.xcresult').mkdir()
                        self.assertNotIn(f'-only-testing:{clip_test}', command)
                    if label == 'xcodebuild-clip':
                        self.assertEqual(['xcodebuild', 'test-without-building'], command[:2])
                        self.assertIn('-collect-test-diagnostics never', ' '.join(command))
                        self.assertIn(f'-only-testing:{clip_test}', command)
                        self.assertIn(str(directory / 'Clip.xcresult'), command)
                        if clip_failure:
                            raise smoke.NativeCommandError('clip test failed')
                    return subprocess.CompletedProcess(command, 0, signing_fixture(label), '')

                def record(_directory, _simulator_id, video, display=None):
                    self.assertEqual(directory / 'clip.mp4', video)
                    self.assertIsNone(display, 'a single-display iPhone records its only display')
                    events.append('record-start')
                    return Mock(), Mock()

                def stop(_directory, _recording):
                    events.append('record-stop')
                    (directory / 'clip.mp4').write_bytes(b'mp4')

                def export(_result, attachments, _directory):
                    attachments.mkdir(parents=True, exist_ok=True)
                    exported = []
                    for index, name in enumerate(named):
                        (attachments / f'{index}.png').write_bytes(b'png')
                        exported.append({'exportedFileName': f'{index}.png', 'suggestedHumanReadableName': name + '_1.png'})
                    (attachments / 'manifest.json').write_text(json.dumps([{'attachments': exported}]))

                with patch.object(smoke.subprocess, 'check_output', return_value='a' * 40), \
                        patch.object(smoke, 'run_command', side_effect=native), \
                        patch.object(smoke, 'start_recording', side_effect=record), \
                        patch.object(smoke, 'stop_recording', side_effect=stop), \
                        patch.object(smoke, '_export_xcresult_attachments', side_effect=export):
                    if clip_failure:
                        with self.assertRaisesRegex(ValueError, 'clip test failed'):
                            smoke.run(directory, video_test=clip_test)
                    else:
                        smoke.run(directory, video_test=clip_test)
                metadata = json.loads((directory / 'metadata.json').read_text())
                self.assertEqual(clip_test, metadata['video_test'])
                self.assertEqual('success', metadata['journey_outcome'])
                self.assertEqual('failure' if clip_failure else 'success', metadata['export_outcome'])
                self.assertEqual(clip_failure, 'video_error' in metadata)
                self.assertLess(events.index('xcodebuild-test'), events.index('record-start'))
                self.assertLess(events.index('record-start'), events.index('xcodebuild-clip'))
                self.assertLess(events.index('xcodebuild-clip'), events.index('record-stop'))
                self.assertEqual(1, events.count('record-stop'))

    def test_video_test_must_name_one_ui_test_method(self):
        for video_test, discovery_only in (('WhoGaveWhatUITests', False), ('WhoGaveWhatTests/Foo/testBar', False),
                                           ('WhoGaveWhatUITests/Foo/testBar -quiet', False),
                                           ('WhoGaveWhatUITests/Foo/testBar', True)):
            with self.subTest(video_test=video_test), tempfile.TemporaryDirectory() as temporary, \
                    patch.object(smoke, 'run_command') as native:
                with self.assertRaisesRegex(ValueError, '--video-test'):
                    smoke.run(Path(temporary), verify_app_names=True, discovery_only=discovery_only,
                              video_test=video_test)
                native.assert_not_called()

    def test_exports_xcresult_and_maps_named_screenshots(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            result = directory / 'Acceptance.xcresult'
            result.mkdir()
            attachments = directory / 'attachments'
            def export(command, **kwargs):
                attachments.mkdir(exist_ok=True)
                names = list(smoke.PLANNED_CHECKPOINT_NAMES)
                exported = []
                for index, name in enumerate(names):
                    filename = f'checkpoint-{index}.png'
                    (attachments / filename).write_bytes(b'png')
                    exported.append({'exportedFileName': filename, 'suggestedHumanReadableName': f'{name}_1.png'})
                (attachments / 'manifest.json').write_text(json.dumps([{'attachments': exported}]))
                return subprocess.CompletedProcess(command, 0, '', '')
            metadata = {'planned_checkpoint_names': list(smoke.PLANNED_CHECKPOINT_NAMES), 'checkpoints': []}
            process = Mock()
            process.returncode = 0
            process.communicate.side_effect = lambda timeout: (export([], timeout=timeout) and ('', ''))
            with patch.object(smoke.subprocess, 'Popen', return_value=process):
                smoke._export_xcresult_attachments(result, attachments, directory)
            self.assertEqual([], smoke._export_named_checkpoints(directory, metadata))
            self.assertTrue((attachments / 'home-start.png').is_file())
            self.assertEqual('home-start', metadata['checkpoints'][0]['name'])

    def test_named_checkpoint_does_not_match_a_longer_prefixed_name(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            attachments = directory / 'attachments'
            attachments.mkdir()
            # xcresult lists later attachments first, so the dark capture precedes the light one.
            exported = []
            for filename, name in [('dark.png', 'dark-people_0_B.png'), ('light.png', 'people_0_A.png')]:
                (attachments / filename).write_bytes(filename.encode())
                exported.append({'exportedFileName': filename, 'suggestedHumanReadableName': name})
            (attachments / 'manifest.json').write_text(json.dumps([{'attachments': exported}]))
            metadata = {'planned_checkpoint_names': ['people', 'dark-people'], 'checkpoints': [], 'evidence_kind': 'diagnostic'}
            self.assertEqual([], smoke._export_named_checkpoints(directory, metadata))
            self.assertEqual(b'light.png', (attachments / 'people.png').read_bytes())
            self.assertEqual(b'dark.png', (attachments / 'dark-people.png').read_bytes())

    def test_attachment_export_failure_is_not_hidden(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            process = Mock()
            process.returncode = 1
            process.communicate.return_value = ('', 'xcresult failed')
            with patch.object(smoke.subprocess, 'Popen', return_value=process), \
                    patch.object(smoke, '_diagnose_processes'):
                with self.assertRaisesRegex(smoke.NativeCommandError, 'xcresult failed'):
                    smoke._export_xcresult_attachments(directory / 'a.xcresult', directory / 'attachments', directory)


class AppDiscoveryAcceptanceTests(unittest.TestCase):
    def test_built_localized_names_and_activity_declaration_are_checked(self):
        with tempfile.TemporaryDirectory() as temporary:
            metadata = {}
            def native(_directory, label, command, timeout):
                if label == 'bundle-info':
                    payload = {'NSUserActivityTypes': ['com.apple.corespotlightitem']}
                elif label.startswith('bundle-spotlight-name-'):
                    payload = {'app-discovery.display-name': 'Who Gave · кто че'}
                else:
                    name = 'Who Gave' if label == 'bundle-names-en' else 'кто че'
                    payload = {'CFBundleDisplayName': name, 'CFBundleName': name}
                self.assertEqual(30, timeout)
                self.assertEqual(['plutil', '-convert', 'xml1', '-o', '-'], command[:5])
                return subprocess.CompletedProcess(command, 0, plistlib.dumps(payload).decode(), '')
            with patch.object(smoke, 'run_command', side_effect=native) as command:
                smoke.verify_built_app_names(Path(temporary), metadata)
            self.assertEqual({'en': 'Who Gave', 'ru': 'кто че'}, metadata['bundle_names'])
            self.assertEqual(5, command.call_count)

    def test_wrong_compiled_name_or_missing_activity_cannot_pass_acceptance(self):
        for failure in ('CFBundleName', 'CFBundleDisplayName', 'activity', 'spotlight-name'):
            with self.subTest(failure=failure), tempfile.TemporaryDirectory() as temporary:
                def native(_directory, label, command, timeout):
                    if label == 'bundle-info':
                        payload = {'NSUserActivityTypes': [] if failure == 'activity' else ['com.apple.corespotlightitem']}
                    elif label.startswith('bundle-spotlight-name-'):
                        payload = {'app-discovery.display-name': 'Wrong name' if failure == 'spotlight-name' else 'Who Gave · кто че'}
                    else:
                        name = 'Who Gave' if label == 'bundle-names-en' else 'кто че'
                        payload = {'CFBundleDisplayName': name, 'CFBundleName': name}
                        if label == 'bundle-names-ru' and failure in ('CFBundleName', 'CFBundleDisplayName'):
                            payload[failure] = 'Wrong name'
                    return subprocess.CompletedProcess(command, 0, plistlib.dumps(payload).decode(), '')
                expected_error = {
                    'CFBundleName': 'Built ru app names do not match',
                    'CFBundleDisplayName': 'Built ru app names do not match',
                    'activity': 'Built app does not declare its Spotlight activity type',
                    'spotlight-name': 'Built en Spotlight display name does not preserve both public names',
                }[failure]
                metadata = {}
                with patch.object(smoke, 'run_command', side_effect=native), self.assertRaisesRegex(ValueError, expected_error):
                    smoke.verify_built_app_names(Path(temporary), metadata)
                self.assertNotIn('bundle_names', metadata)

    def test_disposable_language_journey_is_opt_in_and_requires_all_feature_checkpoints(self):
        for verify, discovery_only in ((False, False), (True, False), (True, True)):
            with self.subTest(verify=verify, discovery_only=discovery_only), tempfile.TemporaryDirectory() as temporary:
                directory = Path(temporary)
                test_commands = []
                native_labels = []
                events = []
                requested_runtime = 'iOS 26.4' if verify else None
                def prepare(_directory, _simulator, _metadata):
                    events.append('prepare-languages')
                def native(_directory, label, command, timeout):
                    native_labels.append(label)
                    if label == 'simulator-list':
                        selected_runtime = 'com.apple.CoreSimulator.SimRuntime.iOS-26-4' if verify else 'com.apple.CoreSimulator.SimRuntime.iOS-26-5'
                        payload = {'devices': {selected_runtime: [
                            dict(name='iPhone 17 Pro', udid='sim-id', state='Booted', isAvailable=True)]}}
                        return subprocess.CompletedProcess(command, 0, json.dumps(payload), '')
                    if label == 'xcodebuild-test':
                        self.assertEqual(900 if discovery_only else 1800, timeout)
                        test_commands.append(command)
                        events.append('xcodebuild-test')
                        raise smoke.NativeCommandError('native assertion failed')
                    if label == 'app-discovery-index-log':
                        self.assertEqual(['xcrun', 'simctl', 'spawn', 'sim-id', 'log', 'show'], command[:6])
                        self.assertEqual(30, timeout)
                        self.assertIn('20m', command)
                        self.assertEqual('subsystem == "pro.ziganshin.WhoGaveWhat" AND category == "AppDiscovery"', command[-1])
                        raise smoke.NativeCommandError('diagnostic log unavailable')
                    if label == 'spotlight-pipeline-log':
                        self.assertEqual(['xcrun', 'simctl', 'spawn', 'sim-id', 'log', 'show'], command[:6])
                        self.assertEqual(30, timeout)
                        self.assertIn('20m', command)
                        self.assertIn('"pro.ziganshin.WhoGaveWhat"', command[-1])
                        self.assertIn('process == "corespotlightd"', command[-1])
                        raise smoke.NativeCommandError('pipeline log unavailable')
                    return subprocess.CompletedProcess(command, 0, '', '')
                with patch.object(smoke.subprocess, 'check_output', return_value='a' * 40), \
                        patch.object(smoke, 'run_command', side_effect=native), \
                        patch.object(smoke, 'prepare_disposable_languages', side_effect=prepare), \
                        patch.object(smoke, 'start_recording', return_value=(Mock(), Mock())), \
                        patch.object(smoke, 'stop_recording'):
                    with self.assertRaisesRegex(smoke.NativeCommandError, 'native assertion failed'):
                        smoke.run(directory, verify_app_names=verify, discovery_only=discovery_only, runtime=requested_runtime)
                metadata = json.loads((directory / 'metadata.json').read_text())
                self.assertEqual(requested_runtime, metadata['requested_runtime'])
                self.assertEqual('iOS 26.4' if verify else 'iOS 26.5', metadata['runtime'])
                self.assertEqual('sim-id', metadata['simulator_id'])
                self.assertIn('platform=iOS Simulator,id=sim-id', test_commands[0])
                self.assertEqual(['prepare-languages', 'xcodebuild-test'] if verify else ['xcodebuild-test'], events)
                self.assertEqual(not verify, 'simulator-bootstatus' in native_labels)
                self.assertNotIn('simulator-boot', native_labels)
                self.assertEqual(verify, 'app-discovery-index-log' in native_labels)
                self.assertEqual(verify, 'app_discovery_diagnostic_error' in metadata)
                self.assertEqual(verify, 'spotlight-pipeline-log' in native_labels)
                self.assertEqual(verify, 'spotlight_pipeline_diagnostic_error' in metadata)
                self.assertIn('native assertion failed', metadata['native_test_error'])
                self.assertEqual(discovery_only, f'-only-testing:{smoke.SPOTLIGHT_DIAGNOSTIC_TEST}' in test_commands[0])
                self.assertEqual(verify and not discovery_only, f'-skip-testing:{smoke.SPOTLIGHT_DIAGNOSTIC_TEST}' in test_commands[0])
                self.assertEqual('diagnostic' if discovery_only else 'feature-acceptance', metadata['evidence_kind'])
                if discovery_only:
                    self.assertEqual(list(smoke.APP_DISCOVERY_CHECKPOINT_NAMES), metadata['planned_checkpoint_names'])
                    self.assertIn('partial suite; not acceptance', metadata['native_test'])
                skipped = '-skip-testing:WhoGaveWhatUITests/AppDiscoveryUITests' in test_commands[0]
                self.assertEqual(not verify, skipped)
                required = smoke.APP_DISCOVERY_CHECKPOINT_NAMES if discovery_only else smoke.APP_LANGUAGE_CHECKPOINT_NAMES
                for checkpoint in required:
                    self.assertEqual(verify, checkpoint in metadata['planned_checkpoint_names'])
                    self.assertEqual(verify, checkpoint in metadata['missing_checkpoints'])
                if verify:
                    self.assertEqual('pending', metadata['spotlight_device_acceptance'])
                    self.assertEqual('failure' if discovery_only else 'not-run', metadata['spotlight_search_outcome'])
                    self.assertEqual('os-spotlight-diagnostic' if discovery_only else 'app-owned', metadata['acceptance_scope'])
                if not discovery_only:
                    self.assertNotIn('spotlight-russian', metadata['planned_checkpoint_names'])
                    self.assertNotIn('app_discovery_queries', metadata)
                self.assertNotEqual('success', metadata['export_outcome'])

    def test_app_owned_acceptance_keeps_all_other_tests_and_requires_core_checkpoints(self):
        for missing_core in (False, True):
            with self.subTest(missing_core=missing_core), tempfile.TemporaryDirectory() as temporary:
                directory = Path(temporary)
                commands = []
                planned = list(smoke.PLANNED_CHECKPOINT_NAMES + smoke.APP_LANGUAGE_CHECKPOINT_NAMES)
                def native(_directory, label, command, _timeout):
                    if label == 'simulator-list':
                        payload = {'devices': {'runtime': [dict(
                            name='iPhone 17 Pro', udid='sim-id', state='Booted', isAvailable=True)]}}
                        output = json.dumps(payload)
                    elif label == 'xcodebuild-test':
                        commands.append(command)
                        (directory / 'Acceptance.xcresult').mkdir()
                        output = ''
                    else:
                        output = signing_fixture(label)
                    return subprocess.CompletedProcess(command, 0, output, '')
                def export(_result, attachments, _directory):
                    attachments.mkdir()
                    names = [name for name in planned if not missing_core or name != 'app-language-draft-resumed']
                    items = []
                    for index, name in enumerate(names):
                        filename = f'{index}.png'
                        (attachments / filename).write_bytes(b'png')
                        items.append({'exportedFileName': filename, 'suggestedHumanReadableName': f'{name}_1.png'})
                    (attachments / 'manifest.json').write_text(json.dumps([{'attachments': items}]))
                def stop(_directory, _recording):
                    (directory / 'clip.mp4').write_bytes(b'mp4')
                with patch.object(smoke.subprocess, 'check_output', return_value='a' * 40), \
                        patch.object(smoke, 'run_command', side_effect=native), \
                        patch.object(smoke, 'prepare_disposable_languages'), \
                        patch.object(smoke, 'start_recording', return_value=(Mock(), Mock())), \
                        patch.object(smoke, 'stop_recording', side_effect=stop), \
                        patch.object(smoke, 'verify_built_app_names') as resources, \
                        patch.object(smoke, '_export_xcresult_attachments', side_effect=export):
                    if missing_core:
                        with self.assertRaisesRegex(ValueError, 'evidence export is incomplete'):
                            smoke.run(directory, verify_app_names=True)
                    else:
                        smoke.run(directory, verify_app_names=True)
                    resources.assert_called_once()
                metadata = json.loads((directory / 'metadata.json').read_text())
                self.assertEqual([f'-skip-testing:{smoke.SPOTLIGHT_DIAGNOSTIC_TEST}'],
                                 [arg for arg in commands[0] if arg.startswith(('-skip-testing:', '-only-testing:'))])
                self.assertEqual(planned, metadata['planned_checkpoint_names'])
                self.assertEqual('app-owned', metadata['acceptance_scope'])
                self.assertEqual('not-run', metadata['spotlight_search_outcome'])
                self.assertEqual('pending', metadata['spotlight_device_acceptance'])
                self.assertNotIn('real Russian and English Spotlight launcher results', metadata['scenario'])
                self.assertEqual('success', metadata['journey_outcome'])
                self.assertEqual('failure' if missing_core else 'success', metadata['export_outcome'])
                if missing_core:
                    self.assertEqual(['app-language-draft-resumed'], metadata['missing_checkpoints'])
                else:
                    spec = importlib.util.spec_from_file_location('scope_report', Path(__file__).parents[1] / 'ui-evidence-report.py')
                    report = importlib.util.module_from_spec(spec)
                    spec.loader.exec_module(report)
                    report.render(directory)
                    self.assertIn('OS Spotlight search was not run; real-device Spotlight verification is pending',
                                  (directory / 'index.html').read_text())

    def test_discovery_only_requires_real_language_scenario_before_native_actions(self):
        with tempfile.TemporaryDirectory() as temporary, patch.object(smoke, 'run_command') as native:
            with self.assertRaisesRegex(ValueError, 'require --verify-app-names'):
                smoke.run(Path(temporary), discovery_only=True)
            native.assert_not_called()

    def test_successful_partial_diagnostic_exports_all_discovery_checkpoints(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            def native(_directory, label, command, _timeout):
                if label == 'simulator-list':
                    devices = {'devices': {'runtime': [dict(
                        name='iPhone 17 Pro', udid='sim-id', state='Booted', isAvailable=True)]}}
                    return subprocess.CompletedProcess(command, 0, json.dumps(devices), '')
                if label == 'xcodebuild-test':
                    (directory / 'Acceptance.xcresult').mkdir()
                return subprocess.CompletedProcess(command, 0, signing_fixture(label), '')
            def export(_result, attachments, _directory):
                attachments.mkdir()
                exported = []
                for index, name in enumerate(smoke.APP_DISCOVERY_CHECKPOINT_NAMES):
                    filename = f'{index}.png'
                    (attachments / filename).write_bytes(b'png')
                    exported.append({'exportedFileName': filename, 'suggestedHumanReadableName': f'{name}_1.png'})
                (attachments / 'manifest.json').write_text(json.dumps([{'attachments': exported}]))
            def stop(_directory, _recording):
                (directory / 'clip.mp4').write_bytes(b'mp4')
            with patch.object(smoke.subprocess, 'check_output', return_value='a' * 40), \
                    patch.object(smoke, 'run_command', side_effect=native), \
                    patch.object(smoke, 'prepare_disposable_languages'), \
                    patch.object(smoke, 'start_recording', return_value=(Mock(), Mock())), \
                    patch.object(smoke, 'stop_recording', side_effect=stop), \
                    patch.object(smoke, 'verify_built_app_names'), \
                    patch.object(smoke, '_export_xcresult_attachments', side_effect=export):
                smoke.run(directory, verify_app_names=True, discovery_only=True)
            metadata = json.loads((directory / 'metadata.json').read_text())
            self.assertEqual('diagnostic', metadata['evidence_kind'])
            self.assertEqual('passed-diagnostic', metadata['spotlight_search_outcome'])
            self.assertEqual('pending', metadata['spotlight_device_acceptance'])
            self.assertEqual('success', metadata['journey_outcome'])
            self.assertEqual('success', metadata['export_outcome'])
            self.assertNotIn('missing_checkpoints', metadata)
            self.assertEqual(list(smoke.APP_DISCOVERY_CHECKPOINT_NAMES), [item['name'] for item in metadata['checkpoints']])

    def test_manual_diagnostic_job_cannot_replace_required_full_suite(self):
        workflow = (Path(__file__).parents[2] / '.github/workflows/tests.yml').read_text()
        job_blocks = re.split(r'^  ([a-z-]+):\n', workflow.partition('\njobs:\n')[2], flags=re.MULTILINE)
        jobs = dict(zip(job_blocks[1::2], job_blocks[2::2]))
        self.assertEqual({'test', 'spotlight-diagnostics'}, set(jobs))
        self.assertNotIn('--discovery-only', jobs['test'])
        self.assertIn('- name: Unit tests and app smoke\n', jobs['test'])
        self.assertIn('- name: Unit tests and app smoke (iPhone 18 Pro)\n', jobs['test'])
        self.assertIn('fail-fast: false', jobs['test'])
        self.assertIn('run-app-smoke.py "$RUNNER_TEMP/ui-app-smoke" --verify-app-names', jobs['test'])
        # Video is opt-in: only a manual dispatch can name a clip, passed through the environment.
        self.assertIn("VIDEO_TEST: ${{ github.event_name == 'workflow_dispatch' && inputs.video_test || '' }}", jobs['test'])
        self.assertIn('${VIDEO_TEST:+--video-test "$VIDEO_TEST"}', jobs['test'])
        self.assertNotIn('${{ inputs.video_test }}', workflow)
        diagnostic = jobs['spotlight-diagnostics']
        self.assertIn("if: github.event_name == 'workflow_dispatch' && inputs.spotlight_diagnostics", diagnostic)
        self.assertIn('name: Spotlight diagnostics (non-acceptance)', diagnostic)
        self.assertIn('continue-on-error: true', diagnostic)
        self.assertNotIn('continue-on-error:', jobs['test'])
        self.assertIn('--verify-app-names --discovery-only', diagnostic)
        self.assertIn('device: iPhone Duo\n            runtime: iOS 27.1\n', jobs['test'])
        self.assertIn('device: iPhone 18 Pro\n            runtime: iOS 27.0\n', jobs['test'])
        self.assertIn('SIMULATOR_RUNTIME: iOS 27.1', diagnostic)
        self.assertIn('SIMULATOR_DEVICE: iPhone Duo', diagnostic)
        for job in (jobs['test'], diagnostic):
            self.assertIn('runs-on: xcode-27\n', job)
            self.assertIn('DEVELOPER_DIR: /Applications/Xcode_27.1.app/Contents/Developer', job)
            self.assertIn('scripts/install-simulator-runtime.sh "$SIMULATOR_RUNTIME" "$SIMULATOR_DEVICE"', job)
            self.assertIn('--runtime "$SIMULATOR_RUNTIME" --device "$SIMULATOR_DEVICE"', job)
        self.assertIn('--fresh-ci-simulator', jobs['test'])
        self.assertIn('--fresh-ci-simulator', diagnostic)
        self.assertIn('name: spotlight-diagnostics-attempt-', diagnostic)
        # Boot, testing, export, logging, and upload need headroom beyond the native test's 15 minutes.
        diagnostic_budget = int(re.search(r'timeout-minutes: (\d+)', diagnostic).group(1))
        self.assertGreaterEqual(diagnostic_budget, 45)

    def test_native_acceptance_runs_automatically_for_app_changes_and_preserves_pr_head_provenance(self):
        workflow = (Path(__file__).parents[2] / '.github/workflows/tests.yml').read_text()
        events = workflow.partition('\non:\n')[2].partition('\npermissions:\n')[0]
        non_app_paths = ("    paths-ignore:\n      - '*.md'\n      - '*.html'\n      - '.agents/**'\n"
                         "      - '.claude/**'\n      - 'docs/**'\n")
        self.assertIn('  push:\n    branches: [master]\n' + non_app_paths, events)
        self.assertIn('  pull_request:\n' + non_app_paths, events)
        self.assertIn('  workflow_dispatch:\n', events)
        self.assertNotIn('types:', events)
        self.assertNotIn('ci-ready', workflow)
        self.assertIn('cancel-in-progress: true', workflow)
        self.assertIn("group: tests-${{ github.event.pull_request.number && "
                      "format('pr-{0}', github.event.pull_request.number) || github.run_id }}", workflow)
        self.assertIn('HEAD_SHA: ${{ github.event.pull_request.head.sha || github.sha }}', workflow)
        self.assertIn('name: ${{ matrix.artifact }}-attempt-${{ github.run_attempt }}', workflow)
        self.assertIn('artifact: ui-app-smoke\n', workflow)
        self.assertIn('artifact: ui-iphone-smoke\n', workflow)

    def test_lightweight_checks_remain_automatic_with_the_existing_check_names_and_commands(self):
        workflow = (Path(__file__).parents[2] / '.github/workflows/checks.yml').read_text()
        self.assertIn('  push:\n    branches: [master]\n  pull_request:\n', workflow)
        self.assertIn('cancel-in-progress: true', workflow)
        self.assertIn('name: Scripts and secret patterns', workflow)
        self.assertIn('name: Swift format and lint', workflow)
        for command in ('scripts/check-secrets.sh', 'python3 -m unittest discover -s scripts/tests -v',
                        'bundle exec ruby "$test"', 'scripts/check-formatting.sh', 'scripts/lint-swift.sh'):
            self.assertIn(command, workflow)
        self.assertNotIn('run-app-smoke.py', workflow)
        self.assertNotRegex(workflow, re.compile(r'^    if:', re.MULTILINE))

    def test_evidence_gate_checks_publication_and_removal_from_a_trusted_body_edit(self):
        workflow = (Path(__file__).parents[2] / '.github/workflows/pr-evidence.yml').read_text()
        events = workflow.partition('\non:\n')[2].partition('\npermissions:\n')[0]
        self.assertEqual('  pull_request_target:\n    types: [edited]\n', events)
        self.assertIn('github.event.changes.body &&', workflow)
        self.assertIn("contains(github.event.pull_request.body, '<!-- visual-evidence:') ||", workflow)
        self.assertIn("contains(github.event.changes.body.from, '<!-- visual-evidence:')", workflow)
        self.assertIn('ref: ${{ github.event.pull_request.base.sha || github.event.repository.default_branch }}', workflow)
        self.assertIn('persist-credentials: false', workflow)
        self.assertIn('statuses: write', workflow)
        self.assertIn('scripts/pr-evidence-gate.py --event-file "$GITHUB_EVENT_PATH" --publish-status', workflow)
        self.assertNotIn('pull_request.head', workflow)

    def test_language_preparation_updates_only_the_selected_simulator_preferences_while_shutdown(self):
        original = {'AppleLanguages': ['en-US'], 'AppleLocale': 'en_US', 'AppleICUForce24HourTime': True}
        prepared = {**original, 'AppleLanguages': ['en-US', 'ru-RU']}
        calls = []
        metadata = {}
        def native(_directory, label, command, timeout):
            calls.append((label, command, timeout))
            if label == 'language-device-state':
                payload = {'devices': {'runtime': [{'udid': 'selected-id', 'state': 'Shutdown'}]}}
                return subprocess.CompletedProcess(command, 0, json.dumps(payload), '')
            payload = original if label == 'language-preferences-before' else prepared
            return subprocess.CompletedProcess(command, 0, plistlib.dumps(payload).decode(), '')
        with tempfile.TemporaryDirectory() as temporary, patch.object(smoke, 'run_command', side_effect=native):
            directory = Path(temporary)
            preferences = directory / 'Library/Preferences/.GlobalPreferences.plist'
            preferences.parent.mkdir(parents=True)
            preferences.write_bytes(plistlib.dumps(original))
            smoke.prepare_disposable_languages(directory, {
                'udid': 'selected-id', 'dataPath': str(directory), 'state': 'Booted'}, metadata)
        self.assertEqual(['language-shutdown', 'language-device-state', 'language-preferences-before', 'language-preferences-languages',
                          'language-preferences-locale', 'language-preferences-after', 'language-boot',
                          'language-bootstatus'], [item[0] for item in calls])
        self.assertEqual(['xcrun', 'simctl', 'shutdown', 'selected-id'], calls[0][1])
        self.assertEqual(smoke.LANGUAGE_SHUTDOWN_TIMEOUT_SECONDS, calls[0][2])
        self.assertEqual(['plutil', '-replace', 'AppleLanguages', '-json', '["en-US", "ru-RU"]'], calls[3][1][:-1])
        self.assertEqual(str(directory / 'Library/Preferences/.GlobalPreferences.plist'), calls[3][1][-1])
        self.assertEqual(['xcrun', 'simctl', 'boot', 'selected-id'], calls[-2][1])
        self.assertEqual(smoke.COLD_BOOT_TIMEOUT_SECONDS, calls[-1][2])
        self.assertTrue(metadata['language_preparation']['verified'])

    def test_language_preparation_cannot_discard_existing_preferences(self):
        original = {'AppleLanguages': ['en-US'], 'existingSetting': True}
        invalid = {'AppleLanguages': ['en-US', 'ru-RU'], 'AppleLocale': 'en_US'}
        labels = []
        def native(_directory, label, command, timeout):
            labels.append(label)
            if label == 'language-device-state':
                payload = {'devices': {'runtime': [{'udid': 'selected-id', 'state': 'Shutdown'}]}}
                return subprocess.CompletedProcess(command, 0, json.dumps(payload), '')
            payload = original if label == 'language-preferences-before' else invalid
            return subprocess.CompletedProcess(command, 0, plistlib.dumps(payload).decode(), '')
        metadata = {}
        with tempfile.TemporaryDirectory() as temporary, patch.object(smoke, 'run_command', side_effect=native):
            directory = Path(temporary)
            preferences = directory / 'Library/Preferences/.GlobalPreferences.plist'
            preferences.parent.mkdir(parents=True)
            preferences.write_bytes(plistlib.dumps(original))
            with self.assertRaisesRegex(ValueError, 'preserve its other preferences'):
                smoke.prepare_disposable_languages(directory, {
                    'udid': 'selected-id', 'dataPath': temporary, 'state': 'Shutdown'}, metadata)
        self.assertNotIn('language-boot', labels)
        self.assertFalse(metadata['language_preparation']['verified'])

    def test_fresh_shutdown_device_gets_language_preferences_before_its_only_boot(self):
        desired = {'AppleLanguages': ['en-US', 'ru-RU'], 'AppleLocale': 'en_US'}
        calls = []
        metadata = {}
        def native(_directory, label, command, timeout):
            calls.append((label, command))
            if label == 'language-device-state':
                payload = {'devices': {'runtime': [{'udid': 'fresh-id', 'state': 'Shutdown'}]}}
                return subprocess.CompletedProcess(command, 0, json.dumps(payload), '')
            if label == 'language-preferences-before':
                # This real file must be initialized safely before plutil can insert keys.
                self.assertEqual({}, plistlib.loads(Path(command[-1]).read_bytes()))
                payload = {}
            else:
                payload = desired
            return subprocess.CompletedProcess(command, 0, plistlib.dumps(payload).decode(), '')
        with tempfile.TemporaryDirectory() as temporary, patch.object(smoke, 'run_command', side_effect=native):
            smoke.prepare_disposable_languages(Path(temporary), {
                'udid': 'fresh-id', 'dataPath': temporary, 'state': 'Shutdown'}, metadata)
        self.assertNotIn('language-shutdown', [label for label, _ in calls])
        self.assertEqual(['language-device-state', 'language-preferences-before', 'language-preferences-languages',
                          'language-preferences-locale', 'language-preferences-after', 'language-boot',
                          'language-bootstatus'], [label for label, _ in calls])
        self.assertEqual('-insert', calls[2][1][1])
        self.assertTrue(metadata['language_preparation']['initialized_preferences'])
        self.assertTrue(metadata['language_preparation']['verified'])

    def test_failed_shutdown_or_still_booted_state_never_writes_preferences(self):
        for failure in ('shutdown-timeout', 'still-booted'):
            with self.subTest(failure=failure), tempfile.TemporaryDirectory() as temporary:
                directory = Path(temporary)
                preferences = directory / 'Library/Preferences/.GlobalPreferences.plist'
                preferences.parent.mkdir(parents=True)
                original = plistlib.dumps({'existingSetting': 'keep'})
                preferences.write_bytes(original)
                labels = []
                def native(_directory, label, command, timeout):
                    labels.append(label)
                    if failure == 'shutdown-timeout':
                        raise smoke.NativeCommandError('shutdown timed out')
                    payload = {'devices': {'runtime': [{'udid': 'selected-id', 'state': 'Booted'}]}}
                    return subprocess.CompletedProcess(command, 0, json.dumps(payload), '')
                with patch.object(smoke, 'run_command', side_effect=native), self.assertRaises(ValueError):
                    smoke.prepare_disposable_languages(directory, {
                        'udid': 'selected-id', 'dataPath': temporary, 'state': 'Booted'}, {})
                self.assertEqual(original, preferences.read_bytes())
                self.assertNotIn('language-preferences-before', labels)
                self.assertNotIn('language-boot', labels)

    def test_missing_spotlight_checkpoint_fails_export_even_if_other_screenshots_exist(self):
        for missing in ('spotlight-english-opened', 'spotlight-navigation-result', 'spotlight-draft-cancelled'):
            with self.subTest(missing=missing), tempfile.TemporaryDirectory() as temporary:
                directory = Path(temporary)
                attachments = directory / 'attachments'
                attachments.mkdir()
                names = [name for name in smoke.APP_DISCOVERY_CHECKPOINT_NAMES if name != missing]
                exported = []
                for index, name in enumerate(names):
                    filename = f'{index}.png'
                    (attachments / filename).write_bytes(b'png')
                    exported.append({'exportedFileName': filename, 'suggestedHumanReadableName': f'{name}_1.png'})
                (attachments / 'manifest.json').write_text(json.dumps([{'attachments': exported}]))
                metadata = {'planned_checkpoint_names': list(smoke.APP_DISCOVERY_CHECKPOINT_NAMES), 'checkpoints': []}
                self.assertEqual([missing], smoke._export_named_checkpoints(directory, metadata))


if __name__ == '__main__':
    unittest.main()

import importlib.util
import json
import os
import plistlib
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
                return subprocess.CompletedProcess(command, 0, '', '')

            def make_recording(_directory, _simulator_id, _video_path):
                recorder = Mock()
                recorder.poll.return_value = None
                recorder.returncode = -signal.SIGINT
                log = (directory / 'record-video.log').open('w')
                return recorder, log

            real_stop_recording = smoke.stop_recording
            def stop_recording(_directory, recording):
                real_stop_recording(_directory, recording)
                if test_number == 1:
                    (directory / 'journeys.mp4').write_bytes(b'first-run-video')

            def export(_result, attachments, _directory):
                attachments.mkdir(parents=True, exist_ok=True)
                names = ([*smoke.PLANNED_CHECKPOINT_NAMES, 'calendar-4-weeks', 'calendar-6-weeks']
                         if test_number == 1 else ['home-start'])
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
            with patches[0], patches[1], patches[2], patches[3], patches[4]:
                smoke.run(directory)
                self.assertTrue((directory / 'journeys.mp4').is_file())
                self.assertTrue((directory / 'attachments/people.png').is_file())
                (directory / 'index.html').write_text('old successful report')
                with self.assertRaisesRegex(smoke.NativeCommandError, 'second native test failed'):
                    smoke.run(directory)

            metadata = json.loads((directory / 'metadata.json').read_text())
            self.assertEqual([1, 2], generations)
            self.assertEqual('failure', metadata['journey_outcome'])
            self.assertNotEqual('success', metadata['export_outcome'])
            self.assertEqual('feature-acceptance', metadata['evidence_kind'])
            self.assertEqual(
                'Native People disclosure and detail navigation plus grouped person editing, photo crop cancel and confirm, and photo persistence and removal',
                metadata['scenario'],
            )
            self.assertFalse((directory / 'journeys.mp4').exists())
            self.assertFalse((directory / 'index.html').exists())
            self.assertFalse((directory / 'attachments/people.png').exists())
            self.assertEqual(b'new', (directory / 'attachments/home-start.png').read_bytes())
            self.assertEqual('2', (result / 'generation').read_text())
            self.assertEqual('keep this file', unrelated.read_text())

    def test_failed_native_journey_stops_video_and_preserves_result_and_metadata(self):
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
            stop_recording = smoke.stop_recording
            named = [*smoke.PLANNED_CHECKPOINT_NAMES, 'calendar-4-weeks', 'calendar-6-weeks']

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

            def stop(_directory, active_recording):
                stop_recording(_directory, active_recording)
                (directory / 'journeys.mp4').write_bytes(b'mp4')

            with patch.object(smoke.subprocess, 'check_output', return_value='a' * 40), \
                    patch.object(smoke, 'run_command', side_effect=native), \
                    patch.object(smoke, 'start_recording', return_value=recording), \
                    patch.object(smoke, 'stop_recording', side_effect=stop), \
                    patch.object(smoke, '_export_xcresult_attachments', side_effect=export):
                with self.assertRaisesRegex(smoke.NativeCommandError, 'assertion failed'):
                    smoke.run(directory)
            metadata = json.loads(metadata_path.read_text())
            self.assertEqual('failure', metadata['journey_outcome'])
            self.assertIn('assertion failed', metadata['native_test_error'])
            self.assertEqual(len(named), len(metadata['checkpoints']))
            self.assertTrue((result).is_dir())
            self.assertTrue((directory / 'attachments/home-start.png').is_file())
            self.assertTrue((directory / 'journeys.mp4').is_file())

    def test_exports_xcresult_and_maps_named_screenshots(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            result = directory / 'Acceptance.xcresult'
            result.mkdir()
            attachments = directory / 'attachments'
            def export(command, **kwargs):
                attachments.mkdir(exist_ok=True)
                names = [*smoke.PLANNED_CHECKPOINT_NAMES, 'calendar-4-weeks', 'calendar-6-weeks']
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
            self.assertIn('calendar-4-weeks.png', [item['image'].split('/')[-1] for item in metadata['checkpoints']])

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
                else:
                    name = 'Who Gave' if label == 'bundle-names-en' else 'кто че'
                    payload = {'CFBundleDisplayName': name, 'CFBundleName': name}
                self.assertEqual(30, timeout)
                self.assertEqual(['plutil', '-convert', 'xml1', '-o', '-'], command[:5])
                return subprocess.CompletedProcess(command, 0, plistlib.dumps(payload).decode(), '')
            with patch.object(smoke, 'run_command', side_effect=native) as command:
                smoke.verify_built_app_names(Path(temporary), metadata)
            self.assertEqual({'en': 'Who Gave', 'ru': 'кто че'}, metadata['bundle_names'])
            self.assertEqual(3, command.call_count)

    def test_wrong_compiled_name_or_missing_activity_cannot_pass_acceptance(self):
        for failure in ('CFBundleName', 'CFBundleDisplayName', 'activity'):
            with self.subTest(failure=failure), tempfile.TemporaryDirectory() as temporary:
                def native(_directory, label, command, timeout):
                    if label == 'bundle-info':
                        payload = {'NSUserActivityTypes': []}
                    else:
                        name = 'Who Gave' if label == 'bundle-names-en' else 'кто че'
                        payload = {'CFBundleDisplayName': name, 'CFBundleName': name}
                        if label == 'bundle-names-ru' and failure != 'activity':
                            payload[failure] = 'Wrong name'
                    return subprocess.CompletedProcess(command, 0, plistlib.dumps(payload).decode(), '')
                metadata = {}
                with patch.object(smoke, 'run_command', side_effect=native), self.assertRaises(ValueError):
                    smoke.verify_built_app_names(Path(temporary), metadata)
                self.assertNotIn('bundle_names', metadata)

    def test_disposable_language_journey_is_opt_in_and_requires_all_feature_checkpoints(self):
        for verify in (False, True):
            with self.subTest(verify=verify), tempfile.TemporaryDirectory() as temporary:
                directory = Path(temporary)
                test_commands = []
                native_labels = []
                events = []
                def prepare(_directory, _simulator, _metadata):
                    events.append('prepare-languages')
                def native(_directory, label, command, timeout):
                    native_labels.append(label)
                    if label == 'simulator-list':
                        payload = {'devices': {'com.apple.CoreSimulator.SimRuntime.iOS-26-5': [
                            dict(name='iPhone 17 Pro', udid='sim-id', state='Booted', isAvailable=True)]}}
                        return subprocess.CompletedProcess(command, 0, json.dumps(payload), '')
                    if label == 'xcodebuild-test':
                        test_commands.append(command)
                        events.append('xcodebuild-test')
                        raise smoke.NativeCommandError('native assertion failed')
                    return subprocess.CompletedProcess(command, 0, '', '')
                with patch.object(smoke.subprocess, 'check_output', return_value='a' * 40), \
                        patch.object(smoke, 'run_command', side_effect=native), \
                        patch.object(smoke, 'prepare_disposable_languages', side_effect=prepare), \
                        patch.object(smoke, 'start_recording', return_value=(Mock(), Mock())), \
                        patch.object(smoke, 'stop_recording'):
                    with self.assertRaisesRegex(smoke.NativeCommandError, 'native assertion failed'):
                        smoke.run(directory, verify_app_names=verify)
                metadata = json.loads((directory / 'metadata.json').read_text())
                self.assertEqual(['prepare-languages', 'xcodebuild-test'] if verify else ['xcodebuild-test'], events)
                self.assertEqual(not verify, 'simulator-bootstatus' in native_labels)
                self.assertNotIn('simulator-boot', native_labels)
                skipped = '-skip-testing:WhoGaveWhatUITests/AppDiscoveryUITests' in test_commands[0]
                self.assertEqual(not verify, skipped)
                for checkpoint in smoke.APP_DISCOVERY_CHECKPOINT_NAMES:
                    self.assertEqual(verify, checkpoint in metadata['planned_checkpoint_names'])
                    self.assertEqual(verify, checkpoint in metadata['missing_checkpoints'])
                self.assertNotEqual('success', metadata['export_outcome'])

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
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            attachments = directory / 'attachments'
            attachments.mkdir()
            names = [name for name in smoke.APP_DISCOVERY_CHECKPOINT_NAMES if name != 'spotlight-english-opened']
            names += ['calendar-4-weeks', 'calendar-6-weeks']
            exported = []
            for index, name in enumerate(names):
                filename = f'{index}.png'
                (attachments / filename).write_bytes(b'png')
                exported.append({'exportedFileName': filename, 'suggestedHumanReadableName': f'{name}_1.png'})
            (attachments / 'manifest.json').write_text(json.dumps([{'attachments': exported}]))
            metadata = {'planned_checkpoint_names': list(smoke.APP_DISCOVERY_CHECKPOINT_NAMES), 'checkpoints': []}
            self.assertEqual(['spotlight-english-opened'], smoke._export_named_checkpoints(directory, metadata))


if __name__ == '__main__':
    unittest.main()

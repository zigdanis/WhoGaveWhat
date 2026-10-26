import importlib.util
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import time
import unittest
from unittest.mock import Mock, patch

spec = importlib.util.spec_from_file_location('simulator_tools', Path(__file__).parents[1] / 'simulator_tools.py')
tools = importlib.util.module_from_spec(spec)
spec.loader.exec_module(tools)


class NativeCommandTests(unittest.TestCase):
    def test_command_logs_output_and_rejects_failure_with_process_diagnostics(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            fake_process = Mock()
            fake_process.communicate.return_value = ('build output', 'compile error')
            fake_process.returncode = 65
            with patch.object(tools.subprocess, 'Popen', return_value=fake_process), \
                    patch.object(tools.subprocess, 'run', return_value=subprocess.CompletedProcess([], 0, 'pid list', '')):
                with self.assertRaisesRegex(tools.NativeCommandError, 'exited 65'):
                    tools.run_command(directory, 'build', ['xcodebuild'], 20)
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
            with patch.object(tools, '_diagnose_processes'):
                with self.assertRaisesRegex(tools.NativeCommandError, 'timed out after 0.5s'):
                    tools.run_command(directory, 'bounded', [sys.executable, '-c', parent], 0.5)
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
                with patch.object(tools.os, 'killpg', side_effect=denied_killpg), \
                        patch.object(tools, '_diagnose_processes', side_effect=diagnostics):
                    with self.assertRaisesRegex(tools.NativeCommandError, 'timed out after 1s'):
                        tools.run_command(directory, 'bounded', [sys.executable, '-c', parent], 1)
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
            with patch.object(tools.subprocess, 'Popen') as popen, patch.object(tools, '_diagnose_processes'):
                process = popen.return_value
                process.communicate.return_value = ('stdout detail', 'stderr detail')
                process.returncode = 65
                with self.assertRaisesRegex(tools.NativeCommandError, 'stderr detail'):
                    tools.run_command(Path(temporary), 'native', ['xcodebuild'], 10)
            log = (Path(temporary) / 'native.log').read_text()
            self.assertIn('stdout detail', log)
            self.assertIn('stderr detail', log)


class SimulatorSelectionTests(unittest.TestCase):
    def test_simulator_selection_reuses_booted_phone_else_latest_17_pro(self):
        payload = {'devices': {
            'com.apple.CoreSimulator.SimRuntime.iOS-26-4': [
                {'name': 'iPhone 17 Pro', 'udid': 'newer', 'state': 'Shutdown', 'isAvailable': True}],
            'com.apple.CoreSimulator.SimRuntime.iOS-26-2': [
                {'name': 'iPhone 16', 'udid': 'booted', 'state': 'Booted', 'isAvailable': True}],
        }}
        self.assertEqual('booted', tools.select_simulator(payload)['udid'])
        payload['devices']['com.apple.CoreSimulator.SimRuntime.iOS-26-2'][0]['state'] = 'Shutdown'
        self.assertEqual('newer', tools.select_simulator(payload)['udid'])
        with self.assertRaisesRegex(ValueError, 'No available'):
            tools.select_simulator({'devices': {}})

    def test_requested_model_reuses_only_a_booted_phone_of_that_model(self):
        payload = {'devices': {
            'com.apple.CoreSimulator.SimRuntime.iOS-27-0': [
                dict(name='iPhone 18 Pro', udid='booted-pro', state='Booted', isAvailable=True)],
            'com.apple.CoreSimulator.SimRuntime.iOS-27-1': [
                dict(name='iPhone Duo', udid='duo', state='Shutdown', isAvailable=True)],
        }}
        self.assertEqual('booted-pro', tools.select_simulator(payload)['udid'])
        self.assertEqual('booted-pro', tools.select_simulator(payload, device_name='iPhone 18 Pro')['udid'])
        with self.assertRaisesRegex(ValueError, r'Booted iPhone \(iPhone 18 Pro\) is not the requested iPhone Duo'):
            tools.select_simulator(payload, device_name='iPhone Duo')
        payload['devices']['com.apple.CoreSimulator.SimRuntime.iOS-27-0'][0]['state'] = 'Shutdown'
        self.assertEqual('duo', tools.select_simulator(payload, device_name='iPhone Duo')['udid'])
        with self.assertRaisesRegex(ValueError, 'No available booted iPhone or iPhone 17 Pro'):
            tools.select_simulator(payload)

    def test_explicit_runtime_selects_existing_exact_17_pro_instead_of_newer_runtime(self):
        payload = {'devices': {
            'com.apple.CoreSimulator.SimRuntime.iOS-26-4': [
                dict(name='iPhone 17 Pro', udid='requested', state='Shutdown', isAvailable=True)],
            'com.apple.CoreSimulator.SimRuntime.iOS-26-5': [
                dict(name='iPhone 17 Pro', udid='newer', state='Shutdown', isAvailable=True)],
        }}
        self.assertEqual('newer', tools.select_simulator(payload)['udid'])
        selected = tools.select_simulator(payload, requested_runtime='iOS 26.4')
        self.assertEqual(('requested', 'iOS 26.4'), (selected['udid'], selected['runtime']))

    def test_explicit_runtime_reuses_matching_booted_phone_and_rejects_conflict(self):
        payload = {'devices': {
            'com.apple.CoreSimulator.SimRuntime.iOS-26-4': [
                dict(name='iPhone 16', udid='booted', state='Booted', isAvailable=True),
                dict(name='iPhone 17 Pro', udid='shutdown', state='Shutdown', isAvailable=True)],
            'com.apple.CoreSimulator.SimRuntime.iOS-26-5': [
                dict(name='iPhone 17 Pro', udid='requested-shutdown', state='Shutdown', isAvailable=True)],
        }}
        self.assertEqual('booted', tools.select_simulator(payload, requested_runtime='iOS 26.4')['udid'])
        with self.assertRaisesRegex(ValueError, 'Booted iPhone booted uses iOS 26.4, not requested iOS 26.5'):
            tools.select_simulator(payload, requested_runtime='iOS 26.5')

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
                tools.select_simulator(payload, requested_runtime='iOS 26.4')
        with self.assertRaisesRegex(ValueError, 'requested runtime iOS-26-4'):
            tools.select_simulator(payload, requested_runtime='iOS-26-4')


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
                    tools, 'run_command', return_value=subprocess.CompletedProcess(
                        [], 0, json.dumps(runtimes), '')) as native:
                metadata = {}
                with self.assertRaises(ValueError):
                    tools.create_ci_simulator(Path('/unused'), payload, 'iOS 26.4', metadata)
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
        with patch.object(tools, 'run_command', side_effect=native):
            simulator = tools.create_ci_simulator(Path('/unused'), {'devices': {}}, 'iOS 27.1', metadata,
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
                            raise tools.NativeCommandError('create timed out')
                        output = 'invalid' if failure == 'invalid-udid' else (
                            self.source_id if failure == 'existing-udid' else self.created_id)
                    elif label == 'simulator-created-list':
                        if failure == 'list-error':
                            raise tools.NativeCommandError('list timed out')
                        output = json.dumps({'devices': {'wrong-runtime': []}})
                    elif label == 'simulator-created-state':
                        output = json.dumps({'devices': {self.runtime_id: [dict(
                            udid=self.created_id, state='Shutdown')]}})
                    else:
                        output = ''
                    return subprocess.CompletedProcess(command, 0, output, '')
                with patch.object(tools, 'run_command', side_effect=native), self.assertRaises(ValueError):
                    tools.create_ci_simulator(Path(temporary), self.source_payload(), 'iOS 26.4', metadata)
                with patch.object(tools, 'run_command', side_effect=native):
                    tools.cleanup_ci_simulator(Path(temporary), metadata)
                fixture = metadata['simulator_fixture']
                self.assertFalse(fixture['creation_verified'])
                mutations = [command for command in calls if command[2] in ('shutdown', 'delete')]
                self.assertEqual([['xcrun', 'simctl', 'delete', self.created_id]]
                                 if failure in ('list-error', 'wrong-runtime') else [], mutations)
                self.assertNotIn(self.source_id, [command[-1] for command in mutations])

    def test_cleanup_shuts_down_and_deletes_only_the_owned_booted_simulator(self):
        calls = []

        def native(_directory, label, command, timeout):
            calls.append(command)
            if label == 'simulator-created-state':
                output = json.dumps({'devices': {self.runtime_id: [
                    dict(udid=self.created_id, state='Booted'), dict(udid=self.source_id, state='Booted')]}})
            else:
                output = ''
            return subprocess.CompletedProcess(command, 0, output, '')
        metadata = {'simulator_fixture': {'created_simulator_id': self.created_id}}
        with patch.object(tools, 'run_command', side_effect=native):
            tools.cleanup_ci_simulator(Path('/unused'), metadata)
        self.assertEqual([['xcrun', 'simctl', 'shutdown', self.created_id],
                          ['xcrun', 'simctl', 'delete', self.created_id]],
                         [command for command in calls if command[2] in ('shutdown', 'delete')])
        self.assertEqual('success', metadata['simulator_fixture']['cleanup_outcome'])
        with patch.object(tools, 'run_command', side_effect=native) as untouched:
            tools.cleanup_ci_simulator(Path('/unused'), {})
        untouched.assert_not_called()


if __name__ == '__main__':
    unittest.main()

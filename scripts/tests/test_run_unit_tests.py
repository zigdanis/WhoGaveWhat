import importlib.util
import json
import os
from pathlib import Path
import plistlib
import subprocess
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('run_unit_tests', Path(__file__).parents[1] / 'run-unit-tests.py')
runner = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runner)

ROOT = Path(__file__).parents[2]
SIMULATOR_ID = 'CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC'


def plist(payload):
    return plistlib.dumps(payload).decode()


def booted_payload():
    return {'devices': {'com.apple.CoreSimulator.SimRuntime.iOS-27-1': [
        dict(name='iPhone Duo', udid=SIMULATOR_ID, state='Booted', isAvailable=True)]}}


def native_outputs(failures=(), built_names=None):
    """A run_command stand-in that answers every native step and raises for the listed labels."""
    names = built_names or {'CFBundleDisplayName': 'Who Gave', 'CFBundleName': 'Who Gave'}

    def native(_directory, label, command, timeout, *, cwd=None):
        if label in failures:
            raise runner.tools.NativeCommandError(f'{label} exited 65')
        if label == 'simulator-list':
            output = json.dumps(booted_payload())
        elif label.startswith('bundle-names-'):
            output = plist(names if label.endswith('en') else {'CFBundleDisplayName': 'кто че', 'CFBundleName': 'кто че'})
        elif label.startswith('bundle-spotlight-name-'):
            output = plist({'app-discovery.display-name': 'Who Gave · кто че'})
        elif label == 'bundle-info':
            output = plist({'NSUserActivityTypes': ['com.apple.corespotlightitem']})
        else:
            output = ''
        return subprocess.CompletedProcess(command, 0, output, '')
    return native


class UnitTestRunTests(unittest.TestCase):
    def test_fresh_fixture_requires_ci_and_explicit_runtime_before_native_actions(self):
        for environment, runtime in (({}, 'iOS 27.1'), ({'GITHUB_ACTIONS': 'false'}, 'iOS 27.1'),
                                     ({'GITHUB_ACTIONS': 'true'}, None)):
            with self.subTest(environment=environment, runtime=runtime), tempfile.TemporaryDirectory() as temporary, \
                    patch.dict(os.environ, environment, clear=True), patch.object(runner.tools, 'run_command') as native:
                with self.assertRaisesRegex(ValueError, 'requires GitHub Actions and an explicit --runtime'):
                    runner.run(Path(temporary), runtime=runtime, fresh_ci_simulator=True)
                native.assert_not_called()

    def test_runs_only_the_unit_suite_then_checks_names_and_catalog_on_the_booted_simulator(self):
        with tempfile.TemporaryDirectory() as temporary, patch.dict(os.environ, {'HEAD_SHA': 'a' * 40}), \
                patch.object(runner.tools, 'run_command', side_effect=native_outputs()) as native, \
                patch.object(runner.tools, 'cleanup_ci_simulator') as cleanup:
            directory = Path(temporary)
            (directory / 'DerivedData').mkdir()
            runner.run(directory, runtime='iOS 27.1', device_name='iPhone Duo')
            labels = [call.args[1] for call in native.call_args_list]
            self.assertEqual(['simulator-list', 'simulator-bootstatus', 'xcodebuild-test', 'bundle-names-en',
                              'bundle-spotlight-name-en', 'bundle-names-ru', 'bundle-spotlight-name-ru',
                              'bundle-info', 'localization-check'], labels)
            test_call = native.call_args_list[2]
            command = test_call.args[2]
            self.assertEqual(['xcodebuild', 'test'], command[:2])
            self.assertIn(f'platform=iOS Simulator,id={SIMULATOR_ID}', command)
            self.assertIn('-only-testing:WhoGaveWhatTests', command)
            self.assertNotIn('-skip-testing:WhoGaveWhatUITests', command)
            self.assertFalse(any('WhoGaveWhatUITests' in argument for argument in command))
            self.assertEqual(ROOT, test_call.kwargs['cwd'])
            localization = native.call_args_list[-1].args[2]
            self.assertEqual(str(ROOT / 'scripts/sync-localizations.py'), localization[1])
            self.assertEqual(['--derived-data', str(directory / 'DerivedData'), '--check'], localization[2:])
            cleanup.assert_called_once()
            metadata = json.loads((directory / 'metadata.json').read_text())
            self.assertEqual(('success', 'a' * 40, 'iPhone Duo', 'iOS 27.1', 'WhoGaveWhatTests only'),
                             (metadata['outcome'], metadata['head_sha'], metadata['device'], metadata['runtime'],
                              metadata['native_test']))
            self.assertEqual({'en': 'Who Gave', 'ru': 'кто че'}, metadata['bundle_names'])
            self.assertFalse((directory / 'DerivedData').exists())

    def test_fresh_ci_fixture_is_created_booted_and_cleaned_up_after_the_suite(self):
        created = dict(name='iPhone Duo', udid=SIMULATOR_ID, state='Shutdown', isAvailable=True, runtime='iOS 27.1')
        with tempfile.TemporaryDirectory() as temporary, patch.dict(os.environ, {'GITHUB_ACTIONS': 'true'}), \
                patch.object(runner.tools, 'run_command', side_effect=native_outputs()) as native, \
                patch.object(runner.tools, 'create_ci_simulator', return_value=created) as create, \
                patch.object(runner.tools, 'cleanup_ci_simulator') as cleanup:
            runner.run(Path(temporary), runtime='iOS 27.1', device_name='iPhone Duo', fresh_ci_simulator=True)
            self.assertEqual(('iOS 27.1', 'iPhone Duo'), (create.call_args.args[2], create.call_args.args[4]))
            labels = [call.args[1] for call in native.call_args_list]
            self.assertEqual(['simulator-list', 'simulator-boot', 'simulator-bootstatus', 'xcodebuild-test'], labels[:4])
            self.assertEqual([SIMULATOR_ID], [call.args[2][-1] for call in native.call_args_list if call.args[1] == 'simulator-boot'])
            cleanup.assert_called_once()

    def test_native_failure_keeps_the_error_metadata_and_owned_teardown(self):
        for failed_label in ('xcodebuild-test', 'localization-check'):
            with self.subTest(failure=failed_label), tempfile.TemporaryDirectory() as temporary, \
                    patch.object(runner.tools, 'run_command', side_effect=native_outputs(failures=(failed_label,))) as native, \
                    patch.object(runner.tools, 'cleanup_ci_simulator') as cleanup:
                directory = Path(temporary)
                with self.assertRaisesRegex(runner.tools.NativeCommandError, f'{failed_label} exited 65'):
                    runner.run(directory, runtime='iOS 27.1')
                self.assertEqual(failed_label, native.call_args_list[-1].args[1])
                cleanup.assert_called_once()
                metadata = json.loads((directory / 'metadata.json').read_text())
                self.assertEqual(('failure', f'{failed_label} exited 65'), (metadata['outcome'], metadata['error']))
                self.assertFalse((directory / 'DerivedData').exists())

    def test_wrong_compiled_app_name_fails_the_run_before_the_catalog_check(self):
        wrong = {'CFBundleDisplayName': 'WhoGaveWhat', 'CFBundleName': 'Who Gave'}
        with tempfile.TemporaryDirectory() as temporary, \
                patch.object(runner.tools, 'run_command', side_effect=native_outputs(built_names=wrong)) as native, \
                patch.object(runner.tools, 'cleanup_ci_simulator'):
            with self.assertRaisesRegex(ValueError, "Built en app names do not match 'Who Gave'"):
                runner.run(Path(temporary))
            self.assertNotIn('localization-check', [call.args[1] for call in native.call_args_list])

    def test_repeated_run_clears_only_its_own_previous_outputs(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            (directory / 'Tests.xcresult').mkdir()
            (directory / 'stale.log').write_text('old')
            (directory / 'metadata.json').write_text('{}')
            (directory / 'keep.txt').write_text('unrelated')
            runner.clear_previous_outputs(directory)
            self.assertEqual(['keep.txt'], [path.name for path in directory.iterdir()])


class WorkflowTests(unittest.TestCase):
    def test_tests_workflow_runs_the_unit_suite_on_a_fresh_simulator_without_ui_journeys(self):
        workflow = (ROOT / '.github/workflows/tests.yml').read_text()
        self.assertIn('python3 scripts/run-unit-tests.py "$RUNNER_TEMP/unit-tests" --runtime "$SIMULATOR_RUNTIME" '
                      '--device "$SIMULATOR_DEVICE" --fresh-ci-simulator', workflow)
        self.assertIn('HEAD_SHA: ${{ github.event.pull_request.head.sha || github.sha }}', workflow)
        for removed in ('run-app-smoke', 'ui-evidence-report', 'video_test', 'spotlight_diagnostics',
                        'AdaptiveGiftJourney', 'AppDiscoveryUITests'):
            self.assertNotIn(removed, workflow)
        self.assertFalse((ROOT / '.github/workflows/pr-evidence.yml').exists())

    def test_lightweight_checks_remain_automatic_with_the_existing_check_names_and_commands(self):
        checks = (ROOT / '.github/workflows/checks.yml').read_text()
        self.assertIn('python3 -m unittest discover -s scripts/tests -v', checks)
        self.assertIn('scripts/check-secrets.sh', checks)
        self.assertIn('scripts/check-formatting.sh', checks)
        self.assertIn('scripts/lint-swift.sh', checks)
        self.assertNotIn('ffmpeg', checks)

    def test_no_repository_file_points_at_the_removed_evidence_tooling(self):
        tracked = subprocess.check_output(['git', 'ls-files'], cwd=ROOT, text=True).split()
        removed = ('run-app-smoke', 'pr-evidence', 'pr-visual-evidence', 'ui-evidence-report', 'evidence_validation',
                   'AdaptiveGiftJourneyUITests', 'AppDiscoveryUITests')
        offenders = []
        for name in tracked:
            path = ROOT / name
            if path.suffix in ('.png', '.jpg', '.json') or not path.is_file():
                continue
            try:
                text = path.read_text()
            except UnicodeDecodeError:
                continue
            offenders.extend(f'{name}: {marker}' for marker in removed if marker in text and name != 'scripts/tests/test_run_unit_tests.py')
        self.assertEqual([], offenders)


if __name__ == '__main__':
    unittest.main()

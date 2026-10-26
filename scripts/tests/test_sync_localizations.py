import contextlib
import importlib.util
import io
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch


SPEC = importlib.util.spec_from_file_location('sync_localizations', Path(__file__).parents[1] / 'sync-localizations.py')
sync_localizations = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(sync_localizations)


class SyncLocalizationsTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.catalog = self.root / 'Localizable.xcstrings'
        self.catalog.write_text('original\n')
        self.patch = patch.object(sync_localizations, 'CATALOG', self.catalog)
        self.patch.start()
        self.addCleanup(self.patch.stop)

    def stringsdata(self, target='WhoGaveWhat', name='Home', configuration='Debug-iphonesimulator'):
        path = self.root / ('Build/Intermediates.noindex/WhoGaveWhat.build/' + configuration
                            + '/' + target + '.build/Objects-normal/arm64/' + name + '.stringsdata')
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text('{}')
        return path

    def test_rejects_missing_app_output_instead_of_emptying_catalog(self):
        self.stringsdata(target='WhoGaveWhatTests')
        with patch.object(sync_localizations.subprocess, 'run') as command:
            with self.assertRaisesRegex(ValueError, 'No app .stringsdata'):
                sync_localizations.sync(self.root)
        command.assert_not_called()
        self.assertEqual(self.catalog.read_text(), 'original\n')

    def test_check_reports_drift_without_changing_catalog_and_excludes_tests(self):
        app = self.stringsdata()
        tests = self.stringsdata(target='WhoGaveWhatTests')

        def synchronize(command, **kwargs):
            self.assertIn(str(app), command)
            self.assertNotIn(str(tests), command)
            Path(command[3]).write_text('synchronized\n')

        with patch.object(sync_localizations.subprocess, 'run', side_effect=synchronize):
            with contextlib.redirect_stdout(io.StringIO()) as output:
                result = sync_localizations.sync(self.root, check=True)
        self.assertEqual(result, 1)
        self.assertIn('String Catalog is out of sync', output.getvalue())
        self.assertEqual(self.catalog.read_text(), 'original\n')

    def test_check_accepts_unchanged_catalog(self):
        self.stringsdata()
        with patch.object(sync_localizations.subprocess, 'run'):
            with contextlib.redirect_stdout(io.StringIO()):
                self.assertEqual(sync_localizations.sync(self.root, check=True), 0)

    def test_sync_updates_catalog_from_release_output(self):
        self.stringsdata(configuration='Release-iphonesimulator')

        def synchronize(command, **kwargs):
            Path(command[3]).write_text('synchronized\n')

        with patch.object(sync_localizations.subprocess, 'run', side_effect=synchronize):
            with contextlib.redirect_stdout(io.StringIO()):
                self.assertEqual(sync_localizations.sync(self.root), 0)
        self.assertEqual(self.catalog.read_text(), 'synchronized\n')

    def test_propagates_tool_failure(self):
        self.stringsdata()
        with patch.object(sync_localizations.subprocess, 'run', side_effect=subprocess.CalledProcessError(1, 'xcrun')):
            with self.assertRaises(subprocess.CalledProcessError):
                sync_localizations.sync(self.root, check=True)
        self.assertEqual(self.catalog.read_text(), 'original\n')


if __name__ == '__main__':
    unittest.main()

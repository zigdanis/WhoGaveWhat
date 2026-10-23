import importlib.util
import json
import os
import struct
import subprocess
import tempfile
import unittest
import zlib
from pathlib import Path
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('store_screenshots', Path(__file__).parents[1] / 'store-screenshots.py')
shots = importlib.util.module_from_spec(spec)
spec.loader.exec_module(shots)

SLUGS = ['home', 'add-gift', 'gift-details', 'person', 'insights', 'compare', 'people']


def png(width, height):
    """A valid, blank PNG header-plus-data of the given size."""
    def chunk(kind, data):
        return struct.pack('>I', len(data)) + kind + data + struct.pack('>I', zlib.crc32(kind + data))
    rows = zlib.compress((b'\x00' + b'\x00' * width) * height)
    header = struct.pack('>IIBBBBB', width, height, 8, 0, 0, 0, 0)
    return b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', header) + chunk(b'IDAT', rows) + chunk(b'IEND', b'')


def runtime(name, devices, available=True):
    version = name.split()[-1].replace('.', '-')
    return {'name': name, 'identifier': f'com.apple.CoreSimulator.SimRuntime.iOS-{version}', 'isAvailable': available,
            'supportedDeviceTypes': [{'name': device, 'identifier': f'com.apple.CoreSimulator.SimDeviceType.{device}'}
                                     for device in devices]}


def set_for(*sizes, count=len(SLUGS)):
    return [(index + 1, SLUGS[index], sizes[0]) for index in range(count)]


class DeviceSelectionTests(unittest.TestCase):
    def test_prefers_the_18_pro_max_on_the_runtime_that_supports_it(self):
        payload = {'runtimes': [
            runtime('iOS 27.1', ['iPhone Duo']),
            runtime('iOS 27.0', ['iPhone 17 Pro Max', 'iPhone 18 Pro', 'iPhone 18 Pro Max', 'iPhone Duo'])]}

        choice = shots.choose_device(payload)

        self.assertEqual('iPhone 18 Pro Max', choice['device'])
        self.assertEqual('iOS 27.0', choice['runtime'])

    def test_falls_back_to_the_newest_pro_max_then_plus(self):
        pro_max = {'runtimes': [runtime('iOS 26.4', ['iPhone 16 Pro Max', 'iPhone 17 Pro Max', 'iPhone 17 Pro'])]}
        plus = {'runtimes': [runtime('iOS 26.4', ['iPhone 16 Plus', 'iPhone 17', 'iPhone 15 Plus'])]}

        self.assertEqual('iPhone 17 Pro Max', shots.choose_device(pro_max)['device'])
        self.assertEqual('iPhone 16 Plus', shots.choose_device(plus)['device'])

    def test_picks_the_newest_runtime_for_the_model(self):
        payload = {'runtimes': [runtime('iOS 26.4', ['iPhone 18 Pro Max']), runtime('iOS 27.0', ['iPhone 18 Pro Max'])]}

        self.assertEqual('iOS 27.0', shots.choose_device(payload)['runtime'])
        self.assertEqual('iOS 26.4', shots.choose_device(payload, runtime='iOS 26.4')['runtime'])

    def test_never_selects_duo_or_unavailable_runtimes_and_explains_the_failure(self):
        payload = {'runtimes': [runtime('iOS 27.1', ['iPhone Duo', 'iPhone 18 Pro']),
                                runtime('iOS 27.0', ['iPhone 18 Pro Max'], available=False)]}

        with self.assertRaisesRegex(ValueError, 'No available 6.9-inch.*iPhone 18 Pro, iPhone Duo'):
            shots.choose_device(payload)
        with self.assertRaisesRegex(ValueError, 'Duo'):
            shots.choose_device(payload, device='iPhone Duo')

    def test_an_explicit_model_must_exist(self):
        payload = {'runtimes': [runtime('iOS 27.0', ['iPhone 18 Pro Max', 'iPhone 18'])]}

        self.assertEqual('iPhone 18', shots.choose_device(payload, device='iPhone 18')['device'])
        with self.assertRaisesRegex(ValueError, 'No available iPhone 17 Pro Max'):
            shots.choose_device(payload, device='iPhone 17 Pro Max')


class PngSizeTests(unittest.TestCase):
    def test_reads_the_header_and_rejects_other_files(self):
        with tempfile.TemporaryDirectory() as temporary:
            good = Path(temporary) / 'good.png'
            good.write_bytes(png(1320, 2868))
            bad = Path(temporary) / 'bad.png'
            bad.write_bytes(b'not a png at all, but long enough to read a header')
            short = Path(temporary) / 'short.png'
            short.write_bytes(b'\x89PNG')

            self.assertEqual((1320, 2868), shots.png_size(good))
            for path in (bad, short):
                with self.assertRaisesRegex(ValueError, 'not a PNG'):
                    shots.png_size(path)

    def test_only_apples_portrait_6_9_inch_sizes_pass(self):
        for size in sorted(shots.ALLOWED_SIZES):
            shots.validate_size(*size, 'shot')
        for size in [(1206, 2622), (1320, 2867), (2868, 1320), (2868, 2868)]:
            with self.subTest(size=size), self.assertRaises(ValueError):
                shots.validate_size(*size, 'shot')

    def test_a_landscape_error_names_the_problem(self):
        with self.assertRaisesRegex(ValueError, 'portrait'):
            shots.validate_size(2868, 1320, 'en-US/01_home.png')
        with self.assertRaisesRegex(ValueError, '1206x2622.*1320x2868'):
            shots.validate_size(1206, 2622, 'en-US/01_home.png')


class ManifestTests(unittest.TestCase):
    def attachment(self, locale, number, slug, suffix='_0_8F2B7C1E-0000-4000-8000-ABCDEF012345.png', file=None):
        return {'exportedFileName': file or f'{locale}-{number}.png',
                'suggestedHumanReadableName': f'store-{locale}-{number:02d}-{slug}{suffix}'}

    def test_picks_this_locales_numbered_shots_and_ignores_everything_else(self):
        manifest = [{'testIdentifier': 'StoreScreenshotsUITests/testStoreScreenshots()', 'attachments': [
            self.attachment('en-US', 1, 'home'), self.attachment('en-US', 2, 'add-gift'),
            self.attachment('ru', 1, 'home'),
            {'exportedFileName': 'x.png', 'suggestedHumanReadableName': 'failure-screen_1_AAAA.png'},
            {'exportedFileName': 'h.txt', 'suggestedHumanReadableName': 'store-en-US-03-person_2_B.txt'}]}]

        self.assertEqual({1: ('home', 'en-US-1.png'), 2: ('add-gift', 'en-US-2.png')},
                         shots.plan_outputs(manifest, 'en-US'))
        self.assertEqual({1: ('home', 'ru-1.png')}, shots.plan_outputs(manifest, 'ru'))

    def test_slug_ends_before_the_attachment_suffix(self):
        for suffix in ('.png', '_0_ABC.png', '_12_DEF-123.png'):
            with self.subTest(suffix=suffix):
                plan = shots.plan_outputs([{'attachments': [self.attachment('ru', 3, 'gift-details', suffix)]}], 'ru')
                self.assertEqual('gift-details', plan[3][0])

    def test_a_retried_shot_keeps_the_last_attachment(self):
        manifest = [{'attachments': [self.attachment('ru', 1, 'home', file='first.png'),
                                     self.attachment('ru', 1, 'home', file='second.png')]}]

        self.assertEqual({1: ('home', 'second.png')}, shots.plan_outputs(manifest, 'ru'))

    def test_a_run_without_store_shots_fails(self):
        with self.assertRaisesRegex(ValueError, 'ru run exported no store screenshots'):
            shots.plan_outputs([{'attachments': []}], 'ru')

    def test_output_names_sort_in_shot_order(self):
        names = [shots.output_name(number, slug) for number, slug in enumerate(SLUGS, start=1)]

        self.assertEqual('01_home.png', names[0])
        self.assertEqual('07_people.png', names[-1])
        self.assertEqual(sorted(names), names)


class SetValidationTests(unittest.TestCase):
    def sets(self, **changes):
        base = {'en-US': set_for((1320, 2868)), 'ru': set_for((1320, 2868))}
        base.update(changes)
        return base

    def test_matching_sets_pass_and_report_their_size(self):
        self.assertEqual((1320, 2868), shots.validate_set(self.sets()))

    def test_locales_need_the_same_slugs_in_the_same_order(self):
        swapped = set_for((1320, 2868))
        swapped[2] = (3, 'person', (1320, 2868))
        with self.assertRaisesRegex(ValueError, 'ru screenshots .* differ from en-US'):
            shots.validate_set(self.sets(ru=swapped))
        with self.assertRaisesRegex(ValueError, 'ru screenshots .*differ|not numbered'):
            shots.validate_set(self.sets(ru=set_for((1320, 2868), count=6)))

    def test_numbers_must_be_contiguous(self):
        gap = [(1, 'home', (1320, 2868)), (3, 'add-gift', (1320, 2868))] + set_for((1320, 2868))[2:]
        with self.assertRaisesRegex(ValueError, 'not numbered'):
            shots.validate_set(self.sets(**{'en-US': gap}))

    def test_count_must_fit_the_store_limits(self):
        with self.assertRaisesRegex(ValueError, 'expected 5 to 10'):
            shots.validate_set({'en-US': set_for((1320, 2868), count=4), 'ru': set_for((1320, 2868), count=4)})
        many = [(index, f'shot-{index}', (1320, 2868)) for index in range(1, 12)]
        with self.assertRaisesRegex(ValueError, 'expected 5 to 10'):
            shots.validate_set({'en-US': many, 'ru': many})

    def test_wrong_or_mixed_sizes_fail(self):
        with self.assertRaisesRegex(ValueError, '1206x2622'):
            shots.validate_set(self.sets(ru=set_for((1206, 2622))))
        mixed = set_for((1320, 2868))
        mixed[0] = (1, 'home', (1290, 2796))
        with self.assertRaisesRegex(ValueError, 'mix sizes'):
            shots.validate_set(self.sets(ru=mixed))


class IndexTests(unittest.TestCase):
    def test_contact_sheet_links_every_shot_relative_to_the_output_folder(self):
        page = shots.render_index({'en-US': set_for((1320, 2868), count=5), 'ru': set_for((1320, 2868), count=5)})

        self.assertIn('src="screenshots/en-US/01_home.png"', page)
        self.assertIn('src="screenshots/ru/05_insights.png"', page)
        self.assertIn('01_home.png (1320x2868)', page)


class RunTests(unittest.TestCase):
    def fake_environment(self, directory, width=1320, height=2868, ru_slugs=None):
        commands = []
        environments = []

        def run_command(_directory, label, command, timeout, *, cwd=None):
            commands.append((label, command))
            if label == 'xcodebuild-test-en-US' or label == 'xcodebuild-test-ru':
                environments.append((os.environ.get('TEST_RUNNER_KS_STORE_SCREENSHOTS'),
                                     os.environ.get('TEST_RUNNER_KS_STORE_LOCALE')))
            output = ''
            if label == 'simulator-runtimes-list':
                output = json.dumps({'runtimes': [runtime('iOS 27.1', ['iPhone Duo']),
                                                  runtime('iOS 27.0', ['iPhone 18 Pro Max'])]})
            if label == 'simulator-list':
                output = json.dumps({'devices': {}})
            return subprocess.CompletedProcess(command, 0, output, '')

        def create(_directory, _payload, requested_runtime, metadata, device_name):
            metadata['simulator_fixture'] = {'created_simulator_id': 'UDID'}
            commands.append(('create', [requested_runtime, device_name]))
            return {'udid': 'UDID'}

        def export(bundle, attachments, _directory):
            locale = 'ru' if 'ru' in bundle.name else 'en-US'
            attachments.mkdir(parents=True)
            entries = []
            slugs = ru_slugs if locale == 'ru' and ru_slugs else SLUGS
            for number, slug in enumerate(slugs, start=1):
                (attachments / f'{locale}-{number}.png').write_bytes(png(width, height))
                entries.append({'exportedFileName': f'{locale}-{number}.png',
                                'suggestedHumanReadableName': f'store-{locale}-{number:02d}-{slug}_0_X.png'})
            (attachments / 'manifest.json').write_text(json.dumps([{'attachments': entries}]))

        def cleanup(_directory, metadata):
            commands.append(('cleanup', [metadata['simulator_fixture']['created_simulator_id']]))
            metadata['simulator_fixture']['cleanup_outcome'] = 'success'

        patches = [patch.object(shots.smoke, 'run_command', side_effect=run_command),
                   patch.object(shots.smoke, 'create_ci_simulator', side_effect=create),
                   patch.object(shots.smoke, '_export_xcresult_attachments', side_effect=export),
                   patch.object(shots.smoke, 'cleanup_ci_simulator', side_effect=cleanup),
                   patch.dict(os.environ, {'HEAD_SHA': 'a' * 40})]
        return commands, environments, patches

    def run_with(self, directory, **options):
        commands, environments, patches = self.fake_environment(directory, **options)
        for item in patches:
            item.start()
            self.addCleanup(item.stop)
        return commands, environments

    def test_a_good_run_lays_out_fastlane_folders_and_cleans_up(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            commands, environments = self.run_with(directory)

            shots.run(directory)

            self.assertEqual(sorted(f'{number:02d}_{slug}.png' for number, slug in enumerate(SLUGS, start=1)),
                             sorted(path.name for path in (directory / 'screenshots/en-US').iterdir()))
            self.assertEqual(sorted(path.name for path in (directory / 'screenshots/en-US').iterdir()),
                             sorted(path.name for path in (directory / 'screenshots/ru').iterdir()))
            metadata = json.loads((directory / 'metadata.json').read_text())
            self.assertEqual('success', metadata['outcome'])
            self.assertEqual(['1320x2868'], metadata['sizes'])
            self.assertEqual(('iPhone 18 Pro Max', 'iOS 27.0'), (metadata['device'], metadata['runtime']))
            self.assertEqual('a' * 40, metadata['head_sha'])
            self.assertTrue((directory / 'index.html').is_file())
            self.assertEqual([('1', 'en-US'), ('1', 'ru')], environments)
            self.assertNotIn('TEST_RUNNER_KS_STORE_LOCALE', os.environ)
            labels = [label for label, _ in commands]
            self.assertLess(labels.index('status-bar'), labels.index('xcodebuild-build'))
            self.assertLess(labels.index('xcodebuild-build'), labels.index('xcodebuild-test-en-US'))
            self.assertEqual('cleanup', labels[-1])
            status = dict(commands)['status-bar']
            self.assertEqual(['override', '--time', '9:41'], status[4:7])
            tests = dict(commands)['xcodebuild-test-ru']
            self.assertIn('test-without-building', tests)
            self.assertIn('-only-testing:WhoGaveWhatUITests/StoreScreenshotsUITests', tests)
            self.assertIn('-collect-test-diagnostics', tests)
            self.assertFalse((directory / 'ru.xcresult').exists())

    def test_wrong_screenshot_size_fails_clearly_and_still_cleans_up(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            commands, _ = self.run_with(directory, width=1206, height=2622)

            with self.assertRaisesRegex(ValueError, '1206x2622'):
                shots.run(directory)

            self.assertEqual('cleanup', commands[-1][0])
            metadata = json.loads((directory / 'metadata.json').read_text())
            self.assertEqual('failure', metadata['outcome'])
            self.assertIn('1206x2622', metadata['error'])

    def test_locale_mismatch_fails(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            self.run_with(directory, ru_slugs=SLUGS[:-1] + ['settings'])

            with self.assertRaisesRegex(ValueError, 'differ from en-US'):
                shots.run(directory)

    def test_a_failed_test_run_keeps_diagnostics_and_cleans_up(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            commands, _ = self.run_with(directory)
            original = shots.smoke.run_command.side_effect

            def failing(directory_, label, command, timeout, *, cwd=None):
                if label == 'xcodebuild-test-ru':
                    raise shots.smoke.NativeCommandError('xcodebuild-test-ru exited 65')
                return original(directory_, label, command, timeout, cwd=cwd)

            shots.smoke.run_command.side_effect = failing

            with self.assertRaisesRegex(shots.smoke.NativeCommandError, 'exited 65'):
                shots.run(directory)

            self.assertEqual('cleanup', commands[-1][0])
            self.assertEqual('failure', json.loads((directory / 'metadata.json').read_text())['outcome'])
            self.assertFalse((directory / 'DerivedData').exists())


if __name__ == '__main__':
    unittest.main()

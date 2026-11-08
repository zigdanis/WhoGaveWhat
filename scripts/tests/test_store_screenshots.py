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


def devices(*entries):
    """A `simctl list devices --json` payload from (runtime, name, udid, state) entries."""
    payload = {'devices': {}}
    for runtime_name, name, udid, state in entries:
        key = 'com.apple.CoreSimulator.SimRuntime.' + runtime_name.replace(' ', '-').replace('.', '-')
        payload['devices'].setdefault(key, []).append(dict(name=name, udid=udid, state=state, isAvailable=True))
    return payload


POOL = devices(('iOS 27.0', 'iPhone 17 Pro', 'C47B0285', 'Shutdown'),
               ('iOS 27.0', 'iPhone 14 Plus', 'FCBC882C', 'Booted'),
               ('iOS 27.0', 'iPhone SE (3rd generation)', 'F808ED1F', 'Shutdown'),
               ('iOS 27.1', 'iPhone Duo', '079EE4B9', 'Shutdown'),
               ('iOS 27.0', 'iPad Pro 13-inch (M5)', '61C17472', 'Shutdown'),
               ('iOS 27.0', 'iPad Pro 11-inch (M5)', 'AAAAAAAA', 'Shutdown'))


class DeviceSelectionTests(unittest.TestCase):
    def test_each_set_takes_its_pool_device_by_udid(self):
        for display, udid, name, runtime_name, state in (
                (shots.IPHONE_63, 'C47B0285', 'iPhone 17 Pro', 'iOS 27.0', 'Shutdown'),
                (shots.IPHONE_65, 'fcbc882c', 'iPhone 14 Plus', 'iOS 27.0', 'Booted'),
                (shots.IPHONE_DUO, '079EE4B9', 'iPhone Duo', 'iOS 27.1', 'Shutdown'),
                (shots.IPAD_13, '61C17472', 'iPad Pro 13-inch (M5)', 'iOS 27.0', 'Shutdown')):
            with self.subTest(display=display.key):
                self.assertEqual({'udid': udid.upper(), 'device': name, 'runtime': runtime_name, 'state': state},
                                 shots.pool_device(POOL, udid, display))

    def test_a_device_of_the_wrong_model_is_refused(self):
        for display, udid in ((shots.IPHONE_63, 'FCBC882C'), (shots.IPHONE_65, 'C47B0285'),
                              (shots.IPHONE_DUO, 'C47B0285'), (shots.IPAD_13, 'AAAAAAAA'),
                              (shots.IPHONE_63, 'F808ED1F'), (shots.IPAD_13, '079EE4B9')):
            with self.subTest(display=display.key, udid=udid), \
                    self.assertRaisesRegex(ValueError, f'does not produce the {display.title} set'):
                shots.pool_device(POOL, udid, display)

    def test_an_unknown_or_unavailable_device_is_refused(self):
        with self.assertRaisesRegex(ValueError, 'No Simulator with UDID 12345678'):
            shots.pool_device(POOL, '12345678', shots.IPHONE_63)
        payload = devices(('iOS 27.0', 'iPhone 17 Pro', 'C47B0285', 'Shutdown'))
        payload['devices']['com.apple.CoreSimulator.SimRuntime.iOS-27-0'][0]['isAvailable'] = False
        with self.assertRaisesRegex(ValueError, 'unavailable'):
            shots.pool_device(payload, 'C47B0285', shots.IPHONE_63)

    def test_only_apples_portrait_13_inch_ipad_sizes_pass_for_ipad(self):
        for size in [(2064, 2752), (2048, 2732)]:
            shots.validate_size(*size, 'shot', shots.IPAD_13)
        with self.assertRaisesRegex(ValueError, '13-inch iPad sizes are 2064x2752, 2048x2732'):
            shots.validate_size(1668, 2420, 'shot', shots.IPAD_13)
        with self.assertRaisesRegex(ValueError, 'portrait'):
            shots.validate_size(2752, 2064, 'shot', shots.IPAD_13)

    def test_every_set_has_its_own_file_prefix(self):
        prefixes = [display.prefix for display in shots.DISPLAYS.values()]
        self.assertEqual(len(prefixes), len(set(prefixes)))


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

    def test_only_apples_portrait_iphone_sizes_pass_for_each_set(self):
        for size in sorted(shots.IPHONE_63.sizes):
            shots.validate_size(*size, 'shot')
        for size in [(1284, 2778), (1242, 2688)]:
            shots.validate_size(*size, 'shot', shots.IPHONE_65)
        for display, size in ((shots.IPHONE_63, (1320, 2868)), (shots.IPHONE_63, (1206, 2621)),
                              (shots.IPHONE_65, (1290, 2796)), (shots.IPHONE_65, (2778, 1284))):
            with self.subTest(display=display.key, size=size), self.assertRaises(ValueError):
                shots.validate_size(*size, 'shot', display)

    def test_only_the_duo_outer_display_size_passes_for_duo(self):
        shots.validate_size(1398, 2034, 'shot', shots.IPHONE_DUO)
        for size in [(1320, 2868), (2007, 2853)]:
            with self.subTest(size=size), self.assertRaisesRegex(ValueError, 'iPhone Duo outer display sizes are 1398x2034'):
                shots.validate_size(*size, 'shot', shots.IPHONE_DUO)
        with self.assertRaisesRegex(ValueError, 'portrait'):
            shots.validate_size(2034, 1398, 'shot', shots.IPHONE_DUO)

    def test_a_landscape_error_names_the_problem(self):
        with self.assertRaisesRegex(ValueError, 'portrait'):
            shots.validate_size(2622, 1206, 'en-US/01_home.png')
        with self.assertRaisesRegex(ValueError, '1320x2868.*1206x2622'):
            shots.validate_size(1320, 2868, 'en-US/01_home.png')


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

    def test_duo_names_share_the_language_folder_without_clashing(self):
        self.assertEqual('duo_01_home.png', shots.output_name(1, 'home', shots.IPHONE_DUO.prefix))
        self.assertNotEqual(shots.IPHONE_63.prefix, shots.IPHONE_DUO.prefix)


class SetValidationTests(unittest.TestCase):
    def sets(self, **changes):
        base = {'en-US': set_for((1206, 2622)), 'ru': set_for((1206, 2622))}
        base.update(changes)
        return base

    def test_matching_sets_pass_and_report_their_size(self):
        self.assertEqual((1206, 2622), shots.validate_set(self.sets()))

    def test_locales_need_the_same_slugs_in_the_same_order(self):
        swapped = set_for((1206, 2622))
        swapped[2] = (3, 'person', (1206, 2622))
        with self.assertRaisesRegex(ValueError, 'ru screenshots .* differ from en-US'):
            shots.validate_set(self.sets(ru=swapped))
        with self.assertRaisesRegex(ValueError, 'ru screenshots .*differ|not numbered'):
            shots.validate_set(self.sets(ru=set_for((1206, 2622), count=6)))

    def test_numbers_must_be_contiguous(self):
        gap = [(1, 'home', (1206, 2622)), (3, 'add-gift', (1206, 2622))] + set_for((1206, 2622))[2:]
        with self.assertRaisesRegex(ValueError, 'not numbered'):
            shots.validate_set(self.sets(**{'en-US': gap}))

    def test_count_must_fit_the_store_limits(self):
        with self.assertRaisesRegex(ValueError, 'expected 5 to 10'):
            shots.validate_set({'en-US': set_for((1206, 2622), count=4), 'ru': set_for((1206, 2622), count=4)})
        many = [(index, f'shot-{index}', (1206, 2622)) for index in range(1, 12)]
        with self.assertRaisesRegex(ValueError, 'expected 5 to 10'):
            shots.validate_set({'en-US': many, 'ru': many})

    def test_wrong_or_mixed_sizes_fail(self):
        with self.assertRaisesRegex(ValueError, '1320x2868'):
            shots.validate_set(self.sets(ru=set_for((1320, 2868))))
        mixed = set_for((1206, 2622))
        mixed[0] = (1, 'home', (1179, 2556))
        with self.assertRaisesRegex(ValueError, 'mix sizes'):
            shots.validate_set(self.sets(ru=mixed))


class IndexTests(unittest.TestCase):
    def test_contact_sheet_links_every_shot_relative_to_the_output_folder(self):
        page = shots.render_index({'en-US': set_for((1320, 2868), count=5), 'ru': set_for((1320, 2868), count=5)})

        self.assertIn('src="screenshots/en-US/01_home.png"', page)
        self.assertIn('src="screenshots/ru/05_insights.png"', page)
        self.assertIn('01_home.png (1320x2868)', page)


class CombineTests(unittest.TestCase):
    SIZES = {'iphone-6.3': (1206, 2622), 'iphone-6.5': (1284, 2778), 'iphone-duo': (1398, 2034), 'ipad-13': (2064, 2752)}

    def write_parts(self, parts, sizes=None, slugs=SLUGS):
        for key, (width, height) in (sizes or self.SIZES).items():
            display = shots.DISPLAYS[key]
            part = parts / f'store-screenshots-{key}'
            for locale in shots.LOCALES:
                folder = part / 'screenshots' / locale
                folder.mkdir(parents=True)
                for number, slug in enumerate(slugs, start=1):
                    (folder / shots.output_name(number, slug, display.prefix)).write_bytes(png(width, height))
            (part / 'metadata.json').write_text(json.dumps({'head_sha': 'b' * 40, 'device': f'{key} model', 'runtime': 'iOS 27.0'}))
            (part / 'index.html').write_text(f'<img src="screenshots/en-US/{display.prefix}01_home.png">')

    def test_merges_every_set_into_one_folder_per_language_with_a_review_page(self):
        with tempfile.TemporaryDirectory() as temporary:
            parts, out = Path(temporary) / 'parts', Path(temporary) / 'out'
            self.write_parts(parts)

            sets = shots.combine_sets(parts, out)

            self.assertEqual(['iphone-6.3', 'iphone-6.5', 'iphone-duo', 'ipad-13'], [display.key for display, _, _ in sets])
            names = sorted(path.name for path in (out / 'screenshots/ru').iterdir())
            self.assertEqual(4 * len(SLUGS), len(names))
            self.assertIn('ipad_01_home.png', names)
            self.assertEqual(names, sorted(path.name for path in (out / 'screenshots/en-US').iterdir()))
            self.assertIn('src="../screenshots/en-US/ipad_01_home.png"', (out / 'ipad-13/index.html').read_text())
            self.assertTrue((out / 'iphone-duo/metadata.json').is_file())
            page = (out / 'index.html').read_text()
            for text in ('13-inch iPad (ipad-13 model, iOS 27.0) &middot; 14 screenshots', 'Commit bbbbbbbbbbbb',
                         'src="screenshots/ru/ipad_07_people.png"', 'medium_07_people.png (1206x2622)',
                         'src="screenshots/en-US/duo_01_home.png"', 'large_01_home.png (1284x2778)'):
                self.assertIn(text, page)
            self.assertLess(page.index('6.3-inch'), page.index('13-inch iPad'))

    def test_a_missing_set_or_wrong_size_fails(self):
        with tempfile.TemporaryDirectory() as temporary:
            parts = Path(temporary) / 'parts'
            self.write_parts(parts, {key: size for key, size in self.SIZES.items() if key != 'ipad-13'})
            with self.assertRaisesRegex(ValueError, "Expected the screenshot sets .*got \\['iphone-6.3'"):
                shots.combine_sets(parts, Path(temporary) / 'out')
        with tempfile.TemporaryDirectory() as temporary:
            parts = Path(temporary) / 'parts'
            self.write_parts(parts, {**self.SIZES, 'ipad-13': (1668, 2420)})
            with self.assertRaisesRegex(ValueError, '13-inch iPad sizes'):
                shots.combine_sets(parts, Path(temporary) / 'out')

    def test_the_upload_check_needs_every_set_from_one_commit(self):
        with tempfile.TemporaryDirectory() as temporary:
            parts, out = Path(temporary) / 'parts', Path(temporary) / 'out'
            self.write_parts(parts)
            shots.combine_sets(parts, out)
            self.assertEqual(list(shots.DISPLAYS), [display.key for display, _, _ in shots.check_upload(out)])
            self.assertEqual(0, shots.main([str(out), '--check']))
            (out / 'iphone-duo/metadata.json').write_text(json.dumps({'head_sha': 'c' * 40}))
            with self.assertRaisesRegex(ValueError, 'different commits'):
                shots.check_upload(out)
            (out / 'iphone-duo/metadata.json').unlink()
            with self.assertRaisesRegex(ValueError, "lacks the screenshot sets \\['iphone-duo'\\]"):
                shots.check_upload(out)

    def test_a_self_contained_review_page_embeds_every_set(self):
        with tempfile.TemporaryDirectory() as temporary:
            parts, out = Path(temporary) / 'parts', Path(temporary) / 'out'
            self.write_parts(parts)
            shots.combine_sets(parts, out)
            page = Path(temporary) / 'review.html'

            with patch.object(shots.shutil, 'which', return_value=None):
                sets = shots.write_review_page(out, page, note='Run 1')

            text = page.read_text()
            self.assertEqual(4, len(sets))
            self.assertEqual(4 * len(SLUGS) * 2, text.count('data:image/png;base64,'))
            self.assertIn('<a href="#">', text)
            self.assertNotIn('src="screenshots/', text)
            self.assertIn('data-label="13-inch iPad · ru · ipad_07_people.png"', text)
            self.assertIn('<p>Run 1</p>', text)

    def test_the_review_page_can_embed_its_images(self):
        page = shots.render_review([(shots.IPAD_13, {}, {'en-US': [(1, 'home', (2064, 2752))]})],
                                   source=lambda locale, name: f'data:image/jpeg;base64,{locale}-{name}')

        self.assertIn('src="data:image/jpeg;base64,en-US-ipad_01_home.png"', page)
        # Browsers won't open a data: link as a page, so a tap shows the shot in the page's own dialog.
        self.assertIn('<dialog id="zoom">', page)
        self.assertIn("event.preventDefault()", page)
        self.assertIn("ArrowRight", page)
        self.assertIn("ArrowLeft", page)
        self.assertIn('<h2>13-inch iPad &middot; 1 screenshots</h2>', page)


class RunTests(unittest.TestCase):
    def fake_environment(self, directory, width=1206, height=2622, ru_slugs=None, payload=POOL):
        commands = []
        environments = []

        def run_command(_directory, label, command, timeout, *, cwd=None):
            commands.append((label, command))
            if label == 'xcodebuild-test-en-US' or label == 'xcodebuild-test-ru':
                environments.append((os.environ.get('TEST_RUNNER_KS_STORE_SCREENSHOTS'),
                                     os.environ.get('TEST_RUNNER_KS_STORE_LOCALE')))
            output = json.dumps(payload) if label == 'simulator-list' else ''
            return subprocess.CompletedProcess(command, 0, output, '')

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

        patches = [patch.object(shots.tools, 'run_command', side_effect=run_command),
                   patch.object(shots.tools, 'export_xcresult_attachments', side_effect=export),
                   patch.dict(os.environ, {'HEAD_SHA': 'a' * 40})]
        return commands, environments, patches

    def run_with(self, directory, **options):
        commands, environments, patches = self.fake_environment(directory, **options)
        for item in patches:
            item.start()
            self.addCleanup(item.stop)
        return commands, environments

    def test_a_good_run_builds_before_booting_and_leaves_the_pool_device_as_found(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            commands, environments = self.run_with(directory)

            shots.run(directory, 'C47B0285')

            self.assertEqual(sorted(f'medium_{number:02d}_{slug}.png' for number, slug in enumerate(SLUGS, start=1)),
                             sorted(path.name for path in (directory / 'screenshots/en-US').iterdir()))
            self.assertEqual(sorted(path.name for path in (directory / 'screenshots/en-US').iterdir()),
                             sorted(path.name for path in (directory / 'screenshots/ru').iterdir()))
            metadata = json.loads((directory / 'metadata.json').read_text())
            self.assertEqual('success', metadata['outcome'])
            self.assertEqual(['1206x2622'], metadata['sizes'])
            self.assertEqual(('iPhone 17 Pro', 'iOS 27.0', 'C47B0285'),
                             (metadata['device'], metadata['runtime'], metadata['simulator_id']))
            self.assertEqual({'booted_here': True, 'errors': []}, metadata['release'])
            self.assertEqual('a' * 40, metadata['head_sha'])
            self.assertTrue((directory / 'index.html').is_file())
            self.assertEqual([('1', 'en-US'), ('1', 'ru')], environments)
            self.assertNotIn('TEST_RUNNER_KS_STORE_LOCALE', os.environ)
            labels = [label for label, _ in commands]
            self.assertEqual(['simulator-list', 'xcodebuild-build', 'simulator-boot', 'simulator-bootstatus',
                              'status-bar-1', 'xcodebuild-test-en-US', 'xcodebuild-test-ru', 'status-bar-clear',
                              'uninstall-ui-test-runner', 'simulator-shutdown'], labels)
            self.assertNotIn('create', ' '.join(' '.join(command) for _, command in commands))
            self.assertNotIn('delete', ' '.join(' '.join(command) for _, command in commands))
            self.assertEqual(['xcrun', 'simctl', 'uninstall', 'C47B0285', shots.UI_TEST_RUNNER],
                             dict(commands)['uninstall-ui-test-runner'])
            status = dict(commands)['status-bar-1']
            self.assertEqual(['override', '--time', '9:41'], status[4:7])
            tests = dict(commands)['xcodebuild-test-ru']
            self.assertIn('test-without-building', tests)
            self.assertIn('platform=iOS Simulator,id=C47B0285', tests)
            self.assertIn('-only-testing:WhoGaveWhatUITests/StoreScreenshotsUITests', tests)
            self.assertIn('-collect-test-diagnostics', tests)
            self.assertFalse((directory / 'ru.xcresult').exists())

    def test_an_already_booted_device_is_not_shut_down(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            commands, _ = self.run_with(directory, width=1284, height=2778)

            shots.run(directory, 'FCBC882C', display=shots.IPHONE_65)

            labels = [label for label, _ in commands]
            self.assertNotIn('simulator-boot', labels)
            self.assertNotIn('simulator-shutdown', labels)
            self.assertEqual('uninstall-ui-test-runner', labels[-1])
            self.assertEqual(sorted(f'large_{number:02d}_{slug}.png' for number, slug in enumerate(SLUGS, start=1)),
                             sorted(path.name for path in (directory / 'screenshots/ru').iterdir()))

    def test_a_duo_run_names_its_files_for_the_duo_set(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            self.run_with(directory, width=1398, height=2034)

            shots.run(directory, '079EE4B9', display=shots.IPHONE_DUO)

            self.assertEqual(sorted(f'duo_{number:02d}_{slug}.png' for number, slug in enumerate(SLUGS, start=1)),
                             sorted(path.name for path in (directory / 'screenshots/ru').iterdir()))
            metadata = json.loads((directory / 'metadata.json').read_text())
            self.assertEqual(('iphone-duo', 'iPhone Duo', 'iOS 27.1', ['1398x2034']),
                             (metadata['display'], metadata['device'], metadata['runtime'], metadata['sizes']))
            self.assertIn('src="screenshots/en-US/duo_01_home.png"', (directory / 'index.html').read_text())

    def test_an_ipad_run_names_its_files_for_the_ipad_set(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            self.run_with(directory, width=2064, height=2752)

            shots.run(directory, '61C17472', display=shots.IPAD_13)

            self.assertEqual(sorted(f'ipad_{number:02d}_{slug}.png' for number, slug in enumerate(SLUGS, start=1)),
                             sorted(path.name for path in (directory / 'screenshots/en-US').iterdir()))
            metadata = json.loads((directory / 'metadata.json').read_text())
            self.assertEqual(('ipad-13', 'iPad Pro 13-inch (M5)', 'iOS 27.0', ['2064x2752']),
                             (metadata['display'], metadata['device'], metadata['runtime'], metadata['sizes']))

    def test_a_wrong_device_fails_before_building(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            commands, _ = self.run_with(directory)

            with self.assertRaisesRegex(ValueError, 'does not produce the 6.3-inch set'):
                shots.run(directory, 'FCBC882C')

            self.assertEqual(['simulator-list'], [label for label, _ in commands])
            self.assertEqual('failure', json.loads((directory / 'metadata.json').read_text())['outcome'])

    def test_wrong_screenshot_size_fails_clearly_and_still_releases_the_device(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            commands, _ = self.run_with(directory, width=1320, height=2868)

            with self.assertRaisesRegex(ValueError, '1320x2868'):
                shots.run(directory, 'C47B0285')

            self.assertEqual('simulator-shutdown', commands[-1][0])
            metadata = json.loads((directory / 'metadata.json').read_text())
            self.assertEqual('failure', metadata['outcome'])
            self.assertIn('1320x2868', metadata['error'])

    def test_locale_mismatch_fails(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            self.run_with(directory, ru_slugs=SLUGS[:-1] + ['settings'])

            with self.assertRaisesRegex(ValueError, 'differ from en-US'):
                shots.run(directory, 'C47B0285')

    def test_a_failed_test_run_keeps_diagnostics_and_releases_the_device(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            commands, _ = self.run_with(directory)
            original = shots.tools.run_command.side_effect

            def failing(directory_, label, command, timeout, *, cwd=None):
                if label == 'xcodebuild-test-ru':
                    raise shots.tools.NativeCommandError('xcodebuild-test-ru exited 65')
                return original(directory_, label, command, timeout, cwd=cwd)

            shots.tools.run_command.side_effect = failing

            with self.assertRaisesRegex(shots.tools.NativeCommandError, 'exited 65'):
                shots.run(directory, 'C47B0285')

            self.assertEqual('simulator-shutdown', commands[-1][0])
            self.assertEqual('failure', json.loads((directory / 'metadata.json').read_text())['outcome'])
            self.assertFalse((directory / 'DerivedData').exists())

    def test_a_failed_release_step_is_reported_after_a_good_capture(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            self.run_with(directory)
            original = shots.tools.run_command.side_effect

            def failing(directory_, label, command, timeout, *, cwd=None):
                if label == 'simulator-shutdown':
                    raise shots.tools.NativeCommandError('simulator-shutdown timed out')
                return original(directory_, label, command, timeout, cwd=cwd)

            shots.tools.run_command.side_effect = failing

            with self.assertRaisesRegex(ValueError, 'not left as found: simulator-shutdown'):
                shots.run(directory, 'C47B0285')
            metadata = json.loads((directory / 'metadata.json').read_text())
            self.assertEqual('success', metadata['outcome'])

    def test_a_capture_needs_a_pool_device(self):
        with tempfile.TemporaryDirectory() as temporary, patch('sys.stderr'), self.assertRaises(SystemExit):
            shots.main([temporary, '--display', 'iphone-6.3'])


class StatusBarTests(unittest.TestCase):
    def test_retries_and_then_keeps_the_real_status_bar(self):
        calls = []

        def failing(directory, label, command, timeout, **kwargs):
            calls.append(label)
            raise shots.tools.NativeCommandError(f'{label} timed out after {timeout}s')

        with patch.object(shots.tools, 'run_command', side_effect=failing):
            self.assertEqual(shots.override_status_bar(Path('/tmp'), 'UDID', attempts=3), 'real')
        self.assertEqual(calls, ['status-bar-1', 'status-bar-2', 'status-bar-3'])

    def test_stops_after_the_first_success(self):
        calls = []

        def flaky(directory, label, command, timeout, **kwargs):
            calls.append(label)
            if len(calls) == 1:
                raise shots.tools.NativeCommandError('status-bar-1 timed out after 90s')

        with patch.object(shots.tools, 'run_command', side_effect=flaky):
            self.assertEqual(shots.override_status_bar(Path('/tmp'), 'UDID'), 'overridden')
        self.assertEqual(calls, ['status-bar-1', 'status-bar-2'])


if __name__ == '__main__':
    unittest.main()

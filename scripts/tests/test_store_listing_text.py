import unittest
from pathlib import Path

METADATA = Path(__file__).resolve().parents[2] / 'fastlane' / 'metadata'
LOCALES = ('en-US', 'ru')
# App Store Connect limits in characters. The name is set by hand in App Store Connect, so there is no name.txt.
LIMITS = {'subtitle.txt': 30, 'keywords.txt': 100, 'promotional_text.txt': 170, 'description.txt': 4000}


def emoji(text):
    """Characters App Store Connect rejects in listing text: pictographs, symbols-and-dingbats, flags, variation selector."""
    return sorted({character for character in text
                   if 0x1F000 <= ord(character) <= 0x1FAFF or 0x2600 <= ord(character) <= 0x27BF
                   or ord(character) in (0xFE0F, 0x200D)})


class StoreListingTextTests(unittest.TestCase):
    def test_fields_fit_app_store_connect_limits(self):
        for locale in LOCALES:
            for name, limit in LIMITS.items():
                with self.subTest(locale=locale, field=name):
                    text = (METADATA / locale / name).read_text().strip()
                    self.assertTrue(text)
                    self.assertLessEqual(len(text), limit)

    def test_the_name_is_left_to_app_store_connect(self):
        for locale in LOCALES:
            self.assertFalse((METADATA / locale / 'name.txt').exists())

    def test_no_emoji_in_listing_text(self):
        for path in sorted(METADATA.rglob('*.txt')):
            with self.subTest(path=path.relative_to(METADATA)):
                self.assertEqual([], emoji(path.read_text()))

    def test_emoji_detection(self):
        self.assertEqual(['😉'], emoji('у вас 😉'))
        self.assertEqual([], emoji('«Кто Че Подарил» — учёт • подарков ;)'))


if __name__ == '__main__':
    unittest.main()

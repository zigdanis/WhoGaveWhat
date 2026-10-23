import unittest
from pathlib import Path

METADATA = Path(__file__).resolve().parents[2] / 'fastlane' / 'metadata'
LOCALES = ('en-US', 'ru')
# App Store Connect limits in characters. The name is set by hand in App Store Connect, so there is no name.txt.
LIMITS = {'subtitle.txt': 30, 'keywords.txt': 100, 'promotional_text.txt': 170, 'description.txt': 4000}


# Blocks that hold emoji: Miscellaneous Technical (⌚ ⏰), Miscellaneous Symbols and Dingbats (☀ ✅),
# Miscellaneous Symbols and Arrows (⭐ ⬛), and the pictograph planes (😉 🎁, flags), plus the emoji
# variation selector and zero-width joiner. Text punctuation such as — « » • → stays allowed.
EMOJI_BLOCKS = ((0x2300, 0x23FF), (0x2600, 0x27BF), (0x2B00, 0x2BFF), (0x1F000, 0x1FAFF))


def emoji(text):
    """Characters App Store Connect rejects in listing text."""
    return sorted({character for character in text
                   if any(start <= ord(character) <= end for start, end in EMOJI_BLOCKS)
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
        for character in ('😉', '🎁', '⏰', '⌚', '⭐', '✅', '☀'):
            with self.subTest(character=character):
                self.assertEqual([character], emoji(f'у вас {character}'))
        self.assertEqual([], emoji('«Кто Че Подарил» — учёт • подарков → ;)'))


if __name__ == '__main__':
    unittest.main()

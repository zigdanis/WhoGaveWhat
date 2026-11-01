import re
import unittest
from pathlib import Path

METADATA = Path(__file__).resolve().parents[2] / 'fastlane' / 'metadata'
LOCALES = ('en-US', 'ru')
# App Store Connect limits in characters. The name is set by hand in App Store Connect, so there is no name.txt.
# release_notes.txt is the version's What's New: App Store Connect rejects it on an app's first version, but
# every update needs it, so each locale must carry one.
LIMITS = {'subtitle.txt': 30, 'keywords.txt': 100, 'promotional_text.txt': 170, 'description.txt': 4000,
          'release_notes.txt': 4000}


# The names as set by hand in App Store Connect, to check that keywords don't repeat their words.
NAMES = {'en-US': 'Who Gave What', 'ru': 'Кто Че Подарил'}
# The Russian name has to be findable in storefronts that index only English (U.K.), such as Kazakhstan. The
# app has no en-GB localization, so those storefronts index the primary en-US one, and its keywords carry the
# words of the Russian name (and «что» for «кто что подарил»). See docs/app-store.md, "Search by name".
RUSSIAN_NAME_WORDS = ('кто', 'че', 'подарил', 'что')


def words(text):
    # App Store search treats ё as е, so they count as the same word.
    return set(re.findall(r'\w+', text.lower().replace('ё', 'е')))


def keywords(locale):
    return (METADATA / locale / 'keywords.txt').read_text().strip().split(',')


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

    def test_keywords_are_comma_separated_without_spaces_around(self):
        for locale in LOCALES:
            for keyword in keywords(locale):
                with self.subTest(locale=locale, keyword=keyword):
                    self.assertTrue(keyword)
                    self.assertEqual(keyword.strip(), keyword)

    def test_keywords_do_not_repeat_the_name_or_subtitle(self):
        for locale in LOCALES:
            subtitle = (METADATA / locale / 'subtitle.txt').read_text()
            with self.subTest(locale=locale):
                self.assertEqual(set(), words(','.join(keywords(locale))) & words(NAMES[locale] + ' ' + subtitle))

    def test_keywords_have_no_duplicate_words(self):
        for locale in LOCALES:
            found = [word for keyword in keywords(locale) for word in sorted(words(keyword))]
            with self.subTest(locale=locale):
                self.assertEqual(sorted(found), sorted(set(found)))

    def test_the_russian_name_is_searchable_in_english_storefronts(self):
        self.assertFalse((METADATA / 'en-GB').exists(), 'en-GB would replace en-US in those storefronts; move the '
                         'Russian name words there first and update docs/app-store.md')
        self.assertLessEqual(set(RUSSIAN_NAME_WORDS), set(keywords('en-US')))
        self.assertIn('что', keywords('ru'))

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

import importlib.util
import unittest
from pathlib import Path

spec = importlib.util.spec_from_file_location("prepare", Path(__file__).parents[1] / "scripts/prepare.py")
prepare = importlib.util.module_from_spec(spec)
spec.loader.exec_module(prepare)


class EPUBTests(unittest.TestCase):
    def test_notes_excluded_but_linked_word_preserved(self):
        parser = prepare.Paragraphs()
        parser.feed('<p>Some <a epub:type="noteref">word</a> here.</p><aside><p>中文注释</p></aside><p>Next paragraph.</p>')
        parser.flush()
        self.assertEqual(parser.items, ["Some word here.", "Next paragraph."])

    def test_inline_markup_and_entities_preserved(self):
        parser = prepare.Paragraphs()
        parser.feed('<p>It is <b>quite</b> clear &amp; useful.<br>Really.</p>')
        parser.flush()
        self.assertEqual(parser.items, ["It is quite clear & useful. Really."])


if __name__ == "__main__":
    unittest.main()

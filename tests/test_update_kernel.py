import importlib.util
from pathlib import Path
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / 'scripts/update-kernel.py'
spec = importlib.util.spec_from_file_location('update_kernel', SCRIPT)
updater = importlib.util.module_from_spec(spec)
spec.loader.exec_module(updater)

OLD = 'a' * 40
NEW = 'b' * 40
OBJECT = 'c' * 40
CURRENT = 'linux-msft-wsl-6.6.9.1'


def tag(name, commit=NEW):
    return f'{commit}\trefs/tags/{name}\n'


class ReleaseSelectionTests(unittest.TestCase):
    def select(self, tags):
        return updater.select_release(tag(CURRENT, OLD) + tags, CURRENT, OLD)

    def test_selects_numeric_latest_in_same_series(self):
        tags = tag('linux-msft-wsl-6.6.99.1') + tag('linux-msft-wsl-6.6.100.1')
        self.assertEqual(('linux-msft-wsl-6.6.100.1', NEW), self.select(tags))

    def test_excludes_new_series_prereleases_and_older_tags(self):
        tags = (tag('linux-msft-wsl-6.18.1.1') + tag('linux-msft-wsl-6.6.100.1-rc1')
                + tag('linux-msft-wsl-6.6.8.9'))
        self.assertIsNone(self.select(tags))

    def test_annotated_tags_use_peeled_commit_regardless_of_order(self):
        name = 'linux-msft-wsl-6.6.100.1'
        records = [tag(name, OBJECT), tag(name + '^{}', NEW)]
        for tags in (''.join(records), ''.join(reversed(records))):
            with self.subTest(tags=tags):
                self.assertEqual((name, NEW), self.select(tags))

    def test_retagged_current_release_is_rejected(self):
        with self.assertRaisesRegex(ValueError, 'release tag moved'):
            updater.select_release(tag(CURRENT, NEW), CURRENT, OLD)

    def test_missing_current_release_is_rejected(self):
        with self.assertRaisesRegex(ValueError, 'disappeared'):
            updater.select_release(tag('linux-msft-wsl-6.6.100.1'), CURRENT, OLD)

    def test_invalid_commit_advertisement_is_rejected(self):
        with self.assertRaisesRegex(ValueError, 'Invalid upstream'):
            self.select(tag('linux-msft-wsl-6.6.100.1', 'not-a-commit'))


if __name__ == '__main__':
    unittest.main()

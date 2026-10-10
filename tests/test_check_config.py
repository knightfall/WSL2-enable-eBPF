import importlib.util
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / 'scripts/check-config.py'
spec = importlib.util.spec_from_file_location('check_config', SCRIPT)
validator = importlib.util.module_from_spec(spec)
spec.loader.exec_module(validator)


class ConfigValidationTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.config = Path(self.directory.name) / 'config'
        self.fragment = Path(self.directory.name) / 'fragment'
        self.fragment.write_text('CONFIG_BPF=y\nCONFIG_BPF_KPROBE_OVERRIDE=y\n')
        self.valid = ('CONFIG_BPF=y\nCONFIG_BPF_KPROBE_OVERRIDE=y\n'
                      'CONFIG_LSM="landlock,apparmor,bpf"\n')

    def test_complete_config_preserves_other_lsms(self):
        self.config.write_text(self.valid)
        self.assertEqual([], validator.check_config(self.config, self.fragment))

    def test_missing_override_is_reported_even_when_bpf_is_present(self):
        self.config.write_text('CONFIG_BPF=y\nCONFIG_LSM="apparmor,bpf"\n')
        self.assertEqual(['CONFIG_BPF_KPROBE_OVERRIDE: expected y, got missing'],
                         validator.check_config(self.config, self.fragment))

    def test_disabled_and_modular_values_do_not_satisfy_builtin_profile(self):
        for value in ('# CONFIG_BPF_KPROBE_OVERRIDE is not set',
                      'CONFIG_BPF_KPROBE_OVERRIDE=m'):
            with self.subTest(value=value):
                self.config.write_text('CONFIG_BPF=y\n' + value + '\nCONFIG_LSM="bpf"\n')
                errors = validator.check_config(self.config, self.fragment)
                self.assertEqual(1, len(errors))
                self.assertIn('CONFIG_BPF_KPROBE_OVERRIDE: expected y, got', errors[0])

    def test_compilation_without_active_lsm_fails_cli(self):
        self.config.write_text(self.valid.replace(',bpf', ''))
        result = subprocess.run([sys.executable, str(SCRIPT), str(self.config),
                                 '--fragment', str(self.fragment)], capture_output=True, text=True)
        self.assertEqual(1, result.returncode)
        self.assertIn('CONFIG_LSM must include bpf', result.stderr)

    def test_lsm_name_must_match_a_whole_entry(self):
        self.config.write_text(self.valid.replace(',bpf', ',not_bpf'))
        self.assertEqual(['CONFIG_LSM must include bpf while preserving the other LSMs'],
                         validator.check_config(self.config, self.fragment))

    def test_inline_comments_are_accepted_but_do_not_become_values(self):
        self.fragment.write_text('CONFIG_BPF=y # BPF core\n')
        self.config.write_text(self.valid)
        self.assertEqual([], validator.check_config(self.config, self.fragment))

    def test_valid_unrelated_kernel_metadata_is_accepted(self):
        # Microsoft's pinned config includes PANIC_TIMEOUT=-1. Such metadata
        # must not prevent validation of the requested BPF options.
        self.config.write_text(self.valid + 'CONFIG_PANIC_TIMEOUT=-1\n'
                               'CONFIG_BASE_SMALL=0\nCONFIG_PHYSICAL_START=0x1000000\n'
                               'CONFIG_DEFAULT_HOSTNAME="name#with-hash"\n')
        self.assertEqual([], validator.check_config(self.config, self.fragment))

    def test_empty_or_malformed_fragment_cannot_pass(self):
        self.config.write_text(self.valid)
        for text in ('# no requests\n', 'CONFIG_BPF=invalid\n', 'CONFIG_BPF=y\nCONFIG_BPF=y\n'):
            with self.subTest(text=text):
                self.fragment.write_text(text)
                with self.assertRaises(ValueError):
                    validator.check_config(self.config, self.fragment)


if __name__ == '__main__':
    unittest.main()

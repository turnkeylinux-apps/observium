"""Interactive setup asks for a password; preseeding keeps it off argv."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class FirstbootTest(unittest.TestCase):
    def run_hook(self, password):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'bin').mkdir()
            helper = root / 'bin/observium.py'
            helper.write_text('#!/bin/sh\nprintf "%s" "$*" > "$RESULT.args"\n'
                              'if [ "$1" = --pass-stdin ]; then cat > "$RESULT.stdin"; fi\n')
            helper.chmod(0o755)
            config = root / 'defaults'
            config.write_text('INITHOOKS_PATH=' + str(root) + '\nINITHOOKS_CONF=' + str(root / 'missing') + '\n')
            hook = root / 'hook'
            hook.write_text((ROOT / 'overlay/usr/lib/inithooks/firstboot.d/40observium').read_text().replace('/etc/default/inithooks', str(config)))
            result = subprocess.run(['bash', str(hook)], stdin=subprocess.DEVNULL,
                                    env=dict(os.environ, APP_PASS=password, RESULT=str(root / 'result')),
                                    text=True, capture_output=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            args = (root / 'result.args').read_text()
            stdin = (root / 'result.stdin').read_text() if (root / 'result.stdin').exists() else None
            return args, stdin, result.stdout + result.stderr

    def test_interactive_setup_retains_terminal_input(self):
        self.assertEqual(self.run_hook('')[:2], ('', None))

    def test_preseed_is_sent_through_stdin_only(self):
        secret = 'test-only-preseed'
        args, stdin, output = self.run_hook(secret)
        self.assertEqual((args, stdin), ('--pass-stdin', secret))
        self.assertNotIn(secret, output)


if __name__ == '__main__':
    unittest.main()

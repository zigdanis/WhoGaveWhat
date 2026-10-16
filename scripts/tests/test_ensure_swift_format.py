import os
from pathlib import Path
import subprocess
import unittest

SCRIPT = Path(__file__).parents[1] / 'ensure-swift-format.sh'


def run(*arguments, **environment):
    env = {'PATH': os.environ['PATH'], 'HOME': '/home/tester', **environment}
    return subprocess.run([str(SCRIPT), *arguments], env=env, capture_output=True, text=True, timeout=10)


class EnsureSwiftFormatPathTest(unittest.TestCase):
    def test_linux_uses_xdg_cache_and_architecture_specific_toolchain(self):
        result = run('--print-install-dir', SWIFT_FORMAT_OS='Linux', SWIFT_FORMAT_ARCH='aarch64',
                     XDG_CACHE_HOME='/cache')
        self.assertEqual(result.stdout.strip(), '/cache/whogavewhat/swift-format/6.3.3')
        result = run('--print-url', SWIFT_FORMAT_OS='Linux', SWIFT_FORMAT_ARCH='aarch64')
        self.assertEqual(result.stdout.strip(), 'https://download.swift.org/swift-6.3.3-release/debian12-aarch64/'
                         'swift-6.3.3-RELEASE/swift-6.3.3-RELEASE-debian12-aarch64.tar.gz')
        result = run('--print-url', SWIFT_FORMAT_OS='Linux', SWIFT_FORMAT_ARCH='x86_64')
        self.assertTrue(result.stdout.strip().endswith('/debian12/swift-6.3.3-RELEASE/swift-6.3.3-RELEASE-debian12.tar.gz'))

    def test_defaults_to_platform_cache_directories(self):
        self.assertEqual(run('--print-install-dir', SWIFT_FORMAT_OS='Linux', SWIFT_FORMAT_ARCH='x86_64').stdout.strip(),
                         '/home/tester/.cache/whogavewhat/swift-format/6.3.3')
        self.assertEqual(run('--print-install-dir', SWIFT_FORMAT_OS='Darwin', SWIFT_FORMAT_ARCH='arm64').stdout.strip(),
                         '/home/tester/Library/Caches/whogavewhat/swift-format/6.3.3')

    def test_rejects_unsupported_platforms_without_downloading(self):
        for os_name, arch in (('Linux', 'riscv64'), ('FreeBSD', 'x86_64')):
            result = run('--print-url', SWIFT_FORMAT_OS=os_name, SWIFT_FORMAT_ARCH=arch)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn('no pinned swift-format download', result.stderr)


if __name__ == '__main__':
    unittest.main()

import contextlib
import importlib.util
import io
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('testflight_secrets', Path(__file__).parents[1] / 'testflight-secrets.py')
secrets = importlib.util.module_from_spec(spec)
spec.loader.exec_module(secrets)


class TestflightSecretsTest(unittest.TestCase):
    def test_rejects_readable_by_others_and_git_checkout_files(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'input.json'
            path.write_text('{}')
            path.chmod(0o644)
            with self.assertRaises(ValueError):
                secrets.restricted_file(path)
            path.chmod(0o600)
            (Path(directory) / '.git').mkdir()
            with self.assertRaises(ValueError):
                secrets.restricted_file(path)

    def import_credentials(self, directory, secret_status):
        directory = Path(directory)
        key = directory / 'key.p8'
        key.write_text('fake-private-content')
        key.chmod(0o600)
        source = directory / 'input.json'
        source.write_text(json.dumps({'ASC_KEY_ID': 'KEYID', 'ASC_ISSUER_ID': 'issuer',
                                      'ASC_PRIVATE_KEY_PATH': str(key), 'MATCH_PASSWORD': 'fake-match-password'}))
        source.chmod(0o600)
        calls = []

        def run(command, **kwargs):
            calls.append((command, kwargs))
            if command[:2] == ['gh', 'api']:
                if command[2].endswith('/deployment-branch-policies'):
                    response = {'branch_policies': [{'name': 'master', 'type': 'branch'}]}
                elif command[2].endswith('/environments/testflight'):
                    response = {'deployment_branch_policy': {'custom_branch_policies': True}}
                else:
                    response = {'full_name': 'zigdanis/WhoGaveWhat', 'private': False}
                return subprocess.CompletedProcess(command, 0, stdout=json.dumps(response), stderr='')
            status = 0 if command[0] == 'openssl' else secret_status
            return subprocess.CompletedProcess(command, status, stdout='', stderr='error')

        output = io.StringIO()
        with patch.object(sys, 'argv', ['testflight-secrets.py', '--repo', 'zigdanis/WhoGaveWhat', str(source)]), patch.object(secrets.subprocess, 'run', run), contextlib.redirect_stdout(output):
            if secret_status:
                with self.assertRaises(RuntimeError):
                    secrets.main()
            else:
                secrets.main()
        self.assertNotIn('fake-private-content', output.getvalue())
        self.assertNotIn('fake-match-password', output.getvalue())
        for command, kwargs in calls:
            self.assertNotIn('fake-private-content', ' '.join(command))
            self.assertNotIn('fake-match-password', ' '.join(command))
            if command[:2] == ['gh', 'secret']:
                self.assertIn('zigdanis/WhoGaveWhat', command)
                self.assertEqual(command[-2:], ['--env', 'testflight'])
                self.assertIn('input', kwargs)
        return source, key

    def test_success_uses_environment_stdin_and_removes_input_copies(self):
        with tempfile.TemporaryDirectory() as directory:
            source, key = self.import_credentials(directory, 0)
            self.assertFalse(source.exists())
            self.assertFalse(key.exists())

    def test_failed_import_retains_input_files_and_does_not_echo_values(self):
        with tempfile.TemporaryDirectory() as directory:
            source, key = self.import_credentials(directory, 1)
            self.assertTrue(source.exists())
            self.assertTrue(key.exists())

    def test_noncanonical_repository_is_rejected_before_reading_credentials(self):
        with (patch.object(sys, 'argv', ['testflight-secrets.py', '--repo', 'example/public', '/missing/credentials.json']),
              patch.object(secrets.subprocess, 'run', return_value=subprocess.CompletedProcess(
                  [], 0, stdout='{"full_name": "example/public", "private": true}', stderr='')) as run,
              patch.object(secrets, 'restricted_file') as restricted_file):
            with self.assertRaisesRegex(RuntimeError, 'canonical zigdanis/WhoGaveWhat'):
                secrets.main()
            restricted_file.assert_not_called()
            run.assert_called_once_with(['gh', 'api', 'repos/example/public'], text=True, capture_output=True)

    def test_unsafe_environment_is_rejected_before_reading_credentials(self):
        for policy, branches in [
            ({'custom_branch_policies': False}, [{'name': 'master', 'type': 'branch'}]),
            ({'custom_branch_policies': True}, [{'name': 'master', 'type': 'tag'}]),
            ({'custom_branch_policies': True}, [{'name': 'master', 'type': 'branch'},
                                              {'name': '*', 'type': 'branch'}]),
        ]:
            with self.subTest(policy=policy, branches=branches):
                responses = [
                    {'full_name': 'zigdanis/WhoGaveWhat', 'private': False},
                    {'deployment_branch_policy': policy}, {'branch_policies': branches},
                ]
                calls = [subprocess.CompletedProcess([], 0, stdout=json.dumps(r), stderr='') for r in responses]
                with (patch.object(sys, 'argv', ['testflight-secrets.py', '--repo', 'zigdanis/WhoGaveWhat', '/missing/input.json']),
                      patch.object(secrets.subprocess, 'run', side_effect=calls) as run,
                      patch.object(secrets, 'restricted_file') as restricted_file):
                    with self.assertRaisesRegex(RuntimeError, 'only the master branch'):
                        secrets.main()
                    restricted_file.assert_not_called()
                    self.assertEqual(3, run.call_count)

    def test_repository_must_be_explicit(self):
        with (patch.object(sys, 'argv', ['testflight-secrets.py']),
              patch.object(secrets.subprocess, 'run') as run,
              contextlib.redirect_stderr(io.StringIO())):
            with self.assertRaises(SystemExit) as error:
                secrets.main()
            self.assertEqual(2, error.exception.code)
            run.assert_not_called()

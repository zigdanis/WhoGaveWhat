import contextlib
import importlib.util
import io
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('testflight', Path(__file__).parents[1] / 'testflight.py')
testflight = importlib.util.module_from_spec(spec)
spec.loader.exec_module(testflight)


class TestflightNotesTest(unittest.TestCase):
    def test_notes_dispatch_uses_original_receipt_identity_and_both_locales(self):
        recorded = {'source_sha': 'a' * 40, 'version': '2.1.4', 'build_number': '26', 'phase': 'available'}
        calls = []

        def gh(*args, data=None):
            calls.append((args, data))
            if args == ('api', 'repos/zigdanis/WhoGaveWhat'):
                return '{"full_name": "zigdanis/WhoGaveWhat", "private": false}'
            if args[0] == 'run':
                return '[]'
            return json.dumps({'html_url': 'https://example.test/run/101', 'workflow_run_id': 101})

        with tempfile.TemporaryDirectory() as directory:
            notes = Path(directory) / 'notes.json'
            notes.write_text(json.dumps({'en': "What's New\nPhoto saving fixed.\n\nWhat to Test\nEdit a photo.",
                                         'ru': 'Что нового\nИсправлено сохранение фото.\n\nЧто проверить\nИзмените фото.'},
                                        ensure_ascii=False), encoding='utf-8')
            with (patch.object(sys, 'argv', ['testflight.py', '--repo', 'zigdanis/WhoGaveWhat', 'notes', '100', str(notes)]),
                  patch.object(testflight, 'readiness'), patch.object(testflight, 'receipt', return_value=recorded),
                  patch.object(testflight, 'gh', side_effect=gh), contextlib.redirect_stdout(io.StringIO())):
                testflight.main()
        payload = calls[-1][1]
        self.assertEqual('master', payload['ref'])
        self.assertEqual('notes', payload['inputs']['operation'])
        self.assertEqual('100', payload['inputs']['resume_run_id'])
        self.assertEqual(recorded['source_sha'], payload['inputs']['source_sha'])
        self.assertIn('What to Test', payload['inputs']['notes_en'])
        self.assertIn('Что проверить', payload['inputs']['notes_ru'])

    def test_noncanonical_repository_is_rejected_before_readiness_or_dispatch(self):
        with (patch.object(sys, 'argv', ['testflight.py', '--repo', 'example/public', 'preflight']),
              patch.object(testflight, 'readiness') as readiness,
              patch.object(testflight, 'gh', return_value='{"full_name": "example/public", "private": true}') as gh):
            with self.assertRaisesRegex(RuntimeError, 'canonical zigdanis/WhoGaveWhat'):
                testflight.main()
            readiness.assert_not_called()
            gh.assert_called_once_with('api', 'repos/example/public')

    def test_public_canonical_repository_ready_requires_master_only_environment(self):
        responses = [
            {'full_name': 'zigdanis/WhoGaveWhat', 'private': False},
            {'deployment_branch_policy': {'custom_branch_policies': True}},
            {'branch_policies': [{'name': 'master', 'type': 'branch'}]},
            {'secrets': [{'name': name} for name in testflight.REQUIRED_SECRETS]},
        ]
        with (patch.object(sys, 'argv', ['testflight.py', '--repo', 'zigdanis/WhoGaveWhat', 'ready']),
              patch.object(testflight, 'gh', side_effect=[json.dumps(r) for r in responses]) as gh,
              contextlib.redirect_stdout(io.StringIO())):
            testflight.main()
        self.assertEqual(4, gh.call_count)
        self.assertEqual(('api', 'repos/zigdanis/WhoGaveWhat/environments/testflight/secrets'), gh.call_args.args)

    def test_unsafe_environment_is_rejected_before_dispatch(self):
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
                with (patch.object(sys, 'argv', ['testflight.py', '--repo', 'zigdanis/WhoGaveWhat', 'preflight']),
                      patch.object(testflight, 'gh', side_effect=[json.dumps(r) for r in responses]) as gh):
                    with self.assertRaisesRegex(RuntimeError, 'only the master branch'):
                        testflight.main()
                self.assertEqual(3, gh.call_count)

    def test_repository_must_be_explicit(self):
        with (patch.object(sys, 'argv', ['testflight.py', 'ready']),
              patch.object(testflight, 'gh') as gh,
              contextlib.redirect_stderr(io.StringIO())):
            with self.assertRaises(SystemExit) as error:
                testflight.main()
            self.assertEqual(2, error.exception.code)
            gh.assert_not_called()

    def test_notes_require_both_translations_with_utf8_byte_limit(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'notes.json'
            for value in [[], {'en': 'Only English'}, {'en': 'Text', 'ru': ' '}, {'en': 'Text', 'ru': 'я' * 2001}]:
                path.write_text(json.dumps(value, ensure_ascii=False), encoding='utf-8')
                with self.assertRaises(ValueError):
                    testflight.read_notes(path)

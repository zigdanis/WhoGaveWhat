import importlib.util
import json
import sys
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import evidence_validation as evidence


def load_script(name):
    spec = importlib.util.spec_from_file_location(name, Path(__file__).resolve().parents[1] / (name + '.py'))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


smoke = load_script('run-app-smoke')
gate = load_script('pr-evidence-gate')


class EvidenceTests(unittest.TestCase):
    def setUp(self):
        self.sha = 'a' * 40
        self.image = 'https://github.com/user-attachments/assets/image-uuid'
        self.video = 'https://github.com/user-attachments/assets/video-uuid'
        self.metadata = dict(head_sha=self.sha, run_id='123', run_attempt='2', evidence_kind='app-smoke',
                             images=[self.image], videos=[self.video])

    def body(self):
        return (evidence.START + '\n' + evidence.metadata_comment(self.metadata) + '\n'
                + f'![Home]({self.image})\n\n{self.video}\n' + evidence.END)

    def test_both_media_kinds_are_required_and_embedded(self):
        self.assertEqual(evidence.parse_evidence(self.body()), self.metadata)
        for key in ['images', 'videos']:
            original = self.metadata[key]
            self.metadata[key] = []
            with self.subTest(key=key), self.assertRaises(ValueError):
                evidence.parse_evidence(self.body())
            self.metadata[key] = original
        with self.assertRaises(ValueError):
            evidence.parse_evidence(self.body().replace(f'![Home]({self.image})', 'Screenshot omitted'))
        with self.assertRaises(ValueError):
            evidence.parse_evidence(self.body().replace('\n' + self.video + '\n', '\nRecording omitted\n'))

    def test_external_urls_duplicate_media_and_malformed_provenance_fail(self):
        for key, value in [('head_sha', 'bad'), ('run_id', '../123'), ('run_attempt', '0'),
                           ('videos', [self.image]), ('images', ['https://example.com/image.png'])]:
            original = self.metadata[key]
            self.metadata[key] = value
            with self.subTest(key=key), self.assertRaises(ValueError):
                evidence.parse_evidence(self.body())
            self.metadata[key] = original
        for body in [self.body() + evidence.START, self.body().replace(evidence.END, ''),
                     evidence.END + self.body()]:
            with self.assertRaises(ValueError):
                evidence.parse_evidence(body)

    def test_gate_rejects_stale_commit(self):
        pr = dict(body=self.body(), head={'sha': 'b' * 40})
        with patch.object(evidence, 'gh') as mocked, self.assertRaisesRegex(ValueError, 'stale'):
            evidence.validate('owner/repo', pr)
        mocked.assert_not_called()

    def test_gate_requires_latest_successful_pr_attempt(self):
        run = dict(status='completed', conclusion='success', event='pull_request', head_sha=self.sha, run_attempt=2)
        def mocked(*args):
            return json.dumps([{'databaseId': 123}]) if args[0] == 'run' else json.dumps(run)
        with patch.object(evidence, 'gh', side_effect=mocked):
            evidence.checked_run('owner/repo', self.sha, self.metadata)
            for key, value in [('conclusion', 'failure'), ('status', 'in_progress'), ('run_attempt', 3),
                               ('head_sha', 'b' * 40), ('event', 'push')]:
                original = run[key]
                run[key] = value
                with self.subTest(key=key), self.assertRaises(ValueError):
                    evidence.checked_run('owner/repo', self.sha, self.metadata)
                run[key] = original
        with patch.object(evidence, 'gh', return_value='[{"databaseId":124}]'), self.assertRaises(ValueError):
            evidence.checked_run('owner/repo', self.sha, self.metadata)

    def test_body_change_during_gate_prevents_success_status(self):
        pr = dict(state='open', body=self.body(), head={'sha': self.sha}, html_url='https://example.com/pr')
        current = dict(pr, body='changed by author')
        with patch.object(gate, 'gh', side_effect=[json.dumps(pr), json.dumps(current)]), \
                patch.object(gate, 'validate'), patch.object(gate, 'update_status') as status:
            self.assertFalse(gate.check('owner/repo', 1, publish_status=True))
        self.assertEqual(status.call_args.args[2], 'failure')


class SimulatorSelectionTests(unittest.TestCase):
    def test_booted_iphone_is_reused_and_latest_preferred_runtime_selected(self):
        devices = {'devices': {
            'com.apple.CoreSimulator.SimRuntime.iOS-26-5': [
                dict(name='iPhone 17 Pro', isAvailable=True, state='Shutdown', udid='new')],
            'com.apple.CoreSimulator.SimRuntime.iOS-26-2': [
                dict(name='iPhone 16', isAvailable=True, state='Booted', udid='existing')],
        }}
        self.assertEqual(smoke.select_simulator(devices)['udid'], 'existing')
        devices['devices']['com.apple.CoreSimulator.SimRuntime.iOS-26-2'][0]['state'] = 'Shutdown'
        self.assertEqual(smoke.select_simulator(devices)['udid'], 'new')
        with self.assertRaises(ValueError):
            smoke.select_simulator({'devices': {'runtime': [dict(name='iPhone 16', isAvailable=True, state='Shutdown')]}})


if __name__ == '__main__':
    unittest.main()

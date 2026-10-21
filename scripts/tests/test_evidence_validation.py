import importlib.util
import io
import json
import sys
import unittest
from contextlib import redirect_stdout
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

    def test_screenshots_are_required_and_a_requested_clip_is_optional_but_embedded(self):
        self.assertEqual(evidence.parse_evidence(self.body()), self.metadata)
        self.metadata['images'] = []
        with self.assertRaises(ValueError):
            evidence.parse_evidence(self.body())
        self.metadata['images'] = [self.image]
        for videos in ([], None):
            self.metadata['videos'] = videos
            if videos is None:
                del self.metadata['videos']
            with self.subTest(videos=videos):
                body = self.body().replace(f'{self.video}\n', '')
                self.assertEqual([], evidence.parse_evidence(body)['videos'])
        self.metadata['videos'] = [self.video]
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
        run = dict(id=123, status='completed', conclusion='success', event='pull_request', head_sha=self.sha, run_attempt=2)
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
        def newer(*args):
            return json.dumps([{'databaseId': 124}]) if args[0] == 'run' else json.dumps(dict(run, id=124))
        with patch.object(evidence, 'gh', side_effect=newer), self.assertRaises(ValueError):
            evidence.checked_run('owner/repo', self.sha, self.metadata)

    def test_manual_clip_dispatch_for_the_head_is_accepted_and_push_runs_are_ignored(self):
        accepted = dict(id=123, status='completed', conclusion='success', event='pull_request',
                        head_sha=self.sha, run_attempt=2)
        for event, expected in (('workflow_dispatch', 124), ('push', 123)):
            newer = dict(accepted, id=124, event=event, run_attempt=1)
            def mocked(*args):
                if args[:2] == ('run', 'list'):
                    self.assertNotIn('--event', args)
                    return json.dumps([{'databaseId': 124}, {'databaseId': 123}])
                return json.dumps(newer if args[1].endswith('/124') else accepted)
            with self.subTest(event=event), patch.object(evidence, 'gh', side_effect=mocked):
                self.assertEqual(expected, evidence.latest_pr_acceptance_run('owner/repo', self.sha)['id'])

    def test_later_verified_entirely_skipped_native_run_does_not_displace_acceptance(self):
        accepted = dict(id=123, status='completed', conclusion='success', event='pull_request',
                        head_sha=self.sha, run_attempt=2)
        skipped = dict(accepted, id=124, run_attempt=1)
        skipped_jobs = {'total_count': 3, 'jobs': [
            dict(name='Unit tests and app smoke', status='completed', conclusion='skipped'),
            dict(name='Unit tests and app smoke (iPhone 18 Pro)', status='completed', conclusion='skipped'),
            dict(name='Spotlight diagnostics (non-acceptance)', status='completed', conclusion='skipped')]}
        actual_jobs = {'total_count': 3, 'jobs': [
            dict(name='Unit tests and app smoke', status='completed', conclusion='success'),
            dict(skipped_jobs['jobs'][1], conclusion='success'), skipped_jobs['jobs'][2]]}
        def mocked(*args):
            if args[:2] == ('run', 'list'):
                return json.dumps([{'databaseId': 124}, {'databaseId': 123}])
            endpoint = args[1]
            if endpoint.endswith('/124'):
                return json.dumps(skipped)
            if endpoint.endswith('/123'):
                return json.dumps(accepted)
            return json.dumps(skipped_jobs if '/124/' in endpoint else actual_jobs)
        with patch.object(evidence, 'gh', side_effect=mocked):
            self.assertEqual(123, evidence.checked_run('owner/repo', self.sha, self.metadata)['id'])
            output = io.StringIO()
            with redirect_stdout(output):
                evidence.main(['owner/repo', self.sha])
            self.assertEqual(123, json.loads(output.getvalue())['id'])

    def test_newer_failed_running_or_ambiguous_native_runs_remain_authoritative(self):
        skipped_jobs = [
            dict(name='Unit tests and app smoke', status='completed', conclusion='skipped'),
            dict(name='Unit tests and app smoke (iPhone 18 Pro)', status='completed', conclusion='skipped'),
            dict(name='Spotlight diagnostics (non-acceptance)', status='completed', conclusion='skipped')]
        for condition in ('failed', 'running', 'queued', 'cancelled', 'native-success', 'unknown-job',
                          'missing-job', 'incomplete-jobs', 'unfinished-job', 'rerun'):
            with self.subTest(condition=condition):
                newer = dict(id=124, status='completed', conclusion='success', event='pull_request',
                             head_sha=self.sha, run_attempt=1)
                jobs = [dict(job) for job in skipped_jobs]
                total = 3
                if condition in ('failed', 'cancelled'):
                    newer['conclusion'] = 'failure' if condition == 'failed' else 'cancelled'
                if condition in ('running', 'queued'):
                    newer.update(status='in_progress' if condition == 'running' else 'queued', conclusion=None)
                if condition == 'native-success':
                    jobs[0]['conclusion'] = 'success'
                if condition == 'unknown-job':
                    jobs[0]['name'] = 'Different job'
                if condition == 'missing-job':
                    jobs = jobs[1:]
                    total = 2
                if condition == 'incomplete-jobs':
                    total = 4
                if condition == 'unfinished-job':
                    jobs[0]['status'] = 'in_progress'
                if condition == 'rerun':
                    newer['run_attempt'] = 2
                def mocked(*args):
                    if args[:2] == ('run', 'list'):
                        return json.dumps([{'databaseId': 124}, {'databaseId': 123}])
                    if args[1].endswith('/124'):
                        return json.dumps(newer)
                    if '/124/attempts/' in args[1]:
                        return json.dumps({'total_count': total, 'jobs': jobs})
                    self.fail('An older successful run must not be queried past authoritative run 124')
                with patch.object(evidence, 'gh', side_effect=mocked):
                    with self.assertRaisesRegex(ValueError, 'latest PR Tests run'):
                        evidence.checked_run('owner/repo', self.sha, self.metadata)
                    output = io.StringIO()
                    with redirect_stdout(output):
                        evidence.main(['owner/repo', self.sha])
                    self.assertEqual(124, json.loads(output.getvalue())['id'])

    def test_skipped_native_verification_error_or_rerun_race_never_falls_back(self):
        for failure in ('jobs-unavailable', 'run-changed'):
            with self.subTest(failure=failure):
                queries = 0
                skipped = dict(id=124, status='completed', conclusion='success', event='pull_request',
                               head_sha=self.sha, run_attempt=1)
                def mocked(*args):
                    nonlocal queries
                    if args[:2] == ('run', 'list'):
                        return json.dumps([{'databaseId': 124}, {'databaseId': 123}])
                    if args[1].endswith('/124'):
                        queries += 1
                        return json.dumps(skipped if queries == 1 else dict(skipped, status='in_progress', run_attempt=2))
                    if '/124/attempts/' in args[1]:
                        if failure == 'jobs-unavailable':
                            raise evidence.subprocess.CalledProcessError(1, ['gh', 'api'])
                        return json.dumps({'total_count': 3, 'jobs': [
                            dict(name='Unit tests and app smoke', status='completed', conclusion='skipped'),
                            dict(name='Unit tests and app smoke (iPhone 18 Pro)', status='completed', conclusion='skipped'),
                            dict(name='Spotlight diagnostics (non-acceptance)', status='completed', conclusion='skipped')]})
                    self.fail('Verification failure must not select older run 123')
                with patch.object(evidence, 'gh', side_effect=mocked):
                    with self.assertRaises(evidence.subprocess.CalledProcessError if failure == 'jobs-unavailable' else ValueError):
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

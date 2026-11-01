import importlib.util
import unittest
from pathlib import Path

spec = importlib.util.spec_from_file_location('check_review_page', Path(__file__).parents[1] / 'check-review-page.py')
check = importlib.util.module_from_spec(spec)
spec.loader.exec_module(check)


def step(open_, label=''):
    return {'open': open_, 'label': label}


class EvaluateTests(unittest.TestCase):
    def test_a_working_viewer_passes(self):
        steps = [step(True, 'a · 1/54'), step(True, 'b · 2/54'), step(True, 'z · 54/54'), step(False, 'z · 54/54')]
        self.assertEqual([], check.evaluate({'shots': 54, 'steps': steps}))

    def test_plain_links_or_a_missing_viewer_fail(self):
        self.assertIn('no shots', check.evaluate({'shots': 0, 'steps': []})[0])
        steps = [step(False), step(False), step(False), step(False)]
        problems = check.evaluate({'shots': 3, 'steps': steps})
        self.assertIn('after a tap on the first shot the viewer is closed', problems)

    def test_arrows_that_do_not_step_fail(self):
        steps = [step(True, 'a · 1/3'), step(True, 'a · 1/3'), step(True, 'a · 1/3'), step(False)]
        problems = check.evaluate({'shots': 3, 'steps': steps})
        self.assertEqual(2, len(problems))
        self.assertIn('expected shot 2/3', problems[0])


class ProbePageTests(unittest.TestCase):
    def test_the_probe_runs_after_the_page_content(self):
        self.assertTrue(check.probe_page('<p>x</p>').endswith('</script>'))
        self.assertIn('</script></body>', check.probe_page('<body><p>x</p></body>'))


if __name__ == '__main__':
    unittest.main()

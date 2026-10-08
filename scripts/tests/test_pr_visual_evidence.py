import importlib.util
import json
import subprocess
import tempfile
import sys
import unittest
from pathlib import Path
from urllib.parse import parse_qs, urlparse
from unittest.mock import patch


sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import evidence_validation

SPEC = importlib.util.spec_from_file_location(
    "visual_evidence", Path(__file__).resolve().parents[1] / "pr-visual-evidence.py",
)
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class PublicationTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="whogavewhat-publication-test-")
        self.addCleanup(self.temporary.cleanup)
        self.directory = Path(self.temporary.name)
        self.metadata = dict(
            head_sha="a" * 40, run_id="123", run_attempt="2",
            journey_outcome="success", export_outcome="success", evidence_kind="app-smoke",
            device="iPhone-17-Pro", runtime="26-5", xcode="26.6",
        )
        self.image = self.directory / "checkpoint.png"
        self.video = self.directory / "demo.mp4"
        self.ffmpeg("-f", "lavfi", "-i", "testsrc=size=640x1280:rate=5", "-frames:v", "1", str(self.image))
        self.ffmpeg("-f", "lavfi", "-i", "testsrc=size=640x360:rate=5:duration=2", "-f", "lavfi", "-i",
                    "sine=frequency=1000:duration=2", "-map", "0:v:0", "-map", "1:a:0", "-c:v", "libx264",
                    "-pix_fmt", "yuv420p", "-c:a", "aac", "-shortest", "-movflags", "+faststart", str(self.video))
        self.pr = dict(
            state="open", head={"sha": "a" * 40}, body="Original description\n",
            html_url="https://github.com/owner/repo/pull/42",
        )
        self.run = dict(
            status="completed", conclusion="success", run_attempt=2, event="pull_request", head_sha="a" * 40,
            html_url="https://github.com/owner/repo/actions/runs/123",
        )
        self.edits = []
        self.uploads = []
        self.upload_paths = []

    def ffmpeg(self, *arguments):
        subprocess.run(["ffmpeg", "-nostdin", "-hide_banner", "-loglevel", "error", "-y", *arguments],
                       check=True, capture_output=True, text=True)

    def gh(self, *args):
        if args == ("api", "repos/{owner}/{repo}"):
            return json.dumps({"full_name": "owner/repo", "id": 1234})
        if args[:2] == ("run", "list"):
            return json.dumps([{"databaseId": 123}])
        if args == ("api", "repos/owner/repo/pulls/42"):
            return json.dumps(self.pr)
        if args == ("api", "repos/owner/repo/actions/runs/123"):
            return json.dumps(self.run)
        if args[:2] == ("api", "repos/owner/repo/pulls/42") and "PATCH" in args:
            return self.edit(args)
        if args[0] == "api" and args[1].startswith("https://uploads.github.com/"):
            return self.upload(args)
        self.fail(f"Unexpected gh call: {args}")

    def upload(self, args):
        self.uploads.append(args)
        query = parse_qs(urlparse(args[1]).query)
        self.assertEqual(query["repository_id"], ["1234"])
        self.assertIn(query["content_type"][0], ["image/png", "video/mp4"])
        upload_path = Path(args[args.index("--input") + 1])
        self.assertTrue(upload_path.is_file())
        self.upload_paths.append(upload_path)
        return json.dumps({"url": "https://github.com/user-attachments/assets/" + query["name"][0].replace(".", "-")})

    def edit(self, args):
        self.edits.append(args)
        self.pr["body"] = json.loads(Path(args[args.index("--input") + 1]).read_text())["body"]
        return json.dumps(self.pr)

    def publish(self, summary="Inspected the save and relaunch journey."):
        (self.directory / "metadata.json").write_text(json.dumps(self.metadata))
        with patch.object(MODULE, "gh", side_effect=self.gh), patch.object(evidence_validation, "gh", side_effect=self.gh):
            MODULE.publish(42, self.directory, summary, ["checkpoint.png"], ["demo.mp4"])

    def test_publication_embeds_media_and_preserves_other_sections_on_repeat(self):
        self.pr["body"] = f"Original\n\n{MODULE.START}\nOld evidence\n{MODULE.END}\n\nReviewer notes\n"
        self.publish()
        self.publish()
        body = self.pr["body"]
        self.assertTrue(body.startswith("Original\n\n"))
        self.assertTrue(body.endswith("\n\nReviewer notes\n"))
        self.assertEqual(body.count(MODULE.START), 1)
        self.assertNotIn("Old evidence", body)
        self.assertIn("a" * 40, body)
        self.assertIn(self.run["html_url"], body)
        self.assertIn("user-attachments/assets/checkpoint-png", body)
        self.assertIn("user-attachments/assets/demo-mp4", body)
        self.assertNotIn(self.temporary.name, body)

    def test_stale_head_or_attempt_never_uploads(self):
        for field, value in [("head_sha", "old-head"), ("run_attempt", "1"), ("run_id", "122")]:
            with self.subTest(field=field):
                original = self.metadata[field]
                self.metadata[field] = value
                with self.assertRaises(ValueError):
                    self.publish()
                self.metadata[field] = original
        self.assertEqual(self.edits, [])
        self.assertEqual(self.uploads, [])

    def test_failed_ci_or_export_never_uploads(self):
        self.run["conclusion"] = "failure"
        with self.assertRaises(ValueError):
            self.publish()
        self.run["conclusion"] = "success"
        self.metadata["export_outcome"] = "failure"
        with self.assertRaises(ValueError):
            self.publish()
        self.assertEqual(self.edits, [])
        self.assertEqual(self.uploads, [])

    def test_concurrent_body_edit_is_preserved(self):
        original = self.upload
        def changed(args):
            self.pr["body"] = "Danis added review notes"
            return original(args)

        self.upload = changed
        self.publish()
        self.assertTrue(self.pr["body"].startswith("Danis added review notes"))
        self.assertEqual(len(self.edits), 1)

    def test_partial_upload_failure_is_reported_without_retry(self):
        original = self.upload
        def partial(args):
            if self.uploads:
                raise subprocess.CalledProcessError(1, args)
            return original(args)

        self.upload = partial
        with self.assertRaises(subprocess.CalledProcessError):
            self.publish()
        self.assertEqual(len(self.uploads), 1)
        self.assertEqual(self.edits, [])
        self.assertEqual(self.pr["body"], "Original description\n")

    def test_missing_published_section_is_not_reported_as_success(self):
        def missing(args):
            self.pr["body"] = "Another writer replaced the evidence"
            return json.dumps(self.pr)

        self.edit = missing
        with self.assertRaisesRegex(ValueError, "evidence was changed"):
            self.publish()

    def test_push_during_upload_does_not_publish_stale_media(self):
        original = self.upload
        def pushed(args):
            self.pr["head"]["sha"] = "new-head"
            return original(args)

        self.upload = pushed
        with self.assertRaisesRegex(ValueError, "PR changed during upload"):
            self.publish()
        self.assertEqual(self.edits, [])

    def test_push_during_publication_invalidates_only_our_section(self):
        original = self.edit
        def pushed(args):
            result = original(args)
            if len(self.edits) == 1:
                self.pr["head"]["sha"] = "new-head"
                self.pr["body"] += "\nDanis added concurrent notes\n"
            return result

        self.edit = pushed
        with self.assertRaisesRegex(ValueError, "head changed"):
            self.publish()
        self.assertIn("Evidence is stale", self.pr["body"])
        self.assertNotIn("Reviewed commit", self.pr["body"])
        self.assertNotIn("user-attachments", self.pr["body"])
        self.assertIn("Danis added concurrent notes", self.pr["body"])
        self.assertEqual(len(self.edits), 2)

    def test_invalidation_does_not_remove_another_publishers_evidence(self):
        original = self.edit
        def replaced(args):
            result = original(args)
            self.pr["head"]["sha"] = "new-head"
            self.pr["body"] = f"{MODULE.START}\nEvidence from a newer publisher\n{MODULE.END}"
            return result

        self.edit = replaced
        with self.assertRaisesRegex(ValueError, "head changed"):
            self.publish()
        self.assertIn("Evidence from a newer publisher", self.pr["body"])
        self.assertEqual(len(self.edits), 1)

    def test_summary_markers_are_rejected_before_upload(self):
        for marker in [MODULE.START, MODULE.END]:
            with self.subTest(marker=marker), self.assertRaisesRegex(ValueError, "Summary"):
                self.publish("Copied section: " + marker)
        self.assertEqual(self.uploads, [])
        self.assertEqual(self.edits, [])

    def test_media_rejects_external_files_and_oversize_uploads(self):
        with tempfile.TemporaryDirectory(prefix="whogavewhat-external-") as other:
            external = Path(other) / "image.png"
            external.write_bytes(b"image")
            with self.assertRaises(ValueError):
                MODULE.media_file(self.directory, str(external), ".png")
        self.image.write_bytes(b"\x89PNG\r\n\x1a\nnot really a png")
        with self.assertRaisesRegex(ValueError, "Could not create compact evidence"):
            self.publish()
        self.assertEqual(self.edits, [])

    def test_compact_derivatives_preserve_bounds_ratio_timing_and_originals(self):
        original_image = self.image.read_bytes()
        original_video = self.video.read_bytes()
        with tempfile.TemporaryDirectory(prefix="compact-output-") as temporary:
            output = MODULE.compact_media(self.directory, ["checkpoint.png"], ["demo.mp4"], Path(temporary))
            self.assertEqual(len(output), 2)
            self.assertEqual(self.image.read_bytes(), original_image)
            self.assertEqual(self.video.read_bytes(), original_video)
            image_info = self.probe(output[0])
            video_info = self.probe(output[1])
            self.assertLessEqual(image_info["width"], 320)
            self.assertLessEqual(image_info["height"], 640)
            self.assertAlmostEqual(image_info["width"] / image_info["height"], 0.5, places=2)
            self.assertLessEqual(video_info["width"], 320)
            self.assertLessEqual(video_info["height"], 640)
            self.assertEqual(video_info["width"] % 2, 0)
            self.assertEqual(video_info["height"] % 2, 0)
            self.assertAlmostEqual(video_info["duration"], 2, delta=0.15)
            self.assertIn("audio", [stream["codec_type"] for stream in self.probe_streams(output[1])])
            subprocess.run(["ffmpeg", "-v", "error", "-i", str(output[0]), "-f", "null", "-"],
                           check=True, capture_output=True)
            subprocess.run(["ffmpeg", "-v", "error", "-i", str(output[1]), "-f", "null", "-"],
                           check=True, capture_output=True)

    def probe(self, path):
        result = subprocess.run(["ffprobe", "-v", "error", "-select_streams", "v:0", "-show_entries",
                                 "stream=width,height,codec_type:format=duration", "-of", "json", str(path)],
                                check=True, capture_output=True, text=True)
        details = json.loads(result.stdout)
        return {**details["streams"][0], "duration": float(details.get("format", {}).get("duration", 0))}

    def probe_streams(self, path):
        result = subprocess.run(["ffprobe", "-v", "error", "-show_entries", "stream=codec_type", "-of", "json",
                                 str(path)], check=True, capture_output=True, text=True)
        return json.loads(result.stdout)["streams"]

    def test_oversized_png_source_is_compacted_and_preserved(self):
        source = self.directory / "large.png"
        self.ffmpeg("-f", "lavfi", "-i", "nullsrc=s=4800x2400:d=1,noise=alls=100:allf=t+u",
                    "-frames:v", "1", str(source))
        self.assertGreater(source.stat().st_size, MODULE.MAX_BYTES)
        original_size = source.stat().st_size
        with tempfile.TemporaryDirectory(prefix="compact-output-") as temporary:
            output = MODULE.compact_media(self.directory, ["large.png"], [], Path(temporary))[0]
            self.assertLessEqual(output.stat().st_size, MODULE.MAX_BYTES)
            self.assertGreaterEqual(source.stat().st_size, original_size)
            info = self.probe(output)
            self.assertLessEqual(info["width"], 320)
            self.assertLessEqual(info["height"], 640)

    def test_missing_ffmpeg_fails_before_upload_and_derivatives_are_cleaned(self):
        (self.directory / "metadata.json").write_text(json.dumps(self.metadata))
        with patch.object(MODULE.shutil, "which", return_value=None), \
                patch.object(MODULE, "gh", side_effect=self.gh), \
                patch.object(evidence_validation, "gh", side_effect=self.gh), \
                self.assertRaisesRegex(ValueError, "ffmpeg is required"):
            MODULE.publish(42, self.directory, "Inspected evidence.", ["checkpoint.png"], ["demo.mp4"])
        self.assertEqual(self.uploads, [])
        self.assertEqual(self.edits, [])

        self.publish()
        self.assertEqual(len(self.upload_paths), 2)
        self.assertTrue(all(not path.exists() for path in self.upload_paths))

    def test_publisher_groups_two_images_per_paragraph_with_checkpoint_labels(self):
        self.ffmpeg("-f", "lavfi", "-i", "testsrc=size=320x640:rate=1", "-frames:v", "1",
                    str(self.directory / "people-list.png"))
        self.ffmpeg("-f", "lavfi", "-i", "testsrc=size=320x640:rate=1", "-frames:v", "1",
                    str(self.directory / "gift-details.png"))
        (self.directory / "metadata.json").write_text(json.dumps(self.metadata))
        with patch.object(MODULE, "gh", side_effect=self.gh), patch.object(evidence_validation, "gh", side_effect=self.gh):
            MODULE.publish(42, self.directory, "Inspected evidence.",
                           ["checkpoint.png", "people-list.png", "gift-details.png"], ["demo.mp4"])
        body = self.pr["body"]
        self.assertRegex(body, r"!\[Checkpoint\]\([^\n]+\) !\[People List\]\([^\n]+\)\n\n"
                              r"!\[Gift Details\]\([^\n]+\)\n\n")
        self.assertIn("user-attachments/assets/demo-mp4", body)

    def test_malformed_markers_do_not_destroy_body(self):
        for body in [MODULE.START, MODULE.END, MODULE.END + MODULE.START, MODULE.START * 2 + MODULE.END]:
            with self.subTest(body=body), self.assertRaises(ValueError):
                MODULE.section(body, "replacement")


if __name__ == "__main__":
    unittest.main()

import importlib.util
import json
import stat
import subprocess
import sys
import tempfile
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location("stage_trial_config", Path(__file__).parents[1] / "scripts/stage_trial_config.py")
stage = importlib.util.module_from_spec(spec)
spec.loader.exec_module(stage)


class TrialProfileTests(unittest.TestCase):
    def test_staged_resource_can_be_read_by_another_installing_user(self):
        with tempfile.TemporaryDirectory() as folder:
            source = Path(folder) / "private.json"
            destination = Path(folder) / "App/Contents/Resources/TrialConfiguration.json"
            source.write_text(json.dumps({"baseURL": "https://example.com/v1", "model": "example", "apiKey": "test-only-key"}))
            source.chmod(0o600)
            result = subprocess.run([sys.executable, str(Path(stage.__file__)), str(source), str(destination)], capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertNotIn("test-only-key", result.stdout + result.stderr)
            self.assertEqual(stat.S_IMODE(destination.stat().st_mode) & 0o444, 0o444)
            self.assertEqual(stat.S_IMODE(source.stat().st_mode), 0o600)

    def test_empty_profile_needs_no_credentials(self):
        self.assertEqual(stage.validate({}), {"baseURL": "", "model": ""})

    def test_profile_keeps_only_explicit_service_fields(self):
        value = {"baseURL": "https://example.com/v1", "model": "example-model", "apiKey": "test-only-key"}
        self.assertEqual(stage.validate(value), value)

    def test_author_files_cannot_enter_distribution(self):
        for field in ["authFile", "contextFile", "sourceEPUB", "bookTitle"]:
            with self.subTest(field=field), self.assertRaises(ValueError):
                stage.validate({field: "/private/example"})

    def test_gemini_trial_retains_explicit_thinking_level(self):
        value = {"baseURL": "https://api.302.ai/v1", "model": "gemini-3.5-flash-lite",
                 "apiKey": "test-only-key", "thinkingLevel": "minimal"}
        self.assertEqual(stage.validate(value), value)
        for level in ["", "unknown", None, 0]:
            with self.subTest(level=level), self.assertRaises(ValueError):
                stage.validate({**value, "thinkingLevel": level})

    def test_partial_or_unsafe_profile_rejected(self):
        for value in [[], {"model": "example"}, {"baseURL": 1},
                      {"baseURL": "http://example.com", "model": "example", "apiKey": "test-only-key"},
                      {"baseURL": "https://example.com?key=example", "model": "example", "apiKey": "test-only-key"}]:
            with self.subTest(value=value), self.assertRaises(ValueError):
                stage.validate(value)

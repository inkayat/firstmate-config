#!/usr/bin/env python3
"""Exercise the real CLI on disposable local clones; never target installed roots.

Catches duplicate/lost additions, pin/baseline/marker bypasses, partial preflight
writes, lost unrelated edits and damage to links or referenced companion files.
"""
import argparse
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

HERE = Path(__file__).resolve().parent
MANIFEST = json.loads((HERE / "source-manifest.json").read_text())
SOURCES = {}


class SourceAdditionTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix="fm-source-additions-")
        self.addCleanup(self.tmp.cleanup)
        self.base = Path(self.tmp.name)
        self.env = dict(os.environ, GIT_CONFIG_NOSYSTEM="1", GIT_CONFIG_GLOBAL=os.devnull,
                        GIT_TERMINAL_PROMPT="0", GIT_AUTHOR_NAME="Synthetic Fixture",
                        GIT_AUTHOR_EMAIL="fixture@example.invalid",
                        GIT_COMMITTER_NAME="Synthetic Fixture",
                        GIT_COMMITTER_EMAIL="fixture@example.invalid")
        self.roots = {}
        for name, source in SOURCES.items():
            dest = self.base / name
            self.command("git", "clone", "--quiet", "--shared", "--no-checkout", str(source), str(dest))
            revision = next(s["revision"] for s in MANIFEST["sources"] if s["root"] == name)
            self.command("git", "-C", str(dest), "checkout", "--quiet", "--detach", revision)
            self.roots[name] = dest
        self.original = self.snapshot()
        self.companions = {self.roots[c["root"]] / c["path"]: (self.roots[c["root"]] / c["path"]).read_bytes()
                           for c in MANIFEST["companions"]}

    def command(self, *args):
        result = subprocess.run(args, text=True, stdout=subprocess.PIPE,
                                stderr=subprocess.STDOUT, env=self.env)
        self.assertEqual(result.returncode, 0, result.stdout)
        return result.stdout

    def cli(self, action, ok=True, only=None):
        args = [sys.executable, str(HERE / "source_additions.py"), action]
        for name, dest in self.roots.items():
            args += [f"--{name}-root", str(dest)]
        if only:
            args += ["--only", *only]
        result = subprocess.run(args, text=True, stdout=subprocess.PIPE,
                                stderr=subprocess.STDOUT, env=self.env)
        if ok:
            self.assertEqual(result.returncode, 0, result.stdout)
        else:
            self.assertNotEqual(result.returncode, 0, result.stdout)
            self.assertIn("refused:", result.stdout)
        return result.stdout

    def snapshot(self):
        return {self.roots[s["root"]] / s["path"]: (self.roots[s["root"]] / s["path"]).read_bytes()
                for s in MANIFEST["sources"]}

    def target(self, index=0):
        source = MANIFEST["sources"][index]
        return self.roots[source["root"]] / source["path"]

    def test_apply_status_idempotent_revert_preserve_links_and_companions(self):
        link = self.base / "installed-skill"
        link.symlink_to(self.target(4).parent, target_is_directory=True)
        identity = os.readlink(link)
        self.cli("status")
        self.cli("apply")
        applied = self.snapshot()
        for path, before in self.original.items():
            self.assertTrue(applied[path].startswith(before))
            self.assertEqual(applied[path].count(b"<!-- BEGIN FM-LIVE-PROBE "), 1)
        self.assertEqual(self.cli("status").count("applied"), 7)
        self.cli("apply")
        self.assertEqual(self.snapshot(), applied)
        self.assertEqual(os.readlink(link), identity)
        self.assertEqual((link / "SKILL.md").read_bytes(), self.target(4).read_bytes())
        self.cli("revert")
        self.cli("revert")
        self.assertEqual(self.snapshot(), self.original)
        for path, body in self.companions.items():
            self.assertEqual(path.read_bytes(), body)

    def test_unexpected_baseline_preflights_every_target_before_writes(self):
        path = self.target(-1)
        path.write_bytes(path.read_bytes() + b"\nUnrelated local baseline edit.\n")
        before = self.snapshot()
        self.assertIn("baseline", self.cli("apply", ok=False))
        self.assertEqual(self.snapshot(), before)

    def test_wrong_source_revision_refuses_before_writes(self):
        self.command("git", "-C", str(self.roots["addy"]), "commit", "--quiet", "--allow-empty", "-m", "Wrong pin")
        self.assertIn("revision", self.cli("apply", ok=False))
        self.assertEqual(self.snapshot(), self.original)

    def test_partial_marker_refuses_without_writes(self):
        path = self.target(-1)
        path.write_bytes(path.read_bytes() + b"\n<!-- BEGIN FM-LIVE-PROBE documentation-and-adrs (temporary) -->\n")
        before = self.snapshot()
        self.assertIn("marker", self.cli("apply", ok=False))
        self.assertEqual(self.snapshot(), before)

    def test_altered_owned_body_refuses_revert_without_partial_removal(self):
        self.cli("apply")
        path = self.target(-1)
        path.write_bytes(path.read_bytes().replace(b"## Temporary live-observation rule", b"## Altered live-observation rule"))
        before = self.snapshot()
        self.assertIn("marker", self.cli("revert", ok=False))
        self.assertEqual(self.snapshot(), before)

    def test_duplicate_owned_block_refuses(self):
        self.cli("apply")
        path = self.target(0)
        addition = path.read_bytes()[len(self.original[path]):]
        path.write_bytes(path.read_bytes() + addition)
        before = self.snapshot()
        self.assertIn("marker", self.cli("apply", ok=False))
        self.assertEqual(self.snapshot(), before)

    def test_revert_removes_only_owned_additions_preserving_later_edits(self):
        self.cli("apply")
        path = self.target(0)
        path.write_bytes(b"Unrelated prefix.\n" + path.read_bytes() + b"Unrelated suffix.\n")
        companion = next(iter(self.companions))
        companion.write_bytes(companion.read_bytes() + b"\nLocal companion change.\n")
        self.cli("revert")
        self.assertEqual(path.read_bytes(), b"Unrelated prefix.\n" + self.original[path] + b"Unrelated suffix.\n")
        self.assertEqual(companion.read_bytes(), self.companions[companion] + b"\nLocal companion change.\n")
        self.cli("revert")

    def test_changed_companion_preflights_before_writes(self):
        companion = next(iter(self.companions))
        companion.write_bytes(b"Changed companion\n")
        self.assertIn("companion", self.cli("apply", ok=False))
        self.assertEqual(self.snapshot(), self.original)

    def test_config_only_selection_does_not_touch_external_sources(self):
        self.cli("apply", only=["config"])
        applied = self.snapshot()
        for source in MANIFEST["sources"]:
            path = self.roots[source["root"]] / source["path"]
            if source["root"] == "config":
                self.assertNotEqual(applied[path], self.original[path])
            else:
                self.assertEqual(applied[path], self.original[path])
        self.cli("revert", only=["config"])
        self.assertEqual(self.snapshot(), self.original)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("config", "superpowers", "addy"):
        parser.add_argument(f"--{name}-source", type=Path, required=True)
    options, rest = parser.parse_known_args()
    SOURCES = {name: getattr(options, f"{name}_source").resolve() for name in ("config", "superpowers", "addy")}
    unittest.main(argv=[sys.argv[0], *rest])

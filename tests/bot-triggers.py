#!/usr/bin/env python3
"""Hermetic CLI acceptance for interval/remote admission and durable skips.

No models, live home, check registration, backend, or lifecycle control. Git
commits below belong only to fresh disposable repositories. All expectations
are literal consumer outcomes, not a copy of the scheduling implementation.
"""
import concurrent.futures
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
BOT = ROOT / "bin/fm-bot"
FMROOT = Path(os.environ.get("FIRSTMATE_ROOT", Path.home() / "Developer/tools/firstmate"))
GIT = shutil.which("git")
PYTHON = sys.executable


class Triggers(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix="fm-bot-triggers-")
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name).resolve()
        self.home = self.root / "home"
        self.fm = self.root / "fm"
        self.bin = self.root / "bin"
        for path in (self.home, self.fm / "data", self.fm / "state", self.bin, self.root / "tmp"):
            path.mkdir(parents=True, exist_ok=True)
        # Only native, non-model tools. Never inherit operator Git credentials,
        # backend namespaces, FirstMate overrides, or a shell startup file.
        for name in ("git", "bash", "perl", "tasks-axi", "node"):
            tool = shutil.which(name)
            if tool:
                (self.bin / name).symlink_to(Path(tool).resolve())
        self.env = {
            "HOME": str(self.home), "FM_HOME": str(self.fm),
            "FIRSTMATE_ROOT": str(FMROOT), "FM_TEST_SKIP_ORPHAN_REAP": "1",
            "FM_BOT_TEST_CLOCK": "1", "TMPDIR": str(self.root / "tmp"),
            "FM_TEST_TMPDIR": str(self.root / "tmp"),
            "PATH": f"{self.bin}:/usr/bin:/bin", "LC_ALL": "C", "TZ": "UTC",
            "GIT_CONFIG_NOSYSTEM": "1", "GIT_CONFIG_GLOBAL": "/dev/null",
            "GIT_TERMINAL_PROMPT": "0", "GIT_ALLOW_PROTOCOL": "file",
        }
        (self.fm / "data/projects.md").write_text("# Projects\n- sandbox [local-only] - disposable fixture\n")
        self.base = ["--role", "senior-fullstack", "--project", "sandbox", "--route", "EXPLORE #2",
                     "--scope", "Review selected project; report only", "--wall-clock-min", "60",
                     "--now", "2026-10-24T22:00:00Z"]

    def command(self, argv, *, ok=True, env=None):
        result = subprocess.run([str(a) for a in argv], env=env or self.env, cwd=self.root,
                                capture_output=True, text=True, timeout=20)
        if ok:
            self.assertEqual(result.returncode, 0, f"{argv}\n{result.stdout}\n{result.stderr}")
        return result

    def bot(self, *args, **kwargs):
        return self.command([PYTHON, "-B", BOT, *args], **kwargs)

    def create(self, *args):
        return self.bot("create", "scan", *self.base, *args)

    def verdict(self, now):
        return json.loads(self.bot("due", "--json", "--now", now).stdout)[0]

    def git(self, *args):
        return self.command([GIT, *args]).stdout.strip()

    def remote(self):
        self.project = self.fm / "projects/sandbox"
        self.project.mkdir(parents=True)
        self.origin = self.root / "origin.git"
        self.git("init", "--bare", self.origin)
        self.git("init", "-b", "selected", self.project)
        self.git("-C", self.project, "config", "user.name", "Fixture")
        self.git("-C", self.project, "config", "user.email", "fixture@example.invalid")
        self.git("-C", self.project, "remote", "add", "origin", self.origin)
        self.a = self.commit("a")
        self.git("-C", self.project, "push", "origin", "HEAD:refs/heads/selected")
        # Deliberately unrelated default branch: observing HEAD is a bug.
        self.git("--git-dir", self.origin, "symbolic-ref", "HEAD", "refs/heads/unrelated")
        self.create("--on-remote", "origin", "--on-branch", "selected")

    def commit(self, text):
        (self.project / "fixture.txt").write_text(text)
        self.git("-C", self.project, "add", "fixture.txt")
        self.git("-C", self.project, "commit", "-m", f"fixture {text}")
        return self.git("-C", self.project, "rev-parse", "HEAD")

    def publish(self, text):
        oid = self.commit(text)
        self.git("-C", self.project, "push", "origin", "HEAD:refs/heads/selected")
        return oid

    def file(self, ident, now, **kwargs):
        return self.bot("file", ident, "--json", "--now", now, **kwargs)

    def owned(self, ident, state="busy"):
        worktree = self.root / "worker" / ident
        worktree.mkdir(parents=True, exist_ok=True)
        gen = self.command([FMROOT / "bin/fm-busy-event.sh", "arm", self.fm / "state", ident]).stdout.strip()
        (self.fm / "state" / f"{ident}.meta").write_text(
            f"endpoint_task_id={ident}\nproject={self.fm / 'projects/sandbox'}\n"
            f"worktree={worktree}\nkind=scout\nharness=omp\nspawn_gen=s-fixture-{gen}\nbusy_gen={gen}\n")
        self.busy(ident, state, gen)
        return gen

    def busy(self, ident, state, gen):
        self.command([FMROOT / "bin/fm-busy-event.sh", "apply", self.fm / "state", ident,
                      state, "--gen", gen, "--source", "omp-ext", "--event", "agent_end" if state == "idle" else "agent_start"])

    def done(self, ident):
        self.command([FMROOT / "bin/fm-tasks-axi.sh", "done", ident])

    def native_records(self, ident, step):
        """Exercise teardown's safe record tail, never its backend/pool work.

        Metadata publication is a fixture. Dispatch, close/retain, busy/status
        retirement and crash-marker replay use their actual native owners.
        """
        if step == "dispatch":
            (self.fm / "state" / f"{ident}.status").write_text("working: disposable record fixture\n")
        else:
            report = self.fm / "data" / ident / "report.md"
            report.parent.mkdir(parents=True, exist_ok=True)
            report.write_text("Disposable record-transition fixture; no worker was launched.\n")
        self.command(["bash", "-c", r'''
set -eu
bin=$1; id=$2; step=$3
. "$bin/fm-tasks-axi-lib.sh"
. "$bin/fm-backlog-transition-lib.sh"
. "$bin/fm-backend.sh"
. "$bin/fm-wake-lib.sh"
. "$bin/fm-classify-lib.sh"
state=$FM_HOME/state; data=$FM_HOME/data; meta=$state/$id.meta
lock=$(fm_meta_lock_path "$meta")
fm_lock_acquire_wait "$lock"
trap 'fm_lock_release "$lock" >/dev/null 2>&1 || true' EXIT
if [ "$step" = dispatch ]; then
  fm_backlog_atomic_transition dispatch "$meta" "$data" "$id" "$state"
elif [ "$step" = replay ]; then
  fm_backlog_close_marker_replay "$state" "$state/$id.backlog-close" "$data"
else
  mode=close; flags=()
  if "$bin/fm-captain-hold.sh" open "$id"; then
    mode=retain; flags=(--retain)
  else
    rc=$?; [ "$rc" -eq 1 ] || exit "$rc"
  fi
  spawn=$(fm_meta_get "$meta" spawn_gen)
  gen=$(fm_meta_get "$meta" busy_gen)
  fm_backlog_close_marker_write "$state" "$id" "$data" "$spawn" \
    "${flags[@]+"${flags[@]}"}" --report "data/$id/report.md"
  [ "$step" != stage ] || exit 0
  "$bin/fm-busy-event.sh" retire "$state" "$id" --gen "$gen"
  status_retire_presentation_task "$state" "$id"
  if [ "$step" = remove-before-done ]; then
    fm_backlog_atomic_transition remove "$meta" "task record" "$state"
  else
    fm_backlog_atomic_transition "$mode" "$meta" "$state/$id.backlog-close" \
      "$data" "$id" "$state" --report "data/$id/report.md"
  fi
fi
''', "native-record-fixture", FMROOT / "bin", ident, step])

    def prune_completion(self, ident):
        self.command([FMROOT / "bin/fm-tasks-axi.sh", "add", "other-finished", "Other fixture completion"])
        self.done("other-finished")
        self.command([FMROOT / "bin/fm-tasks-axi.sh", "prune", "--keep", "1"])
        missing = self.command([FMROOT / "bin/fm-tasks-axi.sh", "show", ident, "--full"], ok=False)
        self.assertNotEqual(missing.returncode, 0)
        self.assertIn("code: NOT_FOUND", missing.stdout)

    def test_native_close_allows_next_interval_after_cleanup(self):
        # Catches requiring live metadata/idle records that native close removes.
        self.create("--every-hours", "3")
        first = "scan-i20261025T010000Z"
        self.file(first, "2026-10-25T01:00Z")
        self.owned(first)
        self.native_records(first, "dispatch")
        self.native_records(first, "close")
        for suffix in (".meta", ".busy-gen", ".busy-state", ".status", ".backlog-close"):
            self.assertFalse((self.fm / "state" / f"{first}{suffix}").exists())
        row = self.command([FMROOT / "bin/fm-tasks-axi.sh", "show", first, "--full"]).stdout
        self.assertIn("state: done", row)
        self.assertEqual(self.verdict("2026-10-25T01:05Z")["verdict"], "filed")
        self.assertEqual(self.verdict("2026-10-25T04:00Z")["verdict"], "due")
        plan = json.loads(self.file("scan-i20261025T040000Z", "2026-10-25T04:00Z").stdout)
        self.assertEqual(plan["id"], "scan-i20261025T040000Z")
        self.assertEqual(self.verdict("2026-10-25T04:01Z")["verdict"], "filed")

    def test_native_remote_cleanup_preserves_skip_and_files_only_new_tip_once(self):
        # Catches cleanup permanently disabling events, replaying skips, or duplicates.
        self.remote()
        self.verdict("2026-10-24T22:00Z")
        self.publish("b")
        first = self.verdict("2026-10-24T22:01Z")["id"]
        self.file(first, "2026-10-24T22:01Z")
        self.owned(first)
        self.native_records(first, "dispatch")
        c = self.publish("c")
        skipped = self.verdict("2026-10-24T22:02Z")
        self.assertEqual((skipped["verdict"], skipped["trigger"]["observed_oid"]), ("skipped", c))
        self.native_records(first, "close")
        self.assertEqual(self.verdict("2026-10-24T22:03Z")["verdict"], "skipped")
        self.assertEqual(self.verdict("2026-10-25T00:04Z")["verdict"], "skipped")
        self.assertNotEqual(self.file(skipped["id"], "2026-10-25T00:04Z", ok=False).returncode, 0)
        d = self.publish("d")
        latest = self.verdict("2026-10-25T00:05Z")
        self.assertEqual((latest["verdict"], latest["trigger"]["observed_oid"]), ("due", d))
        with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
            results = list(pool.map(lambda _: self.file(latest["id"], "2026-10-25T00:05Z"), range(2)))
        plans = [json.loads(r.stdout) for r in results if r.stdout.startswith("{")]
        self.assertEqual(len(plans), 1)
        self.assertEqual((plans[0]["trigger"]["branch"], plans[0]["artifact"]["commit"]), ("selected", d))
        self.assertEqual(self.git("--git-dir", plans[0]["artifact"]["git_dir"], "show", f"{d}:fixture.txt"), "d")
        self.assertEqual(self.verdict("2026-10-25T00:06Z")["verdict"], "filed")

    def test_observed_native_completion_survives_prune_and_restart(self):
        # Catches discarding a positive finish when native retention archives its row.
        self.create("--every-hours", "3")
        first = "scan-i20261025T010000Z"
        self.file(first, "2026-10-25T01:00Z")
        self.owned(first)
        self.native_records(first, "dispatch")
        self.native_records(first, "close")
        self.verdict("2026-10-25T01:05Z")
        self.prune_completion(first)
        self.assertEqual(self.verdict("2026-10-25T04:00Z")["verdict"], "due")
        self.assertEqual(json.loads(self.file("scan-i20261025T040000Z", "2026-10-25T04:00Z").stdout)["id"],
                         "scan-i20261025T040000Z")

    def test_unobserved_pruned_completion_remains_unknown(self):
        # Catches treating missing backlog/meta as completion without a positive receipt.
        self.create("--every-hours", "3")
        first = "scan-i20261025T010000Z"
        self.file(first, "2026-10-25T01:00Z")
        self.owned(first)
        self.native_records(first, "dispatch")
        self.native_records(first, "close")
        self.prune_completion(first)
        row = self.verdict("2026-10-25T04:00Z")
        self.assertEqual((row["verdict"], row["reason"]), ("skipped", "previous-unknown"))
        self.assertNotEqual(self.file("scan-i20261025T040000Z", "2026-10-25T04:00Z", ok=False).returncode, 0)

    def test_native_late_close_replay_allows_later_interval(self):
        # Catches restart losing the real pending-close completion transition.
        self.create("--every-hours", "3")
        first = "scan-i20261025T010000Z"
        self.file(first, "2026-10-25T01:00Z")
        self.owned(first)
        self.native_records(first, "dispatch")
        self.native_records(first, "remove-before-done")
        self.assertEqual(self.verdict("2026-10-25T01:05Z")["verdict"], "filed")
        self.native_records(first, "replay")
        self.verdict("2026-10-25T01:10Z")
        self.assertEqual(self.verdict("2026-10-25T04:00Z")["verdict"], "due")
        self.file("scan-i20261025T040000Z", "2026-10-25T04:00Z")

    def test_native_early_close_replay_with_busy_evidence_still_skips(self):
        # Catches trusting a replayed done row while unfinished ownership survives.
        self.create("--every-hours", "3")
        first = "scan-i20261025T010000Z"
        self.file(first, "2026-10-25T01:00Z")
        self.owned(first)
        self.native_records(first, "dispatch")
        self.native_records(first, "stage")
        self.native_records(first, "replay")
        row = self.verdict("2026-10-25T04:00Z")
        self.assertEqual((row["verdict"], row["reason"]), ("skipped", "previous-unknown"))
        self.assertNotEqual(self.file("scan-i20261025T040000Z", "2026-10-25T04:00Z", ok=False).returncode, 0)

    def test_native_captain_retention_is_not_completion(self):
        # Catches metadata cleanup admitting another job while the native hold survives.
        self.create("--every-hours", "3")
        first = "scan-i20261025T010000Z"
        self.file(first, "2026-10-25T01:00Z")
        self.owned(first)
        self.native_records(first, "dispatch")
        self.command([FMROOT / "bin/fm-captain-hold.sh", "hold", first, "--reason", "unfinished fixture"])
        self.native_records(first, "close")
        row = self.verdict("2026-10-25T04:00Z")
        self.assertEqual((row["verdict"], row["reason"]), ("skipped", "previous-unfinished"))
        self.assertNotEqual(self.file("scan-i20261025T040000Z", "2026-10-25T04:00Z", ok=False).returncode, 0)

    def test_new_incarnation_cannot_inherit_retired_completion_clock(self):
        # Catches an idle replacement inheriting a pre-cleanup finish timestamp.
        self.create("--every-hours", "3")
        first = "scan-i20261025T010000Z"
        self.file(first, "2026-10-25T01:00Z")
        self.owned(first)
        self.native_records(first, "dispatch")
        self.native_records(first, "close")
        self.verdict("2026-10-25T01:05Z")
        self.owned(first, "idle")
        self.verdict("2026-10-25T03:59Z")
        self.assertEqual(self.verdict("2026-10-25T04:00Z")["verdict"], "skipped")
        self.assertEqual(self.verdict("2026-10-25T07:00Z")["verdict"], "due")

    def test_untrusted_pending_close_prevents_reusing_completion(self):
        # Catches inferring safe retirement while a pending-close object is unsafe.
        self.create("--every-hours", "3")
        first = "scan-i20261025T010000Z"
        self.file(first, "2026-10-25T01:00Z")
        self.owned(first)
        self.native_records(first, "dispatch")
        self.native_records(first, "close")
        self.verdict("2026-10-25T01:05Z")
        unrelated = self.root / "unrelated"
        unrelated.write_text("not a native completion receipt\n")
        (self.fm / "state" / f"{first}.backlog-close").symlink_to(unrelated)
        row = self.verdict("2026-10-25T04:00Z")
        self.assertEqual((row["verdict"], row["reason"]), ("skipped", "previous-unknown"))
        self.assertEqual(unrelated.read_text(), "not a native completion receipt\n")

    def test_interval_elapsed_anchor_lateness_and_restart(self):
        # Catches wall-clock/DST slots, immediate first-run, or catch-up queues.
        self.create("--every-hours", "3")
        r = self.verdict("2026-10-25T00:59:59Z")
        self.assertEqual((r["verdict"], r["next"]), ("not-yet", "2026-10-25T01:00:00Z"))
        r = self.verdict("2026-10-25T01:00:00Z")
        self.assertEqual((r["id"], r["verdict"]), ("scan-i20261025T010000Z", "due"))
        self.assertEqual(r["next"], "2026-10-25T04:00:00Z")
        late = self.verdict("2026-10-26T12:59:59Z")
        self.assertEqual(late["id"], "scan-i20261026T100000Z")
        self.assertEqual(late["next"], "2026-10-26T13:00:00Z")
        self.assertEqual(self.verdict("2026-10-26T12:59:59Z"), late)
        shown = json.loads(self.bot("show", "scan", "--json", "--now", "2026-10-25T01:00Z").stdout)
        self.assertEqual(shown["next"], "2026-10-25T04:00:00Z")

    def test_spring_dst_pause_resume_and_backward_clock(self):
        # Catches Stockholm arithmetic replacing elapsed UTC hours, or resume reset.
        self.create("--every-hours", "3", "--now", "2027-03-27T23:00:00Z")
        self.assertEqual(self.verdict("2027-03-28T01:59:59Z")["verdict"], "not-yet")
        self.assertEqual(self.verdict("2027-03-28T02:00:00Z")["id"], "scan-i20270328T020000Z")
        self.bot("pause", "scan")
        self.assertEqual(self.verdict("2027-03-28T05:00:00Z")["verdict"], "paused")
        self.bot("resume", "scan")
        self.assertEqual(self.verdict("2027-03-28T05:00:00Z")["id"], "scan-i20270328T050000Z")
        self.assertEqual(self.verdict("2027-03-27T22:00:00Z")["verdict"], "not-yet")

    def test_refuses_unsafe_or_compound_schedules(self):
        # Catches bypasses of the two-hour minimum and one-hour requested limit.
        cases = [(["--every-hours", "1"], "bad-every-hours"),
                 (["--every-hours", "2.5"], "bad-every-hours"),
                 (["--every-hours", "2", "--wall-clock-min", "61"], "bad-wall-clock-min"),
                 (["--every-hours", "3", "--at", "09:00", "--until", "09:30"], "compound-schedule"),
                 (["--every-hours", "3", "--on-remote", "origin", "--on-branch", "selected"], "compound-schedule"),
                 (["--on-remote", "https://example.invalid", "--on-branch", "main"], "bad-on-remote"),
                 (["--on-remote", "origin", "--on-branch", "main;touch x"], "bad-on-branch"),
                 (["--on-remote", "origin", "--on-branch", "main*"], "bad-on-branch")]
        for args, code in cases:
            with self.subTest(args=args):
                r = self.bot("create", "scan", *self.base, *args, ok=False)
                self.assertNotEqual(r.returncode, 0)
                self.assertIn(f"({code})", r.stderr)
                self.assertFalse((self.fm / "data/bots/scan.md").exists())

    def test_remote_baseline_change_coalescing_and_restart(self):
        # Catches old-history runs, duplicate notifications, stale pending tips,
        # default-branch substitution, and observer mutation of primary refs.
        self.remote()
        before = self.git("-C", self.project, "show-ref")
        first = self.verdict("2026-10-24T22:00:00Z")
        self.assertEqual(first["verdict"], "baseline")
        self.assertEqual(first["trigger"]["observed_oid"], self.a)
        self.assertEqual(self.verdict("2026-10-24T22:01:00Z")["verdict"], "unchanged")
        b = self.publish("b")
        pending = self.verdict("2026-10-24T22:02:00Z")
        self.assertEqual((pending["id"], pending["verdict"]), ("scan-r000000000001", "due"))
        self.assertEqual(pending["trigger"]["observed_oid"], b)
        self.assertEqual(pending["trigger"]["branch"], "selected")
        self.assertEqual(pending["trigger"]["remote"], "origin")
        self.assertEqual(self.verdict("2026-10-24T22:03:00Z")["id"], pending["id"])
        c = self.publish("c")
        expected_refs = self.git("-C", self.project, "show-ref")
        latest = self.verdict("2026-10-24T22:04:00Z")
        self.assertEqual(latest["id"], "scan-r000000000002")
        self.assertEqual(latest["trigger"]["observed_oid"], c)
        self.assertEqual(latest["trigger"]["baseline_oid"], self.a)
        self.assertEqual(self.git("-C", self.project, "show-ref"), expected_refs)
        self.assertIn(self.a, before)
        self.assertEqual(self.git("-C", self.project, "rev-parse", "refs/remotes/origin/selected"), c)
        self.assertFalse((self.fm / "data/backlog.md").exists())

    def test_remote_errors_preserve_pending_and_binding(self):
        # Catches deletion/failure being mistaken for a successful observation,
        # and an edited remote silently retargeting an existing spec.
        self.remote()
        self.verdict("2026-10-24T22:00Z")
        b = self.publish("b")
        self.verdict("2026-10-24T22:01Z")
        marker = self.fm / "data/bots/.observed/scan.json"
        saved = marker.read_bytes()
        self.git("--git-dir", self.origin, "update-ref", "-d", "refs/heads/selected")
        self.assertEqual(self.verdict("2026-10-24T22:02Z")["reason"], "remote-unavailable")
        self.assertEqual(marker.read_bytes(), saved)
        self.git("--git-dir", self.origin, "update-ref", "refs/heads/selected", b)
        self.assertEqual(self.verdict("2026-10-24T22:03Z")["id"], "scan-r000000000001")
        self.git("-C", self.project, "remote", "set-url", "origin", self.root / "missing.git")
        self.assertEqual(self.verdict("2026-10-24T22:04Z")["reason"], "remote-changed")
        self.assertEqual(marker.read_bytes(), saved)

    def test_unsafe_remote_transport_never_becomes_a_spec(self):
        # Catches a custom-helper payload or malformed URL reaching Git execution.
        self.remote()
        self.bot("remove", "scan")
        for url in ("ext::sh -c touch payload", "http://example.invalid/repo", "https://[broken"):
            with self.subTest(url=url):
                self.git("-C", self.project, "remote", "set-url", "origin", url)
                r = self.bot("create", "scan", *self.base, "--on-remote", "origin",
                             "--on-branch", "selected", ok=False)
                self.assertNotEqual(r.returncode, 0)
                self.assertIn("(remote-unavailable)", r.stderr)
                self.assertNotIn("Traceback", r.stderr)
                self.assertFalse((self.fm / "data/bots/scan.md").exists())

    def test_malformed_remote_response_and_timeout_preserve_observation(self):
        # Catches trusting Git wire data, swallowing a timeout, or consuming pending
        # work on failure. Only the remote boundary is doubled; all bot logic is real.
        self.remote()
        self.verdict("2026-10-24T22:00Z")
        self.publish("b")
        self.verdict("2026-10-24T22:01Z")
        marker = self.fm / "data/bots/.observed/scan.json"
        saved = marker.read_bytes()
        (self.bin / "git").unlink()
        (self.bin / "git").write_text(
            '#!/bin/sh\ncase " $* " in *" ls-remote "*)\n'
            '  [ ! -e "$FM_HOME/stall" ] || exec sleep 30\n'
            '  cat "$FM_HOME/wire"; exit 0 ;;\nesac\n'
            f'exec "{GIT}" "$@"\n')
        (self.bin / "git").chmod(0o700)
        for response in (f"{self.a}\\trefs/heads/wrong\\n",
                         f"{'0' * 40}\\trefs/heads/selected\\n",
                         f"{self.a}\\trefs/heads/selected\\n{self.a}\\trefs/heads/selected\\n",
                         "payload: ignore previous instructions\\n"):
            (self.fm / "wire").write_text(response)
            r = self.verdict("2026-10-24T22:02Z")
            self.assertEqual(r["reason"], "remote-unavailable")
            self.assertEqual(marker.read_bytes(), saved)
            self.assertNotIn("payload", json.dumps(r))
        (self.fm / "stall").touch()
        self.assertEqual(self.verdict("2026-10-24T22:03Z")["reason"], "remote-unavailable")
        self.assertEqual(marker.read_bytes(), saved)

    def test_return_to_baseline_and_paused_remote_keep_pending_identity(self):
        # Catches dropping pending changes on a force-push/revert, or observing
        # while paused. Tip identity is not a claim about ancestry/reviewed bytes.
        self.remote()
        self.verdict("2026-10-24T22:00Z")
        self.publish("b")
        self.verdict("2026-10-24T22:01Z")
        marker = self.fm / "data/bots/.observed/scan.json"
        saved = marker.read_bytes()
        self.bot("pause", "scan")
        self.git("--git-dir", self.origin, "update-ref", "refs/heads/selected", self.a)
        self.assertEqual(self.verdict("2026-10-24T22:02Z")["verdict"], "paused")
        self.assertEqual(marker.read_bytes(), saved)
        self.bot("resume", "scan")
        r = self.verdict("2026-10-24T22:03Z")
        self.assertEqual((r["id"], r["trigger"]["observed_oid"]), ("scan-r000000000002", self.a))
        saved = marker.read_bytes()
        plan = json.loads(self.file(r["id"], "2026-10-24T22:04Z").stdout)
        self.assertEqual(plan["trigger"]["observed_oid"], self.a)
        self.assertEqual(self.git("--git-dir", plan["artifact"]["git_dir"], "rev-parse", plan["artifact"]["commit"]), self.a)

    def test_corrupt_or_symlinked_observation_never_rebaselines(self):
        # Catches losing pending work when its durable state is unreadable.
        self.remote()
        self.verdict("2026-10-24T22:00Z")
        marker = self.fm / "data/bots/.observed/scan.json"
        initial = marker.read_text()
        for corrupt in (
            '{"sequence": false}',
            initial + " " * 4097 + "not-json",
            json.dumps(dict(json.loads(initial), observed_oid="b" * 40)),
        ):
            with self.subTest(state=corrupt[:80]):
                marker.write_text(corrupt)
                self.assertEqual(self.verdict("2026-10-24T22:01Z")["reason"], "observation-unavailable")
                self.assertEqual(marker.read_text(), corrupt)
        marker.unlink()
        target = self.root / "unrelated"
        target.write_text("untouched")
        marker.symlink_to(target)
        self.assertEqual(self.verdict("2026-10-24T22:02Z")["reason"], "observation-unavailable")
        self.assertEqual(target.read_text(), "untouched")

    def test_concurrent_observation_and_dry_query(self):
        # Catches check races incrementing the event id twice, or --now consuming it.
        self.remote()
        self.verdict("2026-10-24T22:00Z")
        self.publish("b")
        marker = self.fm / "data/bots/.observed/scan.json"
        saved = marker.read_bytes()
        dry = {k: v for k, v in self.env.items() if k != "FM_BOT_TEST_CLOCK"}
        r = self.bot("due", "--json", "--now", "2026-10-24T22:01Z", env=dry)
        self.assertEqual(json.loads(r.stdout)[0]["id"], "scan-r000000000001")
        self.assertEqual(marker.read_bytes(), saved)
        with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
            rows = list(pool.map(self.verdict, ["2026-10-24T22:02Z"] * 2))
        self.assertEqual([r["id"] for r in rows], ["scan-r000000000001"] * 2)
        self.assertEqual(self.verdict("2026-10-24T22:03Z")["id"], "scan-r000000000001")

    def test_eligible_interval_file_concurrency_and_no_duplicate(self):
        self.create("--every-hours", "3")
        ident = "scan-i20261025T010000Z"
        with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
            results = list(pool.map(lambda _: self.file(ident, "2026-10-25T01:00Z"), range(2)))
        plans = [json.loads(r.stdout) for r in results if r.stdout.startswith("{")]
        self.assertEqual([p["id"] for p in plans], [ident])
        self.assertEqual((plans[0]["kind"], plans[0]["delivery"], plans[0]["duration_enforced"]),
                         ("scout", "report", False))
        self.assertEqual(self.verdict("2026-10-25T01:01Z")["verdict"], "filed")
        self.assertIn("already-filed:", self.file(ident, "2026-10-25T01:02Z").stdout)
        self.assertNotEqual(self.file("scan-20261025", "2026-10-25T01:03Z", ok=False).returncode, 0)
        self.assertNotEqual(self.file("scan-i20261024T220000Z", "2026-10-25T01:03Z", ok=False).returncode, 0)

    def test_queued_skip_survives_completion_and_restart_without_losing_owner(self):
        self.create("--every-hours", "3")
        first, second = "scan-i20261025T010000Z", "scan-i20261025T040000Z"
        self.file(first, "2026-10-25T01:00Z")
        self.assertEqual(self.verdict("2026-10-25T04:00Z")["verdict"], "skipped")
        gen = self.owned(first, "idle")
        self.done(first)
        # Separate CLI processes are restarts, not shared in-memory guards.
        self.assertEqual(self.verdict("2026-10-25T04:10Z")["verdict"], "skipped")
        self.assertNotEqual(self.file(second, "2026-10-25T06:30Z", ok=False).returncode, 0)
        self.assertEqual(self.verdict("2026-10-25T07:00Z")["verdict"], "due")
        self.busy(first, "busy", gen)
        # Recheck at filing: an earlier due line is not admission permission.
        third = "scan-i20261025T070000Z"
        self.assertNotEqual(self.file(third, "2026-10-25T07:00Z", ok=False).returncode, 0)
        self.assertEqual(self.verdict("2026-10-25T07:01Z")["verdict"], "skipped")

    def test_done_requires_owned_idle_not_busy_unknown_or_held(self):
        for condition in ("busy", "unknown", "missing-meta", "held", "wrong-task", "wrong-gen"):
            with self.subTest(condition=condition):
                # Each case has its own bot/last-owned-job continuity.
                name = f"scan-{condition}"
                self.bot("create", name, *self.base, "--every-hours", "3")
                ident = f"{name}-i20261025T010000Z"
                self.file(ident, "2026-10-25T01:00Z")
                gen = self.owned(ident, "idle" if condition not in ("busy", "unknown") else condition)
                if condition != "held":
                    self.done(ident)
                meta = self.fm / "state" / f"{ident}.meta"
                if condition == "missing-meta":
                    meta.unlink()
                elif condition == "held":
                    self.command([FMROOT / "bin/fm-captain-hold.sh", "hold", ident, "--reason", "unfinished fixture"])
                elif condition == "wrong-task":
                    meta.write_text(meta.read_text().replace(f"endpoint_task_id={ident}", "endpoint_task_id=unrelated"))
                elif condition == "wrong-gen":
                    (self.fm / "state" / f"{ident}.busy-gen").write_text("different-generation\n")
                rows = json.loads(self.bot("due", "--json", "--now", "2026-10-25T04:00Z").stdout)
                row = next(r for r in rows if r["name"] == name)
                self.assertEqual(row["verdict"], "skipped")
                self.assertNotEqual(self.file(f"{name}-i20261025T040000Z", "2026-10-25T04:01Z", ok=False).returncode, 0)

    def test_completion_observation_cooldown_and_clock_jump(self):
        self.create("--every-hours", "2")
        ident = "scan-i20261025T000000Z"
        self.file(ident, "2026-10-25T01:59Z")
        self.owned(ident, "idle")
        self.done(ident)
        self.assertEqual(self.verdict("2026-10-25T01:59:30Z")["verdict"], "filed")
        # A late first run cannot be followed one minute later at the next label.
        self.assertEqual(self.verdict("2026-10-25T02:00Z")["verdict"], "skipped")
        self.assertEqual(self.verdict("2026-10-25T03:59:59Z")["verdict"], "skipped")
        self.assertEqual(self.verdict("2026-10-25T04:00Z")["verdict"], "due")
        # Advancing UTC alone cannot bypass elapsed spacing.
        jumped = {**self.env, "FM_BOT_TEST_MONOTONIC": "10"}
        row = json.loads(self.bot("due", "--json", "--now", "2026-10-26T04:00Z", env=jumped).stdout)[0]
        self.assertEqual(row["verdict"], "skipped")
        # Reset observation starts another conservative wait, never a backlog.
        self.assertNotEqual(self.file("scan-i20261025T020000Z", "2026-10-26T04:01Z", ok=False).returncode, 0)

    def test_remote_skips_do_not_replay_and_later_change_uses_same_guard(self):
        self.remote()
        self.verdict("2026-10-24T22:00Z")
        b = self.publish("b")
        first = self.verdict("2026-10-24T22:01Z")["id"]
        plan = json.loads(self.file(first, "2026-10-24T22:01Z").stdout)
        c = self.publish("c")
        skipped = self.verdict("2026-10-24T22:02Z")
        self.assertEqual((skipped["verdict"], skipped["trigger"]["observed_oid"]), ("skipped", c))
        self.owned(first, "idle")
        self.done(first)
        self.assertEqual(self.verdict("2026-10-24T22:03Z")["verdict"], "skipped")
        self.assertEqual(self.verdict("2026-10-25T00:04Z")["verdict"], "skipped")
        self.assertNotEqual(self.file(skipped["id"], "2026-10-25T00:04Z", ok=False).returncode, 0)
        d = self.publish("d")
        latest = self.verdict("2026-10-25T00:05Z")
        self.assertEqual((latest["verdict"], latest["trigger"]["observed_oid"]), ("due", d))
        next_plan = json.loads(self.file(latest["id"], "2026-10-25T00:05Z").stdout)
        self.assertEqual(next_plan["trigger"]["observed_oid"], d)
        # The earlier immutable artifact still has precisely b, not newer c/d.
        self.assertEqual(self.git("--git-dir", plan["artifact"]["git_dir"], "show", f"{b}:fixture.txt"), "b")
        self.assertEqual(self.git("--git-dir", next_plan["artifact"]["git_dir"], "show", f"{d}:fixture.txt"), "d")

    def test_remote_artifact_does_not_require_primary_objects_or_default_tip(self):
        self.remote()
        self.verdict("2026-10-24T22:00Z")
        author = self.root / "author"
        self.git("clone", "--branch", "selected", self.origin, author)
        self.git("-C", author, "config", "user.name", "Other fixture")
        self.git("-C", author, "config", "user.email", "other@example.invalid")
        (author / "fixture.txt").write_text("remote-only")
        self.git("-C", author, "add", "fixture.txt")
        self.git("-C", author, "commit", "-m", "remote-only fixture")
        oid = self.git("-C", author, "rev-parse", "HEAD")
        self.git("-C", author, "push", "origin", "HEAD:refs/heads/selected")
        before = self.git("-C", self.project, "show-ref")
        current = self.verdict("2026-10-24T22:01Z")
        plan = json.loads(self.file(current["id"], "2026-10-24T22:01Z").stdout)
        self.assertEqual((plan["trigger"]["remote"], plan["trigger"]["branch"], plan["artifact"]["commit"]),
                         ("origin", "selected", oid))
        self.assertEqual(self.git("--git-dir", plan["artifact"]["git_dir"], "show", f"{oid}:fixture.txt"), "remote-only")
        self.assertEqual(self.git("-C", self.project, "show-ref"), before)
        absent = self.command([GIT, "-C", self.project, "cat-file", "-e", oid], ok=False)
        self.assertNotEqual(absent.returncode, 0)

    def test_interrupted_plan_recovery_is_once_only_and_never_recovers_skip(self):
        self.create("--every-hours", "3")
        marker_dir = self.fm / "data/bots/.filed"
        unrelated = self.root / "unrelated-markers"
        unrelated.mkdir()
        marker_dir.symlink_to(unrelated)
        ident = "scan-i20261025T010000Z"
        failed = self.file(ident, "2026-10-25T01:00Z", ok=False)
        self.assertNotEqual(failed.returncode, 0)
        row = self.command([FMROOT / "bin/fm-tasks-axi.sh", "show", ident, "--full"]).stdout
        self.assertIn("state: queued", row)
        marker_dir.unlink()
        plan = json.loads(self.file(ident, "2026-10-25T04:00Z").stdout)
        self.assertEqual((plan["id"], plan["already_filed"]), (ident, True))
        self.assertIn("already-filed:", self.file(ident, "2026-10-25T04:01Z").stdout)
        self.assertEqual(self.verdict("2026-10-25T04:02Z")["verdict"], "skipped")
        self.assertFalse(list(unrelated.iterdir()))

    def test_add_acknowledgement_loss_recovers_on_first_retry_only(self):
        self.create("--every-hours", "3")
        actual = str(Path(shutil.which("tasks-axi")).resolve())
        tool = self.bin / "tasks-axi"
        tool.unlink()
        tool.write_text(
            f'#!/bin/bash\n"{actual}" "$@"\nrc=$?\n'
            'if [ "$rc" = 0 ] && [ "$1" = add ] && [ ! -e "$FM_HOME/ack-lost" ]; then\n'
            '  touch "$FM_HOME/ack-lost"; exit 73\nfi\nexit "$rc"\n')
        tool.chmod(0o700)
        ident = "scan-i20261025T010000Z"
        self.assertNotEqual(self.file(ident, "2026-10-25T01:00Z", ok=False).returncode, 0)
        plan = json.loads(self.file(ident, "2026-10-25T01:01Z").stdout)
        self.assertEqual((plan["id"], plan["already_filed"]), (ident, True))
        self.assertIn("already-filed:", self.file(ident, "2026-10-25T01:02Z").stdout)

    def test_remote_concurrent_filing_and_artifact_failure_retains_work(self):
        self.remote()
        self.verdict("2026-10-24T22:00Z")
        oid = self.publish("b")
        ident = self.verdict("2026-10-24T22:01Z")["id"]
        observation = self.fm / "data/bots/.observed/scan.json"
        saved = observation.read_bytes()
        tool = self.bin / "git"
        tool.unlink()
        tool.write_text(f'#!/bin/sh\ncase " $* " in *" fetch "*) exit 1 ;; esac\nexec "{GIT}" "$@"\n')
        tool.chmod(0o700)
        failed = self.file(ident, "2026-10-24T22:02Z", ok=False)
        self.assertNotEqual(failed.returncode, 0)
        self.assertFalse((self.fm / "data/backlog.md").exists())
        self.assertEqual(observation.read_bytes(), saved)
        tool.unlink()
        tool.symlink_to(Path(GIT).resolve())
        with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
            results = list(pool.map(lambda _: self.file(ident, "2026-10-24T22:03Z"), range(2)))
        plans = [json.loads(r.stdout) for r in results if r.stdout.startswith("{")]
        self.assertEqual([(p["id"], p["artifact"]["commit"]) for p in plans], [(ident, oid)])

    def test_forward_utc_jump_does_not_fake_monotonic_spacing(self):
        self.create("--every-hours", "2")
        ident = "scan-i20261025T000000Z"
        self.file(ident, "2026-10-25T00:00Z")
        self.owned(ident, "idle")
        self.done(ident)
        slow = {**self.env, "FM_BOT_TEST_MONOTONIC": "1000"}
        self.bot("due", "--json", "--now", "2026-10-25T00:01Z", env=slow)
        jumped = {**self.env, "FM_BOT_TEST_MONOTONIC": "1010"}
        row = json.loads(self.bot("due", "--json", "--now", "2026-10-26T00:01Z", env=jumped).stdout)[0]
        self.assertEqual(row["verdict"], "skipped")
        # No queue appears when only the monotonic clock later catches up.
        elapsed = {**self.env, "FM_BOT_TEST_MONOTONIC": "8200"}
        row = json.loads(self.bot("due", "--json", "--now", "2026-10-26T00:02Z", env=elapsed).stdout)[0]
        self.assertEqual(row["verdict"], "skipped")

    def test_new_incarnation_invalidates_earlier_completion_observation(self):
        self.create("--every-hours", "3")
        first = "scan-i20261025T010000Z"
        self.file(first, "2026-10-25T01:00Z")
        self.owned(first, "idle")
        self.done(first)
        self.verdict("2026-10-25T01:01Z")
        self.owned(first, "idle")  # same occurrence, genuinely different armed gen
        self.verdict("2026-10-25T03:59Z")
        self.assertEqual(self.verdict("2026-10-25T04:00Z")["verdict"], "skipped")
        self.assertEqual(self.verdict("2026-10-25T07:00Z")["verdict"], "due")

    def test_missing_corrupt_or_symlinked_admission_never_resets_guard(self):
        self.create("--every-hours", "3")
        self.file("scan-i20261025T010000Z", "2026-10-25T01:00Z")
        marker = self.fm / "data/bots/.admission/scan.json"
        saved = marker.read_bytes()
        marker.unlink()
        for corrupt in (None, b'{}', b'null', b'{"last_job": false}'):
            with self.subTest(corrupt=corrupt):
                if corrupt is not None:
                    marker.write_bytes(corrupt)
                self.assertEqual(self.verdict("2026-10-25T04:00Z")["reason"], "admission-unavailable")
                self.assertNotEqual(self.file("scan-i20261025T040000Z", "2026-10-25T04:00Z", ok=False).returncode, 0)
                if marker.exists():
                    marker.unlink()
        target = self.root / "unrelated-admission"
        target.write_bytes(saved)
        marker.symlink_to(target)
        self.assertEqual(self.verdict("2026-10-25T04:00Z")["reason"], "admission-unavailable")
        self.assertEqual(target.read_bytes(), saved)

    def test_pending_previous_job_remains_guarded_after_midnight_and_pause(self):
        self.create("--every-hours", "3")
        self.file("scan-i20261025T220000Z", "2026-10-25T22:59Z")
        self.bot("pause", "scan")
        self.assertEqual(self.verdict("2026-10-26T01:00Z")["verdict"], "paused")
        self.bot("resume", "scan")
        row = self.verdict("2026-10-26T01:01Z")
        self.assertEqual((row["id"], row["verdict"]), ("scan-i20261026T010000Z", "skipped"))

    def test_unowned_row_cannot_replace_last_owned_job_or_release_overlap_guard(self):
        self.create("--every-hours", "3")
        first, foreign = "scan-i20261025T010000Z", "scan-i20261025T040000Z"
        self.file(first, "2026-10-25T01:00Z")
        self.command([FMROOT / "bin/fm-tasks-axi.sh", "add", foreign, "--title", "unowned fixture"])
        self.assertEqual(self.verdict("2026-10-25T04:00Z")["verdict"], "skipped")
        shown = json.loads(self.bot("show", "scan", "--json", "--now", "2026-10-25T04:01Z").stdout)
        self.assertEqual(shown["last_run"], first)
        self.owned(first, "idle")
        self.done(first)
        self.verdict("2026-10-25T04:02Z")
        self.assertEqual(self.verdict("2026-10-25T07:00Z")["verdict"], "skipped")

    def test_recovery_never_reprints_a_plan_after_authority_is_narrowed(self):
        self.create("--every-hours", "3", "--level", "local-commit",
                    "--authorization", "fixture local commit only", "--authorization-scope", "sandbox",
                    "--authorized-on", "2026-10-01", "--expires", "2027-01-01",
                    "--max-files", "2", "--max-lines", "40")
        marker = self.fm / "data/bots/.filed"
        decoy = self.root / "marker-decoy"
        decoy.mkdir()
        marker.symlink_to(decoy)
        ident = "scan-i20261025T010000Z"
        self.assertNotEqual(self.file(ident, "2026-10-25T01:00Z", ok=False).returncode, 0)
        marker.unlink()
        spec = self.fm / "data/bots/scan.md"
        spec.write_text(spec.read_text().replace("level: local-commit", "level: local-proposal"))
        retried = self.file(ident, "2026-10-25T01:01Z", ok=False)
        self.assertNotEqual(retried.returncode, 0)
        self.assertNotIn('"kind": "ship"', retried.stdout)

    def test_daily_plan_keeps_the_scope_snapshot_that_passed_authorization(self):
        self.create("--at", "03:00", "--until", "05:59", "--level", "local-commit",
                    "--authorization", "scan sandbox review approved",
                    "--authorization-scope", "sandbox report only",
                    "--authorized-on", "2026-10-24", "--expires", "2027-01-01",
                    "--max-files", "2", "--max-lines", "40")
        native = self.root / "native"
        (native / "bin").mkdir(parents=True)
        tasks = native / "bin/fm-tasks-axi.sh"
        tasks.write_text(f'#!/bin/sh\nexec "{FMROOT}/bin/fm-tasks-axi.sh" "$@"\n')
        tasks.chmod(0o700)
        posture = native / "bin/fm-project-mode.sh"
        posture.write_text(
            '#!/bin/sh\n'
            f'"{PYTHON}" -c \'from pathlib import Path; import sys; p=Path(sys.argv[1]); '
            'p.write_text(p.read_text().replace("scope: Review selected project; report only", '
            '"scope: Changed after authorization snapshot"))\' "$FM_HOME/data/bots/scan.md"\n'
            f'exec "{FMROOT}/bin/fm-project-mode.sh" "$@"\n')
        posture.chmod(0o700)
        result = self.file("scan-20261025", "2026-10-25T02:00Z",
                           env={**self.env, "FIRSTMATE_ROOT": str(native)})
        plan = json.loads(result.stdout)
        self.assertEqual((plan["scope"], plan["level"]),
                         ("Review selected project; report only", "local-commit"))
        self.assertIn("scope: Changed after authorization snapshot",
                      (self.fm / "data/bots/scan.md").read_text())

    def test_remote_binding_changed_during_inspection_keeps_prior_observation(self):
        self.remote()
        self.assertEqual(self.verdict("2026-10-24T22:01Z")["verdict"], "baseline")
        observation = self.fm / "data/bots/.observed/scan.json"
        before = observation.read_bytes()
        other = self.root / "other.git"
        self.git("init", "--bare", other)
        self.commit("unrelated remote")
        self.git("-C", self.project, "push", str(other), "HEAD:refs/heads/selected")
        wrapper = self.bin / "git"
        wrapper.unlink()
        wrapper.write_text(
            '#!/bin/sh\ncase " $* " in *" ls-remote "*)\n'
            f'  "{GIT}" -C "$FM_HOME/projects/sandbox" remote set-url origin "{other}" ;;\n'
            'esac\n'
            f'exec "{GIT}" "$@"\n')
        wrapper.chmod(0o700)
        verdict = self.verdict("2026-10-24T22:02Z")
        self.assertEqual((verdict["verdict"], verdict.get("reason")), ("error", "remote-changed"))
        self.assertEqual(observation.read_bytes(), before)

    def test_daily_empty_days_does_not_become_an_active_daily_bot(self):
        # An explicitly empty schedule is not consent to run every day.
        r = self.bot("create", "empty-days", *self.base, "--at", "03:00",
                     "--until", "04:00", "--days", "", ok=False)
        self.assertNotEqual(r.returncode, 0)
        self.assertFalse((self.fm / "data/bots/empty-days.md").exists())

    def test_daily_contract_unchanged(self):
        # Catches opt-in fields changing legacy limits, ids, spec layout, or plans.
        self.create("--at", "03:00", "--until", "05:59", "--wall-clock-min", "90")
        spec = (self.fm / "data/bots/scan.md").read_text()
        self.assertNotIn("trigger:", spec)
        self.assertNotIn("every_hours:", spec)
        r = self.verdict("2026-10-25T02:00Z")
        self.assertEqual((r["id"], r["verdict"]), ("scan-20261025", "due"))
        plan = json.loads(self.bot("file", "scan-20261025", "--json", "--now", "2026-10-25T02:00Z").stdout)
        self.assertEqual((plan["kind"], plan["wall_clock_min"], plan["report"]),
                         ("scout", "90", "data/scan-20261025/report.md"))
        self.assertEqual(self.verdict("2026-10-25T02:05Z")["verdict"], "filed")


if __name__ == "__main__":
    if not GIT or not shutil.which("tasks-axi") or not (FMROOT / "bin/fm-tasks-axi.sh").is_file():
        sys.exit("SKIP: native git/tasks-axi/official FirstMate required; no test passed")
    unittest.main(verbosity=2)

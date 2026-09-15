---
name: verification-provenance
description: Establish that verification (test/build/lint) evidence actually ran against the assigned task worktree, not a shared container or artifact bound to a different checkout. Use whenever declaring a command's output as proof before completion, especially when the command ran in Docker, a remote executor, or against a prebuilt artifact rather than a plain local shell in the worktree.
---

# Verification provenance

Fresh, green output is necessary but never sufficient by itself
(`verification-before-completion` already requires the "fresh" half). This
skill adds the missing half: the output must be demonstrably tied to *this*
task's assigned worktree, not merely plausible.

## The failure this exists to close

A shared container or shared remote executor can be bound to a checkout that
is not this task's worktree - e.g. a long-lived dev container mounted from
someone else's clone. A test suite run inside it can go green while never
touching a single line of this task's actual changes. Green output alone does
not prove that; provenance does.

## Procedure

Before citing a command's output as verification evidence, self-report three
plain "LABEL: value" lines (never invented per-command; use the same three
labels every time):

- `VERIFY_PROVENANCE_KIND`: exactly one of
  - `local` - a plain shell command run directly against the worktree
  - `container-bind` - Docker or another container, with the worktree
    bind-mounted in
  - `artifact` - a prebuilt binary/image/package, not a live source tree
- `VERIFY_EXECUTION_REALPATH`: the canonical host filesystem path proving
  the claim -
  - `local`: run `git rev-parse --show-toplevel` (or `pwd -P` for a
    non-git command) from wherever the command actually ran
  - `container-bind`: the **host-side** bind-mount source directory's
    realpath - never the in-container mount target (e.g. never `/workspace`)
  - `artifact`: the source tree path the artifact was built from
- `VERIFY_ARTIFACT_SOURCE_COMMIT` (artifact kind only): the commit the
  artifact's source tree was built from, e.g. embedded build metadata or a
  `git rev-parse HEAD` taken at build time.

`firstmate/fm-verify-provenance.sh`'s `fm_provenance_classify` is the one
deterministic classifier for these three fields; it never guesses a pass. The
worker report is attacker-controlled, so an accepting classification also
requires Firstmate/caller-supplied observed provenance (`FM_OBSERVED_*`) from an
independent wrapper or inspector. Without that independently observed fact,
truthful wrong-tree reports still reject as `wrong_tree`, but apparently correct
self-reports classify as `uncertain` rather than pass.

Its five outcomes:

| Outcome | Meaning |
| --- | --- |
| `worktree_local` | Accept - plain local run, reported path and caller-observed path both match |
| `bind_correct` | Accept - container bind source, as reported and independently observed, is this worktree |
| `artifact_correct` | Accept - artifact's reported and observed source path/commit both match |
| `wrong_tree` | Reject - reported provenance resolves to a different checkout |
| `uncertain` | Reject - a required field is missing, unrecognized, or unprovable; never accepted as a silent pass |

## Recovery

A `wrong_tree` or `uncertain` classification is not completion. Recover by
re-running the same check with worktree-correct provenance - a plain local
command in the assigned worktree is always available as the fallback - and
report the corrected fields. Do not round a rejected or uncertain result up
to "verified."

## Boundaries

This skill classifies **evidence for one already-run command**; it never
intercepts arbitrary commands, manages containers, or orchestrates builds.
Do not hardcode a specific container name, mount path, or CI system anywhere
that cites this skill - the three labels above are the entire generic
contract.

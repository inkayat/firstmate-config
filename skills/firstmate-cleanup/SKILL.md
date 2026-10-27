---
name: firstmate-cleanup
description: Clean up finished FirstMate task agents, their task-owned Space/workspace or terminal panes, disposable worktrees, and transient task records. Use for requests such as "clean up finished agents and their Spaces" or "clean up completed FirstMate tasks". Preserves deliverables and unfinished work; excludes memory curation and unrelated Spaces.
---

# FirstMate cleanup

Perform this from the FirstMate Captain/operator context, not from a delegated
worker asked to remove itself or siblings. This skill uses FirstMate's lifecycle
owners; it adds no cleanup service, scheduler, or alternative state database.
Installing or selecting this skill does not authorize any cleanup by itself.

## Resolve the scope

- Resolve the installed `FIRSTMATE_ROOT` and the owning `FM_HOME` from the
  existing FirstMate configuration/session. Keep them explicit for every helper
  call: scripts live in the distribution checkout, records in the operational
  home. If either is ambiguous, inspect configuration before choosing a target.
- Read that distribution's `AGENTS.md` and
  `.agents/skills/ship-landing/SKILL.md` before cleanup. Their current lifecycle
  and supervision contracts remain authoritative. If the required helper or
  contract is unavailable, report that limit rather than improvise deletion.
- "Space" here means a task's runtime workspace (for example Herdr), identified
  through the task record. A request about ChatGPT Spaces or another app needs
  that app's workflow; it is not authority to delete a FirstMate workspace.
- For a named task, inspect only that task and its dependencies. For a general
  finished-task sweep, inventory this home's task records using
  `bin/fm-fleet-snapshot.sh --contribution-input`. Do not extend a sweep into
  other homes, persistent secondmates, unrelated projects, or unrecorded spaces.

## Decide what is ready

Read each candidate's `state/<id>.meta`, its durable backlog record through
`bin/fm-tasks-axi.sh show <id> --full`, and its current state through
`bin/fm-crew-state.sh <id>`. A historical `done:` line, an idle pane, an empty
queue, or a Completed board card alone does not prove cleanup is safe.

Read the candidate's task brief and applicable project/task preservation rules.
Agent exit, pane/Space closure, source return/deletion, and volatile record or
evidence removal are separate permissions. A source/evidence preservation rule
may prohibit full teardown without prohibiting a separately authorized safe
exit; do not generalize that task's rule to unrelated finished tasks. Copying
results elsewhere is not a substitute when the original must remain or copying
is prohibited. If the supported owner cannot perform only the permitted action,
retain the protected resources and report the limit.

- **Ship:** confirm landing through the selected delivery path. A pushed branch,
  green checks, an open PR, or a clean local ready branch can still be waiting
  on approval. Cleanup never authorizes commit, push, PR creation, or merge.
- **Scout:** load `.agents/skills/scout-completion/SKILL.md`. Read and preserve
  the self-contained report and any required deliverables outside the scratch
  copy before it is discarded. Keep an interactive artifact alive while the
  user is still iterating on it; honor the existing completion/decision gate.
- **Persistent secondmate:** idle is healthy. Exclude it from routine sweeps.
  Only an explicit retirement decision invokes
  `.agents/skills/secondmate-provisioning/SKILL.md` and its own retirement flow.
- **Working, waiting for review/approval, blocked, paused, failed, or unknown:**
  retain it and state the concrete reason. Do not turn recovery, cancellation,
  or unresolved decisions into "finished" work for the sake of tidying up.

A request to clean finished tasks authorizes ordinary guarded cleanup of
verified candidates. Reuse existing authority; do not ask again for each safe
candidate. It does not authorize discarding unfinished or unlanded work.

## Clean through the owner

### Prove input safety and exit first

Read the installed `docs/agent-control.md`, `bin/fm-control.sh`, and the recorded
backend's supported input/composer inspection contract. Before lifecycle input,
use that existing owner's inspection of the exact recorded endpoint to prove
there is no pending user input. `bin/fm-backend.sh`'s
`fm_backend_composer_state` owns composer verdicts; do not invent a screen regex
or shell-key fallback. Require positive emptiness, or owner-confirmed absence
of the exact endpoint with no surviving composer. Idle, landed Git work, agent
death, or a failed endpoint read is not input-safety proof. If supported
inspection cannot establish safety, preserve the candidate and stop.

After preserving required results and satisfying any existing terminal
follow-up obligations, recheck identity, current state and input safety. Exit
preserves source but may retire busy-state wiring; check any evidence protection
before invoking it. Use the control plane with the intended installation/home:

```sh
FM_HOME="$FM_HOME" "$FIRSTMATE_ROOT/bin/fm-control.sh" "$task_id" exit
```

Capture its exit status and full diagnostics. Require exit status `0` and the
owner's verified result for that exact task/endpoint: `stopped`,
`already-stopped`, or `endpoint-gone`, as defined by the installed contract.
`already-stopped` proves no agent is running, not that a composer was checked;
`endpoint-gone` requires the owner's positive absence proof, not unreachability.
Even `stopped` can follow an interrupt without the typed-exit composer check.
None of these words substitutes for the separate positive input-safety proof.
The normal typed-exit path requires composer verdict `empty` before submission
and verifies agent death afterwards; command delivery alone is not completion.

Pending input, refusal, unsupported inspection/exit, unknown state, nonzero exit,
or an unconfirmed result stops this candidate. Never fall through to teardown,
add `--force`, clear/submit/copy away/discard user text, or bypass a dialog to
make the check pass, even if a diagnostic suggests clearing it. Report what
actually happened; a failed exit may already have delivered lifecycle input.
If only exit is authorized, stop after verifying it; do not release source or
remove the remaining task records.

### Teardown only when independently permitted

Only after positive input safety and verified safe exit, and only when source
return, presentation closure and volatile record removal are also permitted,
recheck task identity, ownership, landing/decision constraints and input safety
on any surviving endpoint immediately before the full teardown. If any proof
changed or is unavailable, stop; the earlier exit is not a cleanup bypass.

```sh
FM_HOME="$FM_HOME" "$FIRSTMATE_ROOT/bin/fm-teardown.sh" "$task_id"
```

The helper owns endpoint closure, worktree release, transient checks and records,
and the paired backlog transition. Let it perform these together. Follow a
reported manual-backlog exception through that home's documented workflow;
never close an outstanding captain decision just because its worker is gone.

- Never replace the helper with raw workspace/tab deletion, process killing,
  manual metadata edits, worktree removal, or branch deletion. Never close an
  entire shared workspace to remove one finished agent. For Herdr, inspect
  `docs/herdr-backend.md` and `bin/backends/herdr.sh` if presentation cleanup is
  unclear; teardown targets the recorded pane, not an arbitrary workspace.
- A refusal preserves the evidence needed to investigate. Stop that candidate,
  explain the refusal, and continue only with independent verified candidates.
  Do not clear locks, erase ownership claims, alter records, or add bypass flags
  to make cleanup succeed. A stale record or orphaned Space needs proven identity
  and a supported recovery path; a matching title is insufficient.
- Use `--force` only with explicit authority to discard the named task's work,
  after identifying what would be lost. A general cleanup request is not that
  authority, and it never bypasses the input/exit stop above. Ownership guards
  still apply; force can skip work/report checks and is not decision authority.
- Preserve `data/<id>/`, reports, briefs, attachments, knowledge, and useful
  history. Teardown deliberately retains task data, but retires volatile state;
  do not invoke it when that state is protected evidence. Deleting durable data,
  purging archives, or removing remote branches requires separately scoped authority.

## Verify and report

Capture each helper's exit status and diagnostics. For teardown, exit `0` is
success; exit `4` means cleanup completed with a lost worktree pool slot and must
be reported as partial/degraded, not fully clean. Other nonzero results are
refusals/errors; inspect actual remaining resources before reporting their
outcome, since a late refusal may follow source return or endpoint closure.

Re-read the owning home's task inventory/backlog and inspect the exact recorded
runtime endpoint using the installed backend's supported inspection path.
Distinguish confirmed absence from an unreachable runtime. Verify durable
deliverables remain accessible and no outstanding decision was falsely closed.
A surviving/quarantined presentation record is a remaining item, not permission
for broader deletion. Refresh an existing board through its normal projection
command only if needed; never edit board state to hide a leftover.

Reply in the user's language: what was cleaned, what deliverables were retained,
what remains and why, and any concrete decision needed. Keep candidate-specific
failures visible rather than reporting the whole sweep as successful.

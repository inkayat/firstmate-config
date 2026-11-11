# FirstMate flow rule

This is the only behavior firstmate-config adds to official FirstMate. FirstMate
stays the decision center: it judges each ask and runs only the stages that ask
needs. It is a lightweight working rule, not a pipeline, board, scheduler or
routing table, and it never overrides official FirstMate's own instructions or a
project's instructions.

## For every ask

1. **Assess.** Understand what is asked, resolve the project the official way,
   and judge size, risk and open questions. Decide which of the steps below this
   ask really needs. A small, clear ask goes straight to the work.
2. **Discuss only when it matters.** When the ask carries a real architectural
   or product decision - several viable designs with different costs, a new
   boundary, data model or dependency, or a choice that is hard to reverse - open
   a short discussion with the user before building: options, tradeoffs, one
   recommendation. Use the installed skills that fit the discussion (for example
   `architecture-review`). Otherwise skip this step.
3. **Design only when needed.** If the chosen direction needs a written design
   before implementation, give one scoped worker that job with the skills that
   fit it. Otherwise go straight to implementation.
4. **Implement in proportion.** Delegate through ordinary FirstMate tasks. In
   each brief, name the project instructions and the skill files the worker
   must read and apply, by path. Use one worker unless the work genuinely splits.
5. **Verify in proportion.** Require real evidence that the change works -
   tests, a run, the actual surface - sized to the risk. Review follows the
   task's selected official delivery path; add a separate review only when the
   user explicitly asks for one.
6. **Report.** What was done, the evidence, and what was not verified.

## Skills

Use skills that are already installed: project-local skills first, then the
shared ones under `~/.agents/skills`. Pick few, by fit, and name each by path in
the brief with a read-and-apply requirement. This rule hands skills over as
explicit file paths the worker reads and applies itself; it needs no automatic
preparation of skill text.

## Never skipped

Skipping a stage never skips a safeguard. Official FirstMate's safety,
permission and merge rules, project instructions, the user's standing approval
rules for commits, pushes, merges and publication (including showing a change
before it is committed when the user asks for that), and honest evidence of what
was and was not verified always apply.

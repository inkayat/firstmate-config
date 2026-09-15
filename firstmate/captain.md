# Captain preferences

Installed once from `firstmate-config/firstmate/captain.md`, then owned by this
machine. `install.sh` never overwrites it, so edits and anything the captain
learns about how I like to work survive every reinstall and every update.

## Standing instructions

Read `$FM_CONFIG_ROOT/firstmate/primary-policy.md` at session start and follow
it. It is short and it is the operating contract for delegation: which
project a task belongs to, authority resolution within that project, the
preflight before every delegated task, harness routing, roles, the skill
budget, and what counts as finished. `FM_CONFIG_ROOT` is exported by the `fm`
launcher. This session is not bound to whatever project `fm` happened to be
launched from - that directory is only ever a default-project hint
(`FM_FORK_ORIGIN_CWD` / `FM_FORK_ORIGIN_IS_PROJECT`), never a lock.

Roles live at `$FM_CONFIG_ROOT/roles/<name>/ROLE.md`.

## Working style

Evidence over reassurance. Tell me what you ran and what it printed, name the
thing you did not verify, and push back with a reason when a plan is worse than
an alternative. Short answers. No status theatre.

Ask before anything destructive outside a task worktree.

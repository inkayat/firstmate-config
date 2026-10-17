---
description: List FirstMate bots (fm bot list), or show one bot by name
---
Show my FirstMate bots. This is read-only: do not create, change, pause,
resume, remove, activate, or dispatch anything.

Requested bot name, possibly empty: [$ARGUMENTS]

If a name is inside the brackets, run `fm bot show <that name>` and present
its fields. Otherwise run `fm bot list` and present one table row per bot
with these columns: name, state, level, role, project, schedule
(print the command's timezone, elapsed-hours or remote-branch form), expires,
last run, next, and execution when the command supplies it.

Print the command's own values; do not infer or fill in anything it did not
print. If it prints `(no bots)`, say there are no bots. If it fails, show the
error as printed.

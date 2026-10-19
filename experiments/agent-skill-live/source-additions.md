# Operator runbook: temporary source additions

This is an explicit source edit tool, not a loader, installer, workflow, selector
or completion gate. It never changes Git HEADs/branches, remotes, source pins,
role frontmatter, symlinks, routing or budgets. No active application is performed
by the preparation worker. Main applies the approved additions separately.

## Frozen transport versus destination

Keep this preparation branch in a **separate frozen source clone**. Do not
install from that clone, repoint installed links to it, or switch the active
config checkout to this branch. `source_additions.py` obtains local role/skill
addition bodies from this clone's real `roles/*/ROLE.md` and
`skills/django-backend/SKILL.md`. Three targeted `source-additions/*.append`
files transport only the external sources' own additions. They are not extra
worker instructions and are never exported with the starter.

`source-manifest.json` freezes expected original SHA256s and exact revisions:

| Explicit destination root | Expected HEAD | Target paths |
| --- | --- | --- |
| config | `d5e6e1ca8385645c30f7825047e9df838162b474` | `roles/django-pro/ROLE.md`, `roles/code-reviewer/ROLE.md`, `roles/technical-writer/ROLE.md`, `skills/django-backend/SKILL.md` |
| superpowers | `b36e0829c6d0140e93cfef2ca599b1b07d4a7797` | `skills/test-driven-development/SKILL.md` |
| addy | `be4e44a9fbc5e8df0beaefadbb28bd22ee61cc39` | `skills/code-review-and-quality/SKILL.md`, `skills/documentation-and-adrs/SKILL.md` |

verification-before-completion is inventoried, not changed. All role descriptions,
autoload defaults, skill selection explanations and the normal budget are retained.
Companions remain at their original locations: TDD's `writing-good-tests.md`, and
Addy's root `references/security-checklist.md` and `performance-checklist.md`.
The tool checks these companions on apply/status and never writes them.
It leaves the normal installed `~/.agents/references` link untouched.

## Apply/status/revert (macOS and Omarchy/Linux)

Requires Git and Python 3.10+ for this standard-library tool. The starter has its
own Python 3.12–3.14 requirement. After Main publishes **only** the test branch,
an operator can obtain a frozen transport without changing the active install:

```sh
FROZEN="$HOME/firstmate-live-probe-source"
# Use a new, absent directory. Substitute the exact published preparation HEAD.
PREP_COMMIT=<source-additions-commit>
git clone --single-branch --branch fm/fmc-agent-skill-live-probe-prep \
  https://github.com/inkayat/firstmate-config.git "$FROZEN"
git -C "$FROZEN" checkout --detach "$PREP_COMMIT"
```

On the Mac, Main may use the already committed isolated preparation checkout
as the frozen transport until retaining its own clone. The actual destinations
recorded at preparation intake were:

```sh
CONFIG_DEST=/Users/inkayat/.firstmate/projects/firstmate-config
SUPERPOWERS=/Users/inkayat/.local/share/firstmate-config/skills-src/obra-superpowers
ADDY=/Users/inkayat/.local/share/firstmate-config/skills-src/addyosmani-agent-skills
```

On Omarchy, set these to the **existing installed source roots**, not to the
frozen transport. Confirm normal installed resolutions before acting; for example:

```sh
python3 - <<'PY'
from pathlib import Path
home = Path.home()
for relative in [".omp/agent/agents/fm-django-pro.md",
                 ".agents/skills/test-driven-development/SKILL.md",
                 ".agents/skills/code-review-and-quality/SKILL.md"]:
    target = (home / relative).resolve(strict=True)
    print(relative, "->", target, "source root:", target.parents[2])
PY
```

Then use the same explicit roots for each operation:

```sh
TOOL="$FROZEN/experiments/agent-skill-live/source_additions.py"
python3 "$TOOL" status --config-root "$CONFIG_DEST" \
  --superpowers-root "$SUPERPOWERS" --addy-root "$ADDY"
python3 "$TOOL" apply --config-root "$CONFIG_DEST" \
  --superpowers-root "$SUPERPOWERS" --addy-root "$ADDY"
python3 "$TOOL" status --config-root "$CONFIG_DEST" \
  --superpowers-root "$SUPERPOWERS" --addy-root "$ADDY"
# After the live observation, remove only this tool's exact owned additions:
python3 "$TOOL" revert --config-root "$CONFIG_DEST" \
  --superpowers-root "$SUPERPOWERS" --addy-root "$ADDY"
```

`--only config` (or `superpowers`, `addy`, multiple allowed) limits selected roots;
only selected roots need their root arguments. Default selection is all three.
Every selected source pin, baseline, marker and companion is checked before the
first write. Apply is idempotent, as is revert. Partial/duplicate/altered marker
bodies, changed baselines or wrong revisions produce `refused:` and exit 1.
Status also refuses changed surrounding baselines, rather than hiding drift.
Revert validates source revisions and exact owned blocks but intentionally permits
unrelated surrounding/companion edits; it removes only its exact inserted bytes.
Already-absent revert leaves the file unchanged, including unrelated edits.

Do not run concurrently with edits, install or update. The tool rechecks source
bytes before writes and atomically replaces each regular file with its original
mode. It is not a multi-file filesystem transaction: an I/O failure or concurrent
edit after writes begin may leave partial application; inspect status and resolve
the reported cause. It never restores a saved full-file backup over later changes.

## Updates, reinstall and removal

Active config main remains at its original HEAD but intentionally becomes dirty
in four source files. Normal `fm update` requires clean trees and will safely
refuse this condition. **Revert before updating/reinstalling**, using the retained
frozen tool. Do not stash/reset the primary, bypass updater checks, change pins,
or make the installer ignore local changes for the test.

If reinstall removes additions at unchanged pins and original hashes, reapply
explicitly with the same command. Nothing auto-reapplies. If update changes HEADs,
pins or baselines, this frozen tool refuses: a new inspected preparation against
those exact sources is required, not a forced apply or edited manifest on the fly.
Do not restart current sessions; additions can only be observed through later
normal fresh role/skill preparation. Application alone proves no model adoption.

Retain the frozen tool until active additions are removed. The two preparation
commits are separate: the starter commit and the source/tool commit. Reverting
that latter commit on the test branch does not clean active destination sources;
run the tool's revert first. No config-main merge is part of this experiment.

## Isolated preparation tests

The suite clones each explicitly supplied local repository into temporary
fixtures, checks out the pinned revisions there, and drives the real CLI. It
never edits its input repositories or installed sources and uses no network.

```sh
python3 "$FROZEN/experiments/agent-skill-live/test_source_additions.py" \
  --config-source "$CONFIG_DEST" --superpowers-source "$SUPERPOWERS" \
  --addy-source "$ADDY" -v
```

Covers apply/status/revert, repeat operations, selection scoping, rejected baseline,
pin and marker drift, all-target preflight, later-edit preservation, symlink
resolution and referenced-companion preservation. This is CLI evidence, not a
live agent/skill acceptance run. Linux execution was not available during Mac
preparation (the installed Docker client had no running socket); Linux behavior
is unverified, not claimed as passing. No runtime was started to obtain it.

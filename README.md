# firstmate-config

Version 0.6.0 (proposed, not yet tagged or released).

One working rule for official
[FirstMate](https://github.com/kunchenguid/firstmate) (`kunchenguid/firstmate`,
branch `main`), used directly with no fork. The rule is
[`flow-rule.md`](flow-rule.md): FirstMate judges each ask and runs only the
stages it needs - a short discussion when a real architectural decision is at
stake, a scoped design worker when a written design is needed, then proportionate
implementation and verification - while every safeguard stays in force.

Everything else this repository used to carry - the `fm` launcher, update,
doctor and version commands, board, bots, routing profiles, roles, the shared
skill catalogue, installer and tests - is not part of 0.6.0. It remains
available as the previous version: tag `v0.5.0` and the git history up to
commit `b18ce2b0363d57790daed1fb173dfabf02fae3f5`.

## Use

1. Install and run official FirstMate as its own README describes.
2. Clone this repository somewhere persistent.
3. Add one line to your FirstMate home's `data/captain.md` (default
   `~/.firstmate/data/captain.md`), using the absolute path of your clone:

   ```text
   At session start, read and follow /absolute/path/to/firstmate-config/flow-rule.md.
   ```

Official FirstMate prints `data/captain.md` in full at every session start, so
the Captain sees this line each time and reads the rule from your clone. A
running Captain picks it up at its next session start. Pulling this repository
updates the rule; nothing else is installed.

## Limits

The rule is guidance for the Captain, not enforcement: nothing checks that a
stage was chosen well or that a worker read the files a brief names. The rule
hands skills and instructions to workers as explicit file paths to read and
apply; it does not rely on any automatic preparation of their text.

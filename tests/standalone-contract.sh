#!/usr/bin/env bash
# Offline public-command checks in synthetic HOME/local Git remotes only.
# Catches nested dotfiles-root adoption, verify writes, loss of user state,
# official branch/source bypasses, and accidental retained retired commands.
# shellcheck source=tests/fixture.sh
. "$(dirname "${BASH_SOURCE[0]}")/fixture.sh"
make_world || exit 1

# --verify on a fresh machine must not create even an empty skills directory.
out=$("$FMC/install.sh" --verify 2>&1); status=$?
check 'fresh verify succeeds as a drift report' "$status" 0
has 'fresh verify reports drift' "$out" DRIFT
check 'verify creates no operational home' "$([ -e "$FMHOME" ] && printf yes || printf no)" no
check 'verify creates no shared skills directory' "$([ -e "$HOME/.agents" ] && printf yes || printf no)" no
check 'verify creates no environment file' "$([ -e "$HOME/.config/firstmate-config/env" ] && printf yes || printf no)" no

# Refuse an installer/updater nested in a larger repo, including the old
# dotfiles topology, before touching any machine-owned state or either HEAD.
mkdir -p "$T/wrapper"
git init -q -b main "$T/wrapper"
cp -R "$FMC" "$T/wrapper/firstmate-config"
rm -rf "$T/wrapper/firstmate-config/.git"
out=$("$T/wrapper/firstmate-config/install.sh" 2>&1); status=$?
check 'nested config installer is refused' "$status" 1
has 'installer names standalone root requirement' "$out" 'standalone Git root'
check 'rejected install creates no operational home' "$([ -e "$FMHOME" ] && printf yes || printf no)" no

"$FMC/install.sh" > "$T/install.out" 2>&1 || { cat "$T/install.out"; exit 1; }
before=$(git -C "$OFFICIAL" rev-parse HEAD)
out=$("$T/wrapper/firstmate-config/bin/fm-update" --check 2>&1); status=$?
check 'nested updater is refused' "$status" 1
has 'updater names standalone root requirement' "$out" 'standalone Git root'
check 'wrong config root leaves official untouched' "$(git -C "$OFFICIAL" rev-parse HEAD)" "$before"

printf 'private captain preferences\n' > "$FMHOME/data/captain.md"
mkdir -p "$FMHOME/data/bots" "$FMHOME/state" "$HOME/.pi/agent"
printf 'private receipt\n' > "$FMHOME/data/bots/receipt"
printf 'private hook\n' > "$FMHOME/state/bots.check.sh"
printf '{"packages":["private-package"]}\n' > "$HOME/.pi/agent/settings.json"
ln -s "$T/foreign-bots" "$HOME/.local/bin/ponytail-update"
"$FMC/install.sh" > "$T/reinstall.out" 2>&1; status=$?
check 'reconcile preserves retired user data without failing' "$status" 0
check 'captain preferences preserved' "$(cat "$FMHOME/data/captain.md")" 'private captain preferences'
check 'bot receipt preserved' "$(cat "$FMHOME/data/bots/receipt")" 'private receipt'
check 'existing hook is not administered' "$(cat "$FMHOME/state/bots.check.sh")" 'private hook'
check 'Pi package settings are no longer managed' "$(cat "$HOME/.pi/agent/settings.json")" '{"packages":["private-package"]}'
check 'retired launcher link is not removed' "$(readlink "$HOME/.local/bin/ponytail-update")" "$T/foreign-bots"
out=$("$HOME/.local/bin/fm" tlw 2>&1); status=$?
check 'retired tlw command refused' "$status" 1

# --check never fetches: remote tip advances but local refs and trees stay.
push_change "$OFFICIAL_REMOTE" new-official 'upstream only'
refs_before=$(git -C "$OFFICIAL" rev-parse origin/main)
out=$("$HOME/.local/bin/fm" update --check 2>&1); status=$?
check 'standalone update check succeeds' "$status" 0
check 'check leaves fetched ref unchanged' "$(git -C "$OFFICIAL" rev-parse origin/main)" "$refs_before"
check 'check leaves official HEAD unchanged' "$(git -C "$OFFICIAL" rev-parse HEAD)" "$before"
for mode in --migrate --bootstrap; do
  out=$("$HOME/.local/bin/fm" update "$mode" 2>&1); status=$?
  check "removed migration mode $mode refused" "$status" 1
done

mkdir -p "$OFFICIAL/nested"
out=$(FIRSTMATE_ROOT="$OFFICIAL/nested" FM_CONFIG_ENV="$T/no-env" "$FMC/bin/fm-update" --check 2>&1); status=$?
check 'nested official root refused' "$status" 1
has 'nested official root refusal names checkout root' "$out" 'not the root of a checkout'
rmdir "$OFFICIAL/nested"

git -C "$OFFICIAL" switch -qc wrong-branch
out=$("$HOME/.local/bin/fm" update --check 2>&1); status=$?
check 'wrong official branch refused' "$status" 1
git -C "$OFFICIAL" switch -q main
git -C "$OFFICIAL" remote set-head origin -d
out=$("$HOME/.local/bin/fm" update --check 2>&1); status=$?
check 'missing official default ref refused' "$status" 1
finish

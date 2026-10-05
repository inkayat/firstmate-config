#!/usr/bin/env bash
# install.sh - reconcile this machine with the configuration in this repository.
#
# Rerunning is the normal case, not the exception: every step below states a
# desired end state and makes only the change needed to reach it, so a second
# run prints the same report and touches nothing. The only file that is ever
# created-and-then-left-alone is $FM_HOME/data/captain.md, which belongs to the
# machine once it exists.
#
#   1. checks the toolchain
#   2. clones the official FirstMate checkout if it is missing, never modifies it
#   3. creates the machine-local operational home
#   4. writes ~/.config/firstmate-config/env, the machine-local resolution
#   5. selects the herdr runtime backend
#   6. links the dispatch profiles and seeds the captain file
#   7. links our skills and the pinned external packs into ~/.agents/skills,
#      our slash commands (commands/*.md) into ~/.agents/commands, each
#      role file (roles/<name>/ROLE.md) as OMP agent fm-<name> into
#      ~/.omp/agent/agents
#   8. links the fm launcher onto PATH
#   9. reconciles the Pi Ponytail package: a separate pinned checkout (never
#      the shared skill cache from step 7), a skills filter in Pi's own
#      settings so its bundled ponytail/ponytail-review duplicates never
#      collide with step 7's authoritative copies, and defaultMode=off in
#      ponytail's own config
#  10. reconciles the pinned Agent Library (library_* in the stack manifest)
#      at ${XDG_DATA_HOME:-$HOME/.local/share}/agent-library, the root bin/fm
#      discovers: an exact-commit fetch, a verified private export, and an
#      atomic pointer switch recorded in a receipt it owns; retained versions
#      are never deleted, and state it never recorded is never adopted
#      (firstmate/fm-stack-manifest.sh stack_library)
#
# What it never does: store a credential, touch a project repository, or modify
# anything tracked in the official FirstMate checkout.
#
# Usage:
#   ./install.sh                     reconcile
#   ./install.sh --verify            report drift without changing anything
#   ./install.sh --library-rollback  switch the Agent Library back to the
#                                    retained previous version (step 10 only);
#                                    the next reconcile returns it to the pin
set -u

CONFIG_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=firstmate/fm-stack-manifest.sh
. "$CONFIG_ROOT/firstmate/fm-stack-manifest.sh"
if ! stack_manifest_load "$CONFIG_ROOT/firstmate/stack-manifest.tsv"; then
  printf 'install: %s\n' "$SM_LOAD_ERROR" >&2
  exit 1
fi
FIRSTMATE_ROOT="${FIRSTMATE_ROOT:-$HOME/Developer/tools/firstmate}"
FIRSTMATE_ORIGIN="${FIRSTMATE_ORIGIN:-$SM_FIRSTMATE_REPO}"
FM_HOME="${FM_HOME:-$HOME/.firstmate}"
FM_BACKEND=herdr
ENV_FILE="${FM_CONFIG_ENV:-$HOME/.config/firstmate-config/env}"
SKILLS_ROOT="${FM_SKILLS_ROOT:-$HOME/.agents/skills}"
COMMANDS_ROOT="${FM_COMMANDS_ROOT:-$HOME/.agents/commands}"
AGENTS_ROOT="${FM_OMP_AGENTS_ROOT:-$HOME/.omp/agent/agents}"
SKILL_CACHE="${FM_SKILL_CACHE:-$HOME/.local/share/firstmate-config/skills-src}"
BIN_DIR="${FM_BIN_DIR:-$HOME/.local/bin}"
# Every git probe below inspects a repository it must not silently write to
# (an existing official checkout it never updates); a clone still needs a
# real write, which this setting does not affect.
export GIT_OPTIONAL_LOCKS=0

VERIFY=0
[ "${1:-}" != --verify ] || VERIFY=1
ROLLBACK=0
[ "${1:-}" != --library-rollback ] || ROLLBACK=1

changed=0
failed=0
ok()      { printf '  ok      %s\n' "$1"; }
changedf() { printf '  changed %s\n' "$1"; changed=$((changed + 1)); }
driftf()  { printf '  DRIFT   %s\n' "$1"; changed=$((changed + 1)); }
warn()    { printf '  warn    %s\n' "$1"; }
failf()   { printf '  FAIL    %s\n' "$1" >&2; failed=1; }
step()    { printf '\n%s\n' "$1"; }

# act <description> -- runs the body unless --verify, reporting either way.
would() { # <description>
  if [ "$VERIFY" -eq 1 ]; then driftf "$1"; return 1; fi
  return 0
}

# Step 10, defined ahead of step 1 so --library-rollback can run it alone.
# stack_library prints step-9-style result lines (install/rollback) or one
# status line (verify), mapped here onto this script's own report.
LIBRARY_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
library_step() { # install|rollback|verify
  local out rc line state msg
  if [ -z "$SM_LIBRARY_REPO" ]; then
    warn 'no Agent Library pin in firstmate/stack-manifest.tsv; skipping'
    return 0
  fi
  if ! command -v python3 >/dev/null 2>&1; then
    failf 'python3 is required for the Agent Library step'
    return 0
  fi
  if [ "$1" = verify ]; then
    out=$(stack_library status "$LIBRARY_DATA_HOME" "$SKILL_CACHE/agent-library.git"); rc=$?
    IFS="$(printf '\t')" read -r _ state _ msg <<EOF
$out
EOF
    case $state in
      healthy) ok "$msg" ;;
      not_installed|differs|pending|busy) driftf "$msg" ;;
      ownership|corrupt) failf "$msg" ;;
      *) failf "the Agent Library check exited with status $rc before reporting a result" ;;
    esac
    return 0
  fi
  out=$(stack_library "$1" "$LIBRARY_DATA_HOME" "$SKILL_CACHE/agent-library.git"); rc=$?
  while IFS= read -r line; do
    case $line in
      ok\ *) ok "${line#ok }" ;;
      changed\ *) changedf "${line#changed }" ;;
      warn\ *) warn "${line#warn }" ;;
      fail\ *) failf "${line#fail }" ;;
      '') ;;
      *) failf "Agent Library step: unexpected output: $line" ;;
    esac
  done <<EOF
$out
EOF
  [ "$rc" -eq 0 ] || failf "the Agent Library step exited with status $rc before reporting a result; rerun install.sh"
}

if [ "$ROLLBACK" -eq 1 ]; then
  step '10. Agent Library (rollback to the retained previous version)'
  library_step rollback
  printf '\ninstall: %s change(s), %s failure(s)\n' "$changed" "$failed"
  [ "$failed" -eq 0 ]
  exit
fi

# --- 1. toolchain -----------------------------------------------------------
step '1. toolchain'
for tool in git pi omp herdr; do
  if command -v "$tool" >/dev/null 2>&1; then
    ok "$tool present"
  else
    failf "$tool is required and not on PATH"
  fi
done
for tool in jq treehouse gh bun; do
  if command -v "$tool" >/dev/null 2>&1; then
    ok "$tool present"
  else
    warn "$tool is not on PATH; it is needed for full fleet behavior"
  fi
done
[ "$failed" -eq 0 ] || { printf '\ninstall: missing required tools\n' >&2; exit 1; }

# --- 2. official FirstMate --------------------------------------------------
step '2. official FirstMate checkout'
if [ -f "$FIRSTMATE_ROOT/AGENTS.md" ]; then
  ok "present at $FIRSTMATE_ROOT"
  head_sha=$(git -C "$FIRSTMATE_ROOT" rev-parse --short HEAD 2>/dev/null || printf 'unknown')
  dirty=$(git -C "$FIRSTMATE_ROOT" status --porcelain 2>/dev/null | wc -l | tr -d ' ')
  ok "at $head_sha, $dirty tracked modifications"
  [ "$dirty" = 0 ] || warn 'the official checkout has local modifications; this configuration expects it unmodified'
  # Report-only: an already-present checkout is never updated, rewound, or
  # re-pinned here, no matter how it relates to the validated baseline.
  relation=$(stack_commit_relation "$FIRSTMATE_ROOT" "$SM_FIRSTMATE_COMMIT")
  case $relation in
    exact) ok "matches the validated baseline commit $SM_FIRSTMATE_COMMIT" ;;
    descendant) warn "ahead of the validated baseline commit $SM_FIRSTMATE_COMMIT (unvalidated; not changed automatically)" ;;
    ancestor) warn "behind the validated baseline commit $SM_FIRSTMATE_COMMIT (not updated automatically; run fm doctor for detail)" ;;
    diverged) warn "history has diverged from the validated baseline commit $SM_FIRSTMATE_COMMIT" ;;
    *) warn "relationship to the validated baseline commit $SM_FIRSTMATE_COMMIT is unknown (that commit is not in this checkout's local history)" ;;
  esac
elif would "clone $FIRSTMATE_ORIGIN into $FIRSTMATE_ROOT, pinned to $SM_FIRSTMATE_COMMIT"; then
  mkdir -p "$(dirname "$FIRSTMATE_ROOT")" || failf "cannot create $(dirname "$FIRSTMATE_ROOT")"
  if git clone -q "$FIRSTMATE_ORIGIN" "$FIRSTMATE_ROOT" \
     && git -C "$FIRSTMATE_ROOT" checkout -q "$SM_FIRSTMATE_COMMIT"; then
    changedf "cloned FirstMate into $FIRSTMATE_ROOT, pinned to $SM_FIRSTMATE_COMMIT"
  else
    failf "could not clone $FIRSTMATE_ORIGIN and pin it to $SM_FIRSTMATE_COMMIT"
    # Never leave a half-cloned or unpinned checkout behind for the next run
    # to mistake for a genuine, present install: a partial clone/pin failure
    # must not be reportable as success on a later run.
    rm -rf "$FIRSTMATE_ROOT"
  fi
fi

# --- 3. operational home ----------------------------------------------------
step '3. machine-local operational home'
if [ -e "$FM_HOME/.fm-secondmate-home" ]; then
  failf "$FM_HOME is a secondmate home and cannot be a captain home"
else
  for dir in state data config projects; do
    if [ -d "$FM_HOME/$dir" ]; then
      ok "$FM_HOME/$dir"
    elif would "create $FM_HOME/$dir"; then
      if mkdir -p "$FM_HOME/$dir"; then changedf "created $FM_HOME/$dir"; else failf "cannot create $FM_HOME/$dir"; fi
    fi
  done
fi

# --- 4. machine-local environment -------------------------------------------
write_env_file() { # -> prints ok|drift|changed|fail
  local env_body
  env_body=$(cat <<EOF
# Written by firstmate-config/install.sh. Machine-local: never commit this.
FIRSTMATE_ROOT="$FIRSTMATE_ROOT"
FM_CONFIG_ROOT="$CONFIG_ROOT"
FM_HOME="$FM_HOME"
FM_BACKEND="$FM_BACKEND"
export FIRSTMATE_ROOT FM_CONFIG_ROOT FM_HOME FM_BACKEND
EOF
  )
  if [ -f "$ENV_FILE" ] && [ "$(cat "$ENV_FILE")" = "$env_body" ]; then printf ok; return; fi
  if [ "$VERIFY" -eq 1 ]; then printf drift; return; fi
  if mkdir -p "$(dirname "$ENV_FILE")" && printf '%s\n' "$env_body" > "$ENV_FILE"; then
    printf changed
  else
    printf fail
  fi
}

step '4. machine-local environment'
case $(write_env_file) in
  ok) ok "$ENV_FILE" ;;
  drift) driftf "write $ENV_FILE" ;;
  changed) changedf "wrote $ENV_FILE" ;;
  *) failf "cannot write $ENV_FILE" ;;
esac

# --- 5. runtime backend -----------------------------------------------------
step '5. runtime backend'
backend_file="$FM_HOME/config/backend"
if [ -f "$backend_file" ] && [ "$(tr -d '[:space:]' < "$backend_file")" = "$FM_BACKEND" ]; then
  ok "config/backend is $FM_BACKEND"
elif would "set config/backend to $FM_BACKEND"; then
  if printf '%s\n' "$FM_BACKEND" > "$backend_file"; then
    changedf "set config/backend to $FM_BACKEND"
  else
    failf "cannot write $backend_file"
  fi
fi

# --- 6. dispatch profiles and captain file ---------------------------------
step '6. dispatch profiles and captain file'
# Shared links are stored relative to their own directory, so a moved HOME or
# another machine's HOME spelling keeps them valid. A source is linkable only
# when it exists and its physical path (parent directories resolved, its own
# final component never followed) stays inside the tree it was named under:
# this checkout or the external skill cache. An existing link is current when
# its link chain reaches that physical path without any hop leaving that tree,
# however it is spelled - absolute, relative, or through an alias inside the
# tree - and is then left untouched. Any other existing link - wrong, broken,
# or through a foreign alias - is a failure that is never rewritten: a name
# alone proves nothing about who owns the link.
physical() { # <path> -> <path> with its parent directories resolved
  local dir
  case $(basename "$1") in
    # A terminal . or .. names a directory, not an entry: resolve it whole.
    .|..) (CDPATH='' cd -P "$1" 2>/dev/null && pwd -P); return ;;
  esac
  dir=$(CDPATH='' cd -P "$(dirname "$1")" 2>/dev/null && pwd -P) || return 1
  printf '%s/%s\n' "${dir%/}" "$(basename "$1")"
}
owned_source() { # <target> ; sets OWNED_ROOT and OWNED, fails when missing or outside its tree
  OWNED_ROOT='' OWNED=''
  case $1 in
    "$CONFIG_ROOT"/*) OWNED_ROOT=$CONFIG_ROOT ;;
    "$SKILL_CACHE"/*) OWNED_ROOT=$SKILL_CACHE ;;
    *) return 1 ;;
  esac
  [ -e "$1" ] || return 1
  OWNED_ROOT=$(CDPATH='' cd -P "$OWNED_ROOT" 2>/dev/null && pwd -P) || return 1
  OWNED=$(physical "$1") || return 1
  case $OWNED in "$OWNED_ROOT"/*) return 0 ;; esac
  return 1
}
reaches_owned() { # <link> ; its chain reaches $OWNED and never leaves $OWNED_ROOT
  local p=$1 text hop n=0
  while [ "$n" -lt 40 ]; do
    text=$(readlink "$p") || return 1
    case $text in /*) hop=$text ;; *) hop="$(dirname "$p")/$text" ;; esac
    hop=$(physical "$hop") || return 1
    [ "$hop" != "$OWNED" ] || return 0
    case $hop in "$OWNED_ROOT"/*) ;; *) return 1 ;; esac
    [ -L "$hop" ] || return 1
    p=$hop
    n=$((n + 1))
  done
  return 1
}
relative_to() { # <physical dir> <physical path> -> <path> spelled from <dir>
  local from=${1%/}/ up=''
  while [ "${2#"$from"}" = "$2" ]; do
    from=${from%/*/}/
    up="../$up"
  done
  printf '%s%s\n' "$up" "${2#"$from"}"
}
link_to() { # <target> <link> ; creates a missing link, never rewrites an existing one
  local target=$1 link=$2 dir
  if ! owned_source "$target"; then
    failf "$target is missing or outside its own tree; not linking $link"
    return 0
  fi
  if [ -L "$link" ]; then
    if reaches_owned "$link"; then
      ok "$link"
    else
      failf "$link points at $(readlink "$link"), not $target; leaving it alone (remove it to relink)"
    fi
    return 0
  fi
  if [ -e "$link" ]; then
    warn "$link exists and is not one of ours; leaving it alone"
    return 0
  fi
  would "link $link -> $target" || return 0
  mkdir -p "$(dirname "$link")"
  if dir=$(CDPATH='' cd -P "$(dirname "$link")" 2>/dev/null && pwd -P) \
     && ln -s "$(relative_to "$dir" "$OWNED")" "$link"; then
    changedf "linked $link"
  else
    failf "cannot link $link"
  fi
}

link_to "$CONFIG_ROOT/firstmate/crew-dispatch.json" "$FM_HOME/config/crew-dispatch.json"

captain="$FM_HOME/data/captain.md"
if [ -e "$captain" ]; then
  ok 'data/captain.md exists; leaving this machine'"'"'s copy alone'
elif would 'seed data/captain.md from the template'; then
  if cp "$CONFIG_ROOT/firstmate/captain.md" "$captain"; then
    changedf 'seeded data/captain.md'
  else
    failf "cannot write $captain"
  fi
fi

# --- 7. global skills, commands, and role agents ------------------------------
step '7. global skills, commands, and role agents'
mkdir -p "$SKILLS_ROOT" 2>/dev/null || true

for skill_dir in "$CONFIG_ROOT"/skills/*/; do
  [ -f "$skill_dir/SKILL.md" ] || continue
  name=$(basename "$skill_dir")
  link_to "${skill_dir%/}" "$SKILLS_ROOT/$name"
done

# OMP's `agents` provider turns each ~/.agents/commands/<name>.md into
# /<name> in every session, the same shared root convention as the skills.
for command_file in "$CONFIG_ROOT"/commands/*.md; do
  [ -f "$command_file" ] || continue
  link_to "$command_file" "$COMMANDS_ROOT/$(basename "$command_file")"
done

# Each role file opens with OMP task-agent frontmatter (name: fm-<role>), so
# linking it into OMP's user agent root makes fm-<role> spawnable from every
# OMP session. A symlink already there is ours only when it points at a
# roles/<role>/ROLE.md (this or another firstmate-config checkout); any other
# entry under that name belongs to the user and is left alone.
for role_file in "$CONFIG_ROOT"/roles/*/ROLE.md; do
  [ -f "$role_file" ] || continue
  agent_link="$AGENTS_ROOT/fm-$(basename "$(dirname "$role_file")").md"
  if [ -L "$agent_link" ]; then
    case $(readlink "$agent_link") in
      */roles/*/ROLE.md) ;;
      *) warn "$agent_link exists and is not one of ours; leaving it alone"; continue ;;
    esac
  fi
  link_to "$role_file" "$agent_link"
done

lock="$CONFIG_ROOT/skills/external.lock"
if [ ! -f "$lock" ]; then
  warn 'no skills/external.lock; skipping external packs'
else
  # One checkout per repository, at the pinned commit.
  repos=$(awk -F'\t' '/^[^#]/ && NF >= 5 {print $2 "\t" $3}' "$lock" | sort -u)
  printf '%s\n' "$repos" | while IFS="$(printf '\t')" read -r repo sha; do
    [ -n "${repo:-}" ] || continue
    dest="$SKILL_CACHE/$(printf '%s' "$repo" | tr '/' '-')"
    if [ -d "$dest/.git" ] && [ "$(git -C "$dest" rev-parse HEAD 2>/dev/null)" = "$sha" ]; then
      printf '  ok      %s at %s\n' "$repo" "${sha%"${sha#???????}"}"
      continue
    fi
    if [ "$VERIFY" -eq 1 ]; then printf '  DRIFT   %s is not at %s\n' "$repo" "$sha"; continue; fi
    mkdir -p "$SKILL_CACHE"
    if [ ! -d "$dest/.git" ]; then
      git clone -q "https://github.com/$repo.git" "$dest" || { printf '  FAIL    cannot clone %s\n' "$repo" >&2; continue; }
    fi
    git -C "$dest" fetch -q --all 2>/dev/null
    if git -C "$dest" checkout -q "$sha" 2>/dev/null; then
      printf '  changed %s pinned to %s\n' "$repo" "${sha%"${sha#???????}"}"
    else
      printf '  FAIL    %s has no commit %s\n' "$repo" "$sha" >&2
    fi
  done

  while IFS="$(printf '\t')" read -r id repo sha path name; do
    case ${id:-} in ''|\#*) continue ;; esac
    [ -n "${name:-}" ] || continue
    src="$SKILL_CACHE/$(printf '%s' "$repo" | tr '/' '-')/$path"
    if [ ! -f "$src/SKILL.md" ]; then
      failf "$id: no SKILL.md at $src"
      continue
    fi
    link_to "$src" "$SKILLS_ROOT/$name"
  done < "$lock"

  # addyosmani skills link to ../../references/*.md at their repository root.
  # From ~/.agents/skills/<name>/SKILL.md that path resolves to
  # ~/.agents/references, so that is where the repository's references belong.
  addy_refs="$SKILL_CACHE/addyosmani-agent-skills/references"
  [ ! -d "$addy_refs" ] || link_to "$addy_refs" "$(dirname "$SKILLS_ROOT")/references"
fi

# --- 8. command launchers ---------------------------------------------------
step '8. command launchers'
link_to "$CONFIG_ROOT/bin/fm" "$BIN_DIR/fm"
link_to "$CONFIG_ROOT/bin/ponytail-update" "$BIN_DIR/ponytail-update"
case ":$PATH:" in
  *":$BIN_DIR:"*) ok "$BIN_DIR is on PATH" ;;
  *) warn "$BIN_DIR is not on PATH; add it to your shell profile" ;;
esac

# --- 9. Pi Ponytail package --------------------------------------------------
# The upstream Ponytail package ships six skills (ponytail, -review, -audit,
# -debt, -gain, -help) and one extension. Two of those skills duplicate the
# ones step 7 already installs from the same upstream repo into the shared,
# authoritative ~/.agents/skills. Reconciling it here as a direct pinned
# checkout into Pi's own package path (`$PI_AGENT_DIR/git/<host>/<repo>`,
# matching what `pi install` would produce, but cloned by this script
# itself rather than shelled out to Pi's installer) keeps this reproducible
# from a clean machine with `git pull && ./install.sh`, matching this
# file's own convention of cloning pinned sources itself (see steps 2 and 7).
# Its checkout is deliberately separate from step 7's shared skill cache
# clone: a later `pi update` of this package must never be able to mutate
# the canonical shared skills.
step '9. Pi Ponytail package'
PONYTAIL_REPO=DietrichGebert/ponytail
PONYTAIL_SOURCE="git:github.com/$PONYTAIL_REPO"
PI_AGENT_DIR="${PI_CODING_AGENT_DIR:-$HOME/.pi/agent}"
ponytail_pkg_dir="$PI_AGENT_DIR/git/github.com/$PONYTAIL_REPO"
ponytail_settings="$PI_AGENT_DIR/settings.json"
ponytail_config="${XDG_CONFIG_HOME:-$HOME/.config}/ponytail/config.json"

if [ ! -f "$lock" ]; then
  warn 'no skills/external.lock; skipping Pi ponytail package'
else
  # Single source-of-truth pin: the same commit skills/external.lock already
  # pins for the shared ponytail/ponytail-review skills, read dynamically
  # rather than duplicated here as a second literal.
  ponytail_sha=$(awk -F'\t' -v repo="$PONYTAIL_REPO" '/^[^#]/ && NF >= 5 && $2==repo {print $3; exit}' "$lock")
  if [ -z "$ponytail_sha" ]; then
    warn "skills/external.lock has no $PONYTAIL_REPO pin; skipping Pi ponytail package"
  else
    if [ -d "$ponytail_pkg_dir/.git" ] && [ "$(git -C "$ponytail_pkg_dir" rev-parse HEAD 2>/dev/null)" = "$ponytail_sha" ]; then
      ok "pi package $PONYTAIL_SOURCE at ${ponytail_sha%"${ponytail_sha#???????}"}"
    elif would "pin pi package $PONYTAIL_SOURCE to $ponytail_sha"; then
      mkdir -p "$(dirname "$ponytail_pkg_dir")"
      [ -d "$ponytail_pkg_dir/.git" ] || git clone -q "https://github.com/$PONYTAIL_REPO.git" "$ponytail_pkg_dir" 2>/dev/null
      if [ -d "$ponytail_pkg_dir/.git" ]; then
        git -C "$ponytail_pkg_dir" fetch -q --all 2>/dev/null
        if git -C "$ponytail_pkg_dir" checkout -q "$ponytail_sha" 2>/dev/null; then
          changedf "pi package $PONYTAIL_SOURCE pinned to ${ponytail_sha%"${ponytail_sha#???????}"}"
        else
          failf "pi package $PONYTAIL_SOURCE has no commit $ponytail_sha"
        fi
      else
        failf "cannot clone pi package $PONYTAIL_SOURCE"
      fi
    fi

    if [ -d "$ponytail_pkg_dir" ]; then
      if ! command -v python3 >/dev/null 2>&1; then
        failf "python3 is required to reconcile $ponytail_settings and $ponytail_config"
      else
        # Structural merge: only the "skills" filter on this one package
        # entry is ever touched; every other key, entry, and file is
        # preserved byte-for-byte when already correct.
        pi_settings_result=$(PONYTAIL_SOURCE="$PONYTAIL_SOURCE" PONYTAIL_VERIFY="$VERIFY" python3 - "$ponytail_settings" <<'PY'
import json, os, sys
path = sys.argv[1]
src = os.environ["PONYTAIL_SOURCE"]
verify = os.environ["PONYTAIL_VERIFY"] == "1"
skills = ["-skills/ponytail/SKILL.md", "-skills/ponytail-review/SKILL.md"]
try:
    with open(path) as f:
        data = json.load(f)
except FileNotFoundError:
    data = {}
except json.JSONDecodeError as e:
    print(f"fail invalid JSON in {path}: {e}")
    sys.exit(0)
pkgs = data.get("packages", [])
changed = False
found = False
for i, p in enumerate(pkgs):
    if isinstance(p, dict) and p.get("source") == src:
        found = True
        if p.get("skills") != skills:
            p["skills"] = skills
            changed = True
        break
    if isinstance(p, str) and p == src:
        pkgs[i] = {"source": src, "skills": skills}
        found = True
        changed = True
        break
if not found:
    pkgs.append({"source": src, "skills": skills})
    changed = True
if not changed:
    print(f"ok {src} skills filter")
elif verify:
    print(f"drift {src} skills filter")
else:
    data["packages"] = pkgs
    os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
    with open(path, "w") as f:
        json.dump(data, f, indent=2)
        f.write("\n")
    print(f"changed {src} skills filter in {path}")
PY
)
        case $pi_settings_result in
          ok\ *)     ok "${pi_settings_result#ok }" ;;
          changed\ *) changedf "${pi_settings_result#changed }" ;;
          drift\ *)  driftf "${pi_settings_result#drift }" ;;
          fail\ *)   failf "${pi_settings_result#fail }" ;;
          *)         failf "could not reconcile $ponytail_settings: $pi_settings_result" ;;
        esac

        ponytail_config_result=$(PONYTAIL_VERIFY="$VERIFY" python3 - "$ponytail_config" <<'PY'
import json, os, sys
path = sys.argv[1]
verify = os.environ["PONYTAIL_VERIFY"] == "1"
try:
    with open(path) as f:
        data = json.load(f)
except FileNotFoundError:
    data = {}
except json.JSONDecodeError as e:
    print(f"fail invalid JSON in {path}: {e}")
    sys.exit(0)
if data.get("defaultMode") == "off":
    print(f"ok {path}: defaultMode is off")
elif verify:
    print(f"drift {path}: defaultMode is not off")
else:
    data["defaultMode"] = "off"
    os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
    with open(path, "w") as f:
        json.dump(data, f, indent=2)
        f.write("\n")
    print(f"changed {path}: set defaultMode=off")
PY
)
        case $ponytail_config_result in
          ok\ *)     ok "${ponytail_config_result#ok }" ;;
          changed\ *) changedf "${ponytail_config_result#changed }" ;;
          drift\ *)  driftf "${ponytail_config_result#drift }" ;;
          fail\ *)   failf "${ponytail_config_result#fail }" ;;
          *)         failf "could not reconcile $ponytail_config: $ponytail_config_result" ;;
        esac
      fi
    fi
  fi
fi

# --- 10. Agent Library -----------------------------------------------------
# The pinned Library lives outside every checkout, at the portable per-user
# root bin/fm discovers when AGENT_LIBRARY_ROOT is unset; this step never
# writes AGENT_LIBRARY_ROOT anywhere. A no-op when the pinned version is
# already active and verified; a fetch or auth failure fails this run with
# the installed version left active. Rules: stack_library in
# firstmate/fm-stack-manifest.sh, docs/install.html.
step '10. Agent Library'
if [ "$VERIFY" -eq 1 ]; then library_step verify; else library_step install; fi

# --- report -----------------------------------------------------------------
if [ "$VERIFY" -eq 1 ]; then
  printf '\nverify: %s drift item(s), %s failure(s)\n' "$changed" "$failed"
else
  printf '\ninstall: %s change(s), %s failure(s)\n' "$changed" "$failed"
fi

[ "$failed" -eq 0 ]

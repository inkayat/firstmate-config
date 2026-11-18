# shellcheck shell=bash
# fm-roles-lib.sh - the one owner of role-file frontmatter parsing.
#
# Sourced by bin/fm-role-handoff and the tests. A role is
# $ROLES_ROOT/<name>/ROLE.md; its only skill source is the frontmatter
# `autoloadSkills` list. Nothing here selects a skill: the Captain chooses a
# role, and the role's list is the whole skill set a worker is handed.
#
# Callers set ROLES_ROOT (the roles directory) before calling anything.

# role_file <role> - prints the ROLE.md path, fails when the role does not exist.
role_file() {
  case $1 in ''|*[!a-z0-9-]*) return 1 ;; esac
  [ -f "$ROLES_ROOT/$1/ROLE.md" ] && printf '%s/%s/ROLE.md\n' "$ROLES_ROOT" "$1"
}

# role_names - one installed role name per line.
role_names() {
  local f
  for f in "$ROLES_ROOT"/*/ROLE.md; do
    [ -f "$f" ] && basename "$(dirname "$f")"
  done
}

# role_frontmatter <ROLE.md> - the lines between the opening and closing `---`.
# Fails when the file does not open with a frontmatter block that is closed.
role_frontmatter() {
  awk '
    NR == 1 { if ($0 != "---") exit 1; next }
    $0 == "---" { closed = 1; exit }
    { print }
    END { if (!closed) exit 1 }
  ' "$1"
}

# role_autoload_skills <role> - one autoloadSkills entry per line, in file
# order, duplicates kept (the lint reports them). Prints nothing for a role
# without the key or with `autoloadSkills: []`. Accepts only the block list
# form the roles use; any other shape fails loudly rather than being guessed.
role_autoload_skills() {
  local file fm
  file=$(role_file "$1") || { printf 'no such role: %s\n' "$1" >&2; return 1; }
  fm=$(role_frontmatter "$file") || { printf 'role %s: frontmatter is missing or not closed\n' "$1" >&2; return 1; }
  printf '%s\n' "$fm" | awk '
    /^autoloadSkills:[[:space:]]*\[\][[:space:]]*$/ { next }
    /^autoloadSkills:[[:space:]]*$/ { in_list = 1; next }
    /^autoloadSkills:/ { bad = 1; next }
    in_list && /^[[:space:]]+-[[:space:]]+[A-Za-z0-9][A-Za-z0-9_-]*[[:space:]]*$/ {
      sub(/^[[:space:]]+-[[:space:]]+/, ""); sub(/[[:space:]]+$/, ""); print; next
    }
    in_list && /^[[:space:]]/ { bad = 1; next }
    { in_list = 0 }
    END { if (bad) exit 1 }
  ' || { printf 'role %s: autoloadSkills is not a plain block list of skill names\n' "$1" >&2; return 1; }
}

# role_frontmatter_name <role> - the `name:` value (OMP agent name).
role_frontmatter_name() {
  local file
  file=$(role_file "$1") || return 1
  role_frontmatter "$file" | sed -n 's/^name:[[:space:]]*//p' | head -n 1
}

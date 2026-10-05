#!/usr/bin/env bash
# fm-stack-manifest.sh - the one parsing/comparison owner for
# firstmate/stack-manifest.tsv, the single source of truth for stable
# compatibility information across OMP Captain -> official FirstMate ->
# Herdr -> Pi / OMP, on macOS and Betao/Omarchy Linux. Sourced by install.sh,
# bin/fm-doctor and bin/fm-version; never fork this parsing, the
# version-comparison logic, or the Agent Library state rules between them -
# extend this file instead.
#
# Public interface:
#   stack_manifest_load <path>
#     Sets the SM_* globals below from a strict key<TAB>value manifest file.
#     Returns 1 and sets SM_LOAD_ERROR on: a missing file; a file missing any
#     required key; a duplicate required key (the first occurrence wins the
#     error, never a silent last-value overwrite); a schema_version other
#     than the one this parser supports; a firstmate_validated_commit that
#     is not a full 40-hex SHA; a min/tested tool version that is not plain
#     numeric dotted form; or a min version greater than its own tested
#     version. Every SM_* global is reset to empty first, so a failed load
#     can never leave a stale value from a previous call. Unknown keys are
#     ignored (forward-compatible) but can never overwrite a known field.
#     The optional Agent Library pin - library_repo, library_commit and
#     library_tree, all three or none, plus an optional library_ref - sets
#     SM_LIBRARY_REPO/COMMIT/TREE/REF. It is a load error when only part of
#     the pin is present, when library_commit/library_tree are not full
#     lowercase hex of the same length (40, or 64 for a sha256 repository),
#     when library_repo is empty, has whitespace, or carries http(s) URL
#     credentials, or when library_ref is not refs/tags/<name>. The ref is a
#     fetch fallback only, never the pin: the commit and tree are.
#   stack_version_extract <raw>
#     Prints the leading dot-separated numeric version (two or more integer
#     components, e.g. "0.85.1") found anywhere in <raw>, or nothing when
#     none is found. Matches this project's own "leading numeric semantic
#     version only" parsing policy for --version output.
#
#   stack_version_compare <a> <b>
#     Prints lt, eq, or gt: portable numeric comparison of two dot-separated
#     integer version strings, missing trailing components treated as 0.
#     Deliberately not `sort -V` - BSD sort (macOS) has no -V flag, so that
#     would not be portable across this project's own two target platforms.
#     This is the "lightweight existing mechanism": a dozen lines of pure
#     bash, no new dependency.
#
#   stack_component_compat <ver> <min> <tested>
#     Prints PASS, WARNING, FAIL, or UNKNOWN for one installed component
#     version against its manifest policy:
#       - <ver>, <min>, or <tested> empty (unparseable/unknown input) ->
#         UNKNOWN, never a guessed FAIL.
#       - <ver> below <min> -> FAIL (hard minimum violation).
#       - <ver> above <tested> -> WARNING (newer than validated; a newer
#         version must never automatically FAIL).
#       - otherwise (<min> <= <ver> <= <tested>) -> PASS.
#
#   stack_commit_relation <repo> <baseline-full-sha>
#     Prints exact, descendant, ancestor, diverged, or unknown: reasons from
#     the local Git graph only, never fetches, never guesses.
#       - exact: <repo>'s HEAD is the baseline commit.
#       - descendant: HEAD is a descendant of the baseline (newer,
#         unvalidated).
#       - ancestor: HEAD is an ancestor of the baseline (older than the
#         validated baseline).
#       - diverged: neither is an ancestor of the other.
#       - unknown: HEAD cannot be resolved, or the baseline commit is not
#         present in <repo>'s local object graph (this function never
#         fetches to find out).
#
#   stack_library <install|rollback|status> <data-home> <source-cache-repo>
#     The Agent Library lifecycle for the loaded pin (SM_LIBRARY_*), run in
#     one python3 process. <data-home> is ${XDG_DATA_HOME:-$HOME/.local/share}
#     (D), the same root bin/fm discovers. It owns exactly:
#       D/agent-library          the active pointer, a relative symlink
#                                .agent-library/<commit>, replaced only by
#                                an atomic rename
#       D/.agent-library/<c>     immutable verified versions, never deleted
#       D/firstmate-config/agent-library.lock     the lock anchor, created
#                                once and never unlinked or recreated
#       D/firstmate-config/agent-library.receipt  the ownership receipt
#     Ownership is the receipt's recorded device/inode/link text, never a
#     name or shape: anything it does not record is refused, never adopted.
#     install: under an exclusive non-blocking flock on the anchor, finishes
#       or drops an interrupted switch the receipt records, then makes the
#       pinned version active - reusing a retained verified version, or
#       fetching the exact commit (library_ref only as a fallback), checking
#       its commit and tree ids, exporting it into a private staging
#       directory and rebuilding the pinned tree id from the exported bytes,
#       modes and symlinks - through receipt write, durable pending record,
#       identity re-checks, atomic pointer rename, then finalize. A pinned
#       version already active and verified is a no-op with no write.
#     rollback: the same protocol, switching to the receipt's retained
#       previous version after re-verifying it; nothing records a hold, so
#       the next install returns to the pin.
#     status: read-only under a shared flock (bounded retries; never
#       creates or repairs anything) and prints one line
#       "status<TAB><state><TAB><commit or ->TAB><message>", state one of
#       healthy, not_installed, differs, pending, busy, ownership, corrupt.
#     install/rollback print step-9-style "ok|changed|warn|fail <message>"
#     lines. A missing python3 or a death before a result line is the
#     caller's to report.
#
#   stack_library_runtime <data-home>
#     Sets SL_RUNTIME_MODE (explicit|default), SL_RUNTIME_ROOT and
#     SL_RUNTIME_REASON (empty when available): the Library root bin/fm hands
#     the Captain - an exported AGENT_LIBRARY_ROOT, even empty or invalid,
#     wins; only when it is unset is <data-home>/agent-library used - and
#     whether it is usable (library/bin/agent-library.ts present and bun on
#     PATH). It mirrors bin/fm's launch rule for reporting only; bin/fm stays
#     the owner of the decision.

# shellcheck disable=SC2034 # public interface: read by install.sh/fm-doctor after stack_manifest_load
SM_SCHEMA_VERSION=
SM_FIRSTMATE_REPO=
SM_FIRSTMATE_COMMIT=
SM_PI_MIN=
SM_PI_TESTED=
SM_OMP_MIN=
SM_OMP_TESTED=
SM_HERDR_MIN=
SM_HERDR_TESTED=
SM_LOAD_ERROR=
SM_LIBRARY_REPO=
SM_LIBRARY_COMMIT=
SM_LIBRARY_TREE=
SM_LIBRARY_REF=

# The schema_version this parser understands. Bump this only alongside a
# parser change that actually reads a new/changed key; a tracked manifest
# whose schema_version disagrees fails closed rather than being guessed at.
SM_SUPPORTED_SCHEMA_VERSION=1

stack_manifest_load() { # <path>
  local file=$1 key value missing='' field seen=' ' name min tested authority
  SM_SCHEMA_VERSION=; SM_FIRSTMATE_REPO=; SM_FIRSTMATE_COMMIT=
  SM_PI_MIN=; SM_PI_TESTED=; SM_OMP_MIN=; SM_OMP_TESTED=
  SM_HERDR_MIN=; SM_HERDR_TESTED=; SM_LOAD_ERROR=
  SM_LIBRARY_REPO=; SM_LIBRARY_COMMIT=; SM_LIBRARY_TREE=; SM_LIBRARY_REF=

  if [ ! -f "$file" ]; then
    SM_LOAD_ERROR="manifest not found: $file"
    return 1
  fi

  while IFS="$(printf '\t')" read -r key value || [ -n "${key:-}" ]; do
    case ${key:-} in
      ''|\#*) continue ;;
      schema_version|firstmate_repo|firstmate_validated_commit|pi_min_version|pi_tested_version|omp_min_version|omp_tested_version|herdr_min_version|herdr_tested_version|library_repo|library_commit|library_tree|library_ref)
        case $seen in
          *" $key "*)
            SM_LOAD_ERROR="manifest $file has duplicate key: $key"
            return 1
            ;;
        esac
        seen="$seen$key "
        ;;
    esac
    case ${key:-} in
      schema_version) SM_SCHEMA_VERSION=$value ;;
      firstmate_repo) SM_FIRSTMATE_REPO=$value ;;
      firstmate_validated_commit) SM_FIRSTMATE_COMMIT=$value ;;
      pi_min_version) SM_PI_MIN=$value ;;
      pi_tested_version) SM_PI_TESTED=$value ;;
      omp_min_version) SM_OMP_MIN=$value ;;
      omp_tested_version) SM_OMP_TESTED=$value ;;
      herdr_min_version) SM_HERDR_MIN=$value ;;
      herdr_tested_version) SM_HERDR_TESTED=$value ;;
      library_repo) SM_LIBRARY_REPO=$value ;;
      library_commit) SM_LIBRARY_COMMIT=$value ;;
      library_tree) SM_LIBRARY_TREE=$value ;;
      library_ref) SM_LIBRARY_REF=$value ;;
    esac
  done < "$file"

  for field in SM_SCHEMA_VERSION SM_FIRSTMATE_REPO SM_FIRSTMATE_COMMIT \
               SM_PI_MIN SM_PI_TESTED SM_OMP_MIN SM_OMP_TESTED \
               SM_HERDR_MIN SM_HERDR_TESTED; do
    [ -n "${!field}" ] || missing="$missing ${field#SM_}"
  done
  if [ -n "$missing" ]; then
    SM_LOAD_ERROR="manifest $file missing required key(s):$missing"
    return 1
  fi

  if [ "$SM_SCHEMA_VERSION" != "$SM_SUPPORTED_SCHEMA_VERSION" ]; then
    SM_LOAD_ERROR="manifest $file has unsupported schema_version '$SM_SCHEMA_VERSION' (this parser supports only $SM_SUPPORTED_SCHEMA_VERSION)"
    return 1
  fi

  if ! [[ $SM_FIRSTMATE_COMMIT =~ ^[0-9A-Fa-f]{40}$ ]]; then
    SM_LOAD_ERROR="manifest $file firstmate_validated_commit is not a full 40-hex SHA: $SM_FIRSTMATE_COMMIT"
    return 1
  fi

  for field in "pi:$SM_PI_MIN:$SM_PI_TESTED" "omp:$SM_OMP_MIN:$SM_OMP_TESTED" "herdr:$SM_HERDR_MIN:$SM_HERDR_TESTED"; do
    name=${field%%:*}; field=${field#*:}
    min=${field%%:*}; tested=${field#*:}
    if ! [[ $min =~ ^[0-9]+(\.[0-9]+)+$ ]]; then
      SM_LOAD_ERROR="manifest $file ${name}_min_version is not plain numeric dotted form: $min"
      return 1
    fi
    if ! [[ $tested =~ ^[0-9]+(\.[0-9]+)+$ ]]; then
      SM_LOAD_ERROR="manifest $file ${name}_tested_version is not plain numeric dotted form: $tested"
      return 1
    fi
    if [ "$(stack_version_compare "$min" "$tested")" = gt ]; then
      SM_LOAD_ERROR="manifest $file ${name}_min_version ($min) is greater than ${name}_tested_version ($tested)"
      return 1
    fi
  done

  if [ -n "$SM_LIBRARY_REPO$SM_LIBRARY_COMMIT$SM_LIBRARY_TREE$SM_LIBRARY_REF" ]; then
    if [ -z "$SM_LIBRARY_REPO" ] || [ -z "$SM_LIBRARY_COMMIT" ] || [ -z "$SM_LIBRARY_TREE" ]; then
      SM_LOAD_ERROR="manifest $file must set library_repo, library_commit and library_tree together (library_ref is optional)"
      return 1
    fi
    if [[ $SM_LIBRARY_REPO =~ [[:space:]] ]]; then
      SM_LOAD_ERROR="manifest $file library_repo must not contain whitespace"
      return 1
    fi
    # Never echo the value here: it may hold the very secret being refused.
    case $SM_LIBRARY_REPO in
      http://*|https://*)
        authority=${SM_LIBRARY_REPO#*://}; authority=${authority%%/*}
        case $authority in *@*)
          SM_LOAD_ERROR="manifest $file library_repo carries URL credentials; Git read access belongs to this machine's credential helper or SSH key, never the manifest"
          return 1
          ;;
        esac
        ;;
    esac
    if ! [[ $SM_LIBRARY_COMMIT =~ ^([0-9a-f]{40}|[0-9a-f]{64})$ ]]; then
      SM_LOAD_ERROR="manifest $file library_commit is not a full lowercase 40- or 64-hex object id: $SM_LIBRARY_COMMIT"
      return 1
    fi
    if ! [[ $SM_LIBRARY_TREE =~ ^([0-9a-f]{40}|[0-9a-f]{64})$ ]] || [ "${#SM_LIBRARY_TREE}" -ne "${#SM_LIBRARY_COMMIT}" ]; then
      SM_LOAD_ERROR="manifest $file library_tree is not a full lowercase hex object id of the same length as library_commit: $SM_LIBRARY_TREE"
      return 1
    fi
    if [ -n "$SM_LIBRARY_REF" ] && ! [[ $SM_LIBRARY_REF =~ ^refs/tags/[A-Za-z0-9._-]+$ ]]; then
      SM_LOAD_ERROR="manifest $file library_ref must be refs/tags/<name> (a fetch fallback, never the pin): $SM_LIBRARY_REF"
      return 1
    fi
  fi

  return 0
}

stack_version_extract() { # <raw text>
  local raw=${1:-}
  if [[ $raw =~ ([0-9]+(\.[0-9]+)+) ]]; then
    printf '%s' "${BASH_REMATCH[1]}"
  fi
}

stack_version_compare() { # <a> <b> -> lt|eq|gt
  local a=${1:-} b=${2:-}
  local -a pa pb
  IFS='.' read -r -a pa <<< "$a"
  IFS='.' read -r -a pb <<< "$b"
  local n=${#pa[@]} i ca cb
  [ "${#pb[@]}" -le "$n" ] || n=${#pb[@]}
  for ((i = 0; i < n; i++)); do
    ca=${pa[i]:-0}; cb=${pb[i]:-0}
    ca=$((10#$ca)); cb=$((10#$cb))
    if [ "$ca" -lt "$cb" ]; then printf lt; return; fi
    if [ "$ca" -gt "$cb" ]; then printf gt; return; fi
  done
  printf eq
}

stack_component_compat() { # <ver> <min> <tested> -> PASS|WARNING|FAIL|UNKNOWN
  local ver=${1:-} min=${2:-} tested=${3:-}
  if [ -z "$ver" ] || [ -z "$min" ] || [ -z "$tested" ]; then
    printf UNKNOWN
    return
  fi
  case $(stack_version_compare "$ver" "$min") in
    lt) printf FAIL; return ;;
  esac
  case $(stack_version_compare "$ver" "$tested") in
    gt) printf WARNING; return ;;
  esac
  printf PASS
}

stack_commit_relation() { # <repo> <baseline-full-sha> -> exact|descendant|ancestor|diverged|unknown
  local repo=$1 baseline=${2:-} head
  [ -n "$baseline" ] || { printf unknown; return; }
  head=$(git -C "$repo" rev-parse HEAD 2>/dev/null) || { printf unknown; return; }
  if [ "$head" = "$baseline" ]; then printf exact; return; fi
  git -C "$repo" cat-file -e "$baseline^{commit}" 2>/dev/null || { printf unknown; return; }
  if git -C "$repo" merge-base --is-ancestor "$baseline" HEAD 2>/dev/null; then
    printf descendant; return
  fi
  if git -C "$repo" merge-base --is-ancestor HEAD "$baseline" 2>/dev/null; then
    printf ancestor; return
  fi
  printf diverged
}

stack_library() { # <install|rollback|status> <data-home> <source-cache-repo>
  python3 - "$1" "$2" "$3" "$SM_LIBRARY_REPO" "$SM_LIBRARY_COMMIT" "$SM_LIBRARY_TREE" "$SM_LIBRARY_REF" <<'PY'
import fcntl, hashlib, json, os, re, shutil, signal, stat, subprocess, sys, time

MODE, D, CACHE, REPO, COMMIT, TREE, REF = sys.argv[1:8]
S = os.path.join(D, "firstmate-config")
POINTER = os.path.join(D, "agent-library")
VERSIONS = os.path.join(D, ".agent-library")
ANCHOR = os.path.join(S, "agent-library.lock")
RECEIPT = os.path.join(S, "agent-library.receipt")
SCHEMA = "fm-agent-library-receipt.v1"
PREFIX = ".agent-library/"
OID = re.compile(r"(?:[0-9a-f]{40}|[0-9a-f]{64})\Z")
TEMP = re.compile(r"\.agent-library-pointer\.tmp-[0-9]+\Z")
TOP = {"schema", "generation", "versions_dir", "versions", "pointer", "previous", "body_sha256"}
VKEYS = {"name", "commit", "tree", "dev", "ino", "verified_at"}
PKEYS = {"kind", "version", "temp_name", "text", "dev", "ino", "prior"}
UID = os.getuid()
CLOEXEC = getattr(os, "O_CLOEXEC", 0)


class Refuse(Exception):
    """A refusal: kind is "ownership" (unknown or changed state) or "corrupt"."""
    def __init__(self, msg, kind="ownership"):
        Exception.__init__(self, msg)
        self.kind = kind


class Run(object):
    fd = None            # the held lock anchor descriptor
    raw = None           # receipt bytes as this run last read or wrote them
    gen = None           # their generation (None: no receipt)
    own_temp = None      # (path, identity) of this run's temp pointer symlink
    own_staging = None   # (path, identity) of this run's not yet recorded export
    own_versions = None  # identity of D/.agent-library when this run created it
    switched = None      # the version the pointer was renamed to by this run


RUN = Run()


def say(kind, msg):
    print("%s %s" % (kind, msg), flush=True)


def short(c):
    return c[:12]


def lst(p):
    try:
        return os.lstat(p)
    except FileNotFoundError:
        return None


def idof(st):
    return {"dev": st.st_dev, "ino": st.st_ino}


def link_id(p):
    """The identity of whatever is at p (text None when it is no symlink)."""
    st = lst(p)
    if st is None:
        return None
    return {"text": os.readlink(p) if stat.S_ISLNK(st.st_mode) else None, "dev": st.st_dev, "ino": st.st_ino}


def nat(x):
    return isinstance(x, int) and not isinstance(x, bool) and x >= 0


def pointed(ptr):
    return ptr["text"][len(PREFIX):] if ptr else None


def find(r, name):
    for v in (r["versions"] if r else []):
        if v["name"] == name:
            return v
    return None


def checksum(r):
    body = {k: v for k, v in r.items() if k != "body_sha256"}
    return hashlib.sha256(json.dumps(body, sort_keys=True, separators=(",", ":")).encode()).hexdigest()


def durable(fd):
    try:
        fcntl.fcntl(fd, fcntl.F_FULLFSYNC)
    except (AttributeError, OSError):
        os.fsync(fd)


def durable_dir(path):
    fd = os.open(path, os.O_RDONLY | CLOEXEC)
    try:
        durable(fd)
    finally:
        os.close(fd)


def private_dir(path):
    st = lst(path)
    if st is None or not stat.S_ISDIR(st.st_mode) or st.st_uid != UID:
        raise Refuse("%s is not a directory owned by this user; nothing was changed" % path)


# --- receipt ------------------------------------------------------------------

def invalid(why):
    raise Refuse("receipt %s is invalid (%s); it was not changed or repaired - see docs/install.html" % (RECEIPT, why), "corrupt")


def no_duplicates(pairs):
    if len(pairs) != len({k for k, _ in pairs}):
        raise ValueError("duplicate key")
    return dict(pairs)


def no_constant(name):
    raise ValueError(name)


def read_raw():
    try:
        fd = os.open(RECEIPT, os.O_RDONLY | os.O_NOFOLLOW | CLOEXEC)
    except FileNotFoundError:
        return None
    except OSError as e:
        invalid("it cannot be opened as a regular file: %s" % e.strerror)
    try:
        st = os.fstat(fd)
        if not stat.S_ISREG(st.st_mode) or st.st_uid != UID:
            invalid("not a regular file owned by this user")
        chunks = []
        while True:
            b = os.read(fd, 1 << 16)
            if not b:
                return b"".join(chunks)
            chunks.append(b)
    finally:
        os.close(fd)


def validate(raw):
    try:
        r = json.loads(raw.decode("utf-8"), object_pairs_hook=no_duplicates, parse_constant=no_constant)
    except ValueError:
        invalid("not well-formed JSON")
    if not isinstance(r, dict) or set(r) - {"pending"} != TOP:
        invalid("unexpected or missing fields")
    if r["schema"] != SCHEMA:
        invalid("unknown schema")
    if r["body_sha256"] != checksum(r):
        invalid("checksum mismatch")
    if not nat(r["generation"]):
        invalid("generation")
    vd = r["versions_dir"]
    if not (isinstance(vd, dict) and set(vd) == {"dev", "ino"} and nat(vd["dev"]) and nat(vd["ino"])):
        invalid("versions_dir")
    if not isinstance(r["versions"], list):
        invalid("versions")
    names = []
    for v in r["versions"]:
        if not (isinstance(v, dict) and set(v) == VKEYS):
            invalid("version entry")
        if not (isinstance(v["commit"], str) and OID.match(v["commit"]) and v["name"] == v["commit"]):
            invalid("version name/commit")
        if not (isinstance(v["tree"], str) and OID.match(v["tree"]) and len(v["tree"]) == len(v["commit"])):
            invalid("version tree")
        if not (nat(v["dev"]) and nat(v["ino"]) and isinstance(v["verified_at"], str)):
            invalid("version identity")
        if v["name"] in names:
            invalid("duplicate version")
        names.append(v["name"])
    ptr = r["pointer"]
    if ptr is not None:
        if not (isinstance(ptr, dict) and set(ptr) == {"text", "dev", "ino"} and isinstance(ptr["text"], str)
                and nat(ptr["dev"]) and nat(ptr["ino"])):
            invalid("pointer")
        if not ptr["text"].startswith(PREFIX) or pointed(ptr) not in names:
            invalid("pointer names no recorded version")
    prev = r["previous"]
    if prev is not None and (ptr is None or prev not in names or prev == pointed(ptr)):
        invalid("previous")
    if "pending" in r:
        p = r["pending"]
        if not (isinstance(p, dict) and set(p) == PKEYS):
            invalid("pending")
        if p["kind"] not in ("update", "rollback") or p["version"] not in names:
            invalid("pending version")
        if p["text"] != PREFIX + p["version"]:
            invalid("pending text")
        if not (isinstance(p["temp_name"], str) and TEMP.match(p["temp_name"])):
            invalid("pending temp_name")
        if not (nat(p["dev"]) and nat(p["ino"])):
            invalid("pending identity")
        if p["prior"] != ptr:
            invalid("pending prior")
        if p["kind"] == "rollback" and p["version"] != prev:
            invalid("pending rollback version")
    return r


def read_receipt():
    RUN.raw = read_raw()
    r = validate(RUN.raw) if RUN.raw is not None else None
    RUN.gen = r["generation"] if r else None
    return r


def receipt_unchanged():
    """The on-disk receipt must still be exactly what this run last read or
    wrote; a change means a writer that ignored the lock interfered, and
    nothing more is written. Checked right before each receipt write and
    before an export is given its version name. The check and the following
    rename are two calls, so this detects earlier interference; it is not an
    atomic compare-and-swap."""
    now = read_raw()
    if now == RUN.raw:
        return
    if now is None:
        was = "now missing"
    else:
        try:
            was = "generation %s -> %s" % (RUN.gen, validate(now)["generation"])
        except Refuse:
            was = "now invalid"
    raise Refuse("receipt %s changed during this run (%s); stopped without writing it" % (RECEIPT, was))


def write_receipt(r):
    """Replace the receipt with r at the next generation: temp file, fsync,
    rename, directory fsync."""
    receipt_unchanged()
    body = {k: v for k, v in r.items() if k != "body_sha256"}
    body["generation"] = 1 if RUN.gen is None else RUN.gen + 1
    body["body_sha256"] = checksum(body)
    data = (json.dumps(body, sort_keys=True, indent=1) + "\n").encode()
    tmp = "%s.tmp-%d" % (RECEIPT, os.getpid())
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW | CLOEXEC, 0o600)
    try:
        try:
            view = memoryview(data)
            while view:
                view = view[os.write(fd, view):]
            durable(fd)
        finally:
            os.close(fd)
        os.replace(tmp, RECEIPT)
    except BaseException:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise
    durable_dir(S)
    RUN.raw, RUN.gen = data, body["generation"]
    return body


# --- ownership classification -----------------------------------------------

def classify(r):
    """Returns "fresh", "steady", "old" or "new" (pending: the live pointer is
    still the prior one, or already the switched one); refuses anything else."""
    live = link_id(POINTER)
    vst = lst(VERSIONS)
    if r is None:
        if live is None and vst is None:
            return "fresh"
        raise Refuse("%s exists but no receipt records it (unknown state); it was not adopted or changed - see docs/install.html"
                     % (POINTER if live is not None else VERSIONS))
    if vst is None or not stat.S_ISDIR(vst.st_mode) or idof(vst) != r["versions_dir"]:
        raise Refuse("%s is not the receipt-owned versions directory (missing, replaced or foreign); nothing was changed" % VERSIONS)
    for v in r["versions"]:
        st = lst(os.path.join(VERSIONS, v["name"]))
        if st is None or not stat.S_ISDIR(st.st_mode) or idof(st) != {"dev": v["dev"], "ino": v["ino"]}:
            raise Refuse("%s/%s is not the receipt-owned version (missing, replaced or foreign); nothing was changed"
                         % (VERSIONS, v["name"]))
    allowed = [r["pointer"]]
    p = r.get("pending")
    if p:
        allowed.append({"text": p["text"], "dev": p["dev"], "ino": p["ino"]})
    if live not in allowed:
        raise Refuse("%s is not the receipt-owned pointer (replaced, foreign or changed); it was not adopted or changed" % POINTER)
    if not p:
        return "steady"
    return "new" if live == allowed[1] else "old"


# --- integrity: rebuild the git tree id from the bytes on disk ----------------

def algo_for(oid):
    return "sha1" if len(oid) == 40 else "sha256"


def obj_id(kind, data, algo):
    h = hashlib.new(algo)
    h.update(kind + b" %d\0" % len(data))
    h.update(data)
    return h.hexdigest()


def file_id(path, algo):
    fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | CLOEXEC)
    try:
        size = os.fstat(fd).st_size
        h = hashlib.new(algo)
        h.update(b"blob %d\0" % size)
        seen = 0
        while True:
            b = os.read(fd, 1 << 20)
            if not b:
                break
            seen += len(b)
            h.update(b)
    finally:
        os.close(fd)
    if seen != size:
        raise Refuse("%s changed while it was being verified" % os.fsdecode(path), "corrupt")
    return h.hexdigest()


def tree_id(path, algo):
    path = os.fsencode(path)
    entries = []
    for name in os.listdir(path):
        full = os.path.join(path, name)
        st = os.lstat(full)
        if stat.S_ISDIR(st.st_mode):
            entries.append((name + b"/", b"40000", name, tree_id(full, algo)))
        elif stat.S_ISLNK(st.st_mode):
            entries.append((name, b"120000", name, obj_id(b"blob", os.readlink(full), algo)))
        elif stat.S_ISREG(st.st_mode):
            mode = b"100755" if st.st_mode & stat.S_IXUSR else b"100644"
            entries.append((name, mode, name, file_id(full, algo)))
        else:
            raise Refuse("%s is neither a file, a directory nor a symlink" % os.fsdecode(full), "corrupt")
    entries.sort()
    return obj_id(b"tree", b"".join(m + b" " + n + b"\0" + bytes.fromhex(o) for _, m, n, o in entries), algo)


def verify_version(v):
    path = os.path.join(VERSIONS, v["name"])
    if tree_id(path, algo_for(v["tree"])) != v["tree"]:
        raise Refuse("Agent Library version %s at %s no longer rebuilds its pinned tree %s; it was not changed or re-blessed"
                     % (short(v["name"]), path, short(v["tree"])), "corrupt")


def pinned_version(r):
    v = find(r, COMMIT)
    if v is not None and v["tree"] != TREE:
        raise Refuse("the manifest pins tree %s for %s but the receipt-owned version records %s; nothing was changed"
                     % (short(TREE), short(COMMIT), short(v["tree"])), "corrupt")
    return v


# --- the lock -----------------------------------------------------------------

def open_anchor(exclusive):
    flags = (os.O_RDWR | os.O_CREAT) if exclusive else os.O_RDONLY
    try:
        fd = os.open(ANCHOR, flags | os.O_NOFOLLOW | CLOEXEC, 0o600)
    except OSError as e:
        raise Refuse("lock anchor %s cannot be opened safely (%s); it was left alone" % (ANCHOR, e.strerror))
    st = os.fstat(fd)
    if not stat.S_ISREG(st.st_mode) or st.st_uid != UID or st.st_nlink != 1:
        os.close(fd)
        raise Refuse("lock anchor %s is not a private regular file of this user (hard-linked or foreign); it was left alone" % ANCHOR)
    return fd


def anchor_unchanged(fd):
    st, held = lst(ANCHOR), os.fstat(fd)
    if st is None or (st.st_dev, st.st_ino) != (held.st_dev, held.st_ino):
        raise Refuse("lock anchor %s changed while it was being locked; it was left alone" % ANCHOR)


def lock_exclusive():
    os.makedirs(D, exist_ok=True)
    if lst(S) is None:
        try:
            os.mkdir(S, 0o700)
        except FileExistsError:
            pass
    private_dir(S)
    fd = open_anchor(True)
    try:
        fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        raise Refuse("another installer holds the Agent Library lock %s; nothing was changed - rerun when it has finished" % ANCHOR)
    except OSError as e:
        raise Refuse("cannot lock %s (%s); an unlocked run is never attempted" % (ANCHOR, e.strerror))
    anchor_unchanged(fd)
    RUN.fd = fd


def lock_shared():
    """None: no installer ever wrote Library state here; "busy": an installer
    holds the lock; otherwise the held shared-lock descriptor."""
    if lst(S) is None:
        return None
    private_dir(S)
    if lst(ANCHOR) is None:
        return None
    fd = open_anchor(False)
    for attempt in range(5):
        try:
            fcntl.flock(fd, fcntl.LOCK_SH | fcntl.LOCK_NB)
            break
        except BlockingIOError:
            if attempt == 4:
                os.close(fd)
                return "busy"
            time.sleep(1)
        except OSError as e:
            raise Refuse("cannot lock %s (%s)" % (ANCHOR, e.strerror))
    anchor_unchanged(fd)
    return fd


# --- source, export, version --------------------------------------------------

def git(*args, **kw):
    return subprocess.run(["git", "--git-dir", CACHE] + list(args), stdout=subprocess.PIPE, stderr=subprocess.PIPE, **kw)


def rev(spec):
    r = git("rev-parse", "--verify", "--quiet", spec)
    return r.stdout.decode().strip() if r.returncode == 0 else None


def last_line(err):
    lines = [l.strip() for l in err.decode("utf-8", "replace").splitlines() if l.strip()]
    return re.sub(r"(://)[^/@\s]*@", r"\1***@", lines[-1]) if lines else "no error output"


def fetch_pinned(active):
    st = lst(CACHE)
    if st is None:
        os.makedirs(os.path.dirname(CACHE), exist_ok=True)
        r = subprocess.run(["git", "init", "--quiet", "--bare", CACHE], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        if r.returncode != 0:
            raise Refuse("cannot create the Agent Library source cache %s (%s)" % (CACHE, last_line(r.stderr)))
    elif not stat.S_ISDIR(st.st_mode) or git("rev-parse", "--is-bare-repository").stdout.strip() != b"true":
        raise Refuse("%s is not a bare Git repository; it was left alone" % CACHE)
    if rev(COMMIT + "^{commit}") is None:
        env = dict(os.environ, GIT_TERMINAL_PROMPT="0", GCM_INTERACTIVE="never")
        errors = []
        for spec in [COMMIT] + ([REF] if REF else []):
            r = git("fetch", "--quiet", "--no-tags", "--depth", "1", REPO, spec, env=env)
            if r.returncode == 0 and rev(COMMIT + "^{commit}") is not None:
                break
            errors.append(last_line(r.stderr) if r.returncode else "%s did not provide %s" % (spec, short(COMMIT)))
        else:
            raise Refuse("cannot fetch the pinned Agent Library %s from %s (%s); %s. A private source needs this machine's own Git read access - see docs/install.html"
                         % (short(COMMIT), REPO, errors[-1],
                            "the installed Library %s stays active and unchanged" % short(active) if active else "nothing was installed"))
    if rev(COMMIT + "^{commit}") != COMMIT:
        raise Refuse("the source cache does not hold commit %s; nothing was staged" % COMMIT)
    tree = rev(COMMIT + "^{tree}")
    if tree != TREE:
        raise Refuse("pinned commit %s has tree %s but the manifest pins %s; nothing was staged"
                     % (short(COMMIT), short(tree or "unknown"), short(TREE)), "corrupt")


def read_exact(stream, n):
    chunks = []
    while n:
        b = stream.read(n)
        if not b:
            raise Refuse("git cat-file ended early while exporting %s" % short(COMMIT), "corrupt")
        chunks.append(b)
        n -= len(b)
    return b"".join(chunks)


def export(dest):
    """Write every blob of the pinned tree under dest with exact bytes, the
    executable bit and symlink text; never follow anything it creates."""
    r = git("ls-tree", "-r", "-z", "--full-tree", COMMIT)
    if r.returncode != 0:
        raise Refuse("cannot list the pinned tree of %s (%s)" % (short(COMMIT), last_line(r.stderr)), "corrupt")
    entries = []
    for rec in r.stdout.split(b"\0"):
        if not rec:
            continue
        meta, path = rec.split(b"\t", 1)
        mode, kind, oid = meta.split(b" ")
        parts = path.split(b"/")
        if any(p in (b"", b".", b"..") or p.lower() == b".git" for p in parts):
            raise Refuse("the pinned tree has an unsafe path %r; nothing was installed" % path, "corrupt")
        if kind != b"blob" or mode not in (b"100644", b"100755", b"120000"):
            raise Refuse("the pinned tree entry %r has unsupported mode %s; nothing was installed" % (path, mode.decode()), "corrupt")
        entries.append((mode, oid, parts))
    cat = subprocess.Popen(["git", "--git-dir", CACHE, "cat-file", "--batch"], stdin=subprocess.PIPE, stdout=subprocess.PIPE)
    try:
        for mode, oid, parts in entries:
            cat.stdin.write(oid + b"\n")
            cat.stdin.flush()
            header = cat.stdout.readline().split()
            if len(header) != 3 or header[0] != oid or header[1] != b"blob":
                raise Refuse("git cat-file did not return blob %s" % oid.decode(), "corrupt")
            data = read_exact(cat.stdout, int(header[2]))
            read_exact(cat.stdout, 1)
            parent = os.fsencode(dest)
            for part in parts[:-1]:
                parent = os.path.join(parent, part)
                st = lst(parent)
                if st is None:
                    os.mkdir(parent, 0o755)
                elif not stat.S_ISDIR(st.st_mode):
                    raise Refuse("the pinned tree nests %r under a non-directory; nothing was installed" % b"/".join(parts), "corrupt")
            target = os.path.join(parent, parts[-1])
            if mode == b"120000":
                os.symlink(data, target)
                continue
            fd = os.open(target, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW | CLOEXEC, 0o600)
            try:
                view = memoryview(data)
                while view:
                    view = view[os.write(fd, view):]
                os.fchmod(fd, 0o755 if mode == b"100755" else 0o644)
                os.fsync(fd)
            finally:
                os.close(fd)
    finally:
        cat.stdin.close()
        cat.stdout.close()
        cat.wait()


def stage_and_record(r):
    """Export the pinned commit into a private staging directory, prove it
    rebuilds the pinned tree, rename it to its version name and record it in
    the receipt (write #1). Returns the new receipt."""
    if r is None:
        os.mkdir(VERSIONS, 0o700)
        RUN.own_versions = idof(os.lstat(VERSIONS))
    staging = os.path.join(VERSIONS, ".staging-%s-%d" % (COMMIT, os.getpid()))
    os.mkdir(staging, 0o700)
    RUN.own_staging = (staging, idof(os.lstat(staging)))
    export(staging)
    got = tree_id(staging, algo_for(TREE))
    if got != TREE:
        raise Refuse("the staged export of %s rebuilds tree %s, not the pinned %s; its staging directory was removed and nothing else changed"
                     % (short(COMMIT), short(got), short(TREE)), "corrupt")
    durable_dir(staging)
    receipt_unchanged()
    final = os.path.join(VERSIONS, COMMIT)
    if lst(final) is not None:
        raise Refuse("%s exists but the receipt does not record it; it was not adopted or reused" % final)
    os.rename(staging, final)
    RUN.own_staging = (final, RUN.own_staging[1])
    durable_dir(VERSIONS)
    st = os.lstat(final)
    entry = {"name": COMMIT, "commit": COMMIT, "tree": TREE, "dev": st.st_dev, "ino": st.st_ino,
             "verified_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())}
    if r is None:
        vst = os.lstat(VERSIONS)
        r = {"schema": SCHEMA, "versions_dir": idof(vst), "versions": [], "pointer": None, "previous": None}
    r = write_receipt(dict(r, versions=r["versions"] + [entry]))
    RUN.own_staging = None
    return r


# --- the atomic switch and its recovery ---------------------------------------

def switch(r, name, kind):
    """pending (write #2) -> identity re-checks -> atomic rename -> finalize
    (write #3). Returns the finalized receipt."""
    text = PREFIX + name
    temp_name = ".agent-library-pointer.tmp-%d" % os.getpid()
    temp = os.path.join(D, temp_name)
    os.symlink(text, temp)
    tid = link_id(temp)
    RUN.own_temp = (temp, tid)
    pending = {"kind": kind, "version": name, "temp_name": temp_name, "text": text,
               "dev": tid["dev"], "ino": tid["ino"], "prior": r["pointer"]}
    r = write_receipt(dict(r, pending=pending))
    v = find(r, name)
    vst = lst(os.path.join(VERSIONS, name))
    if link_id(POINTER) != r["pointer"] or vst is None or idof(vst) != {"dev": v["dev"], "ino": v["ino"]} \
            or idof(os.lstat(VERSIONS)) != r["versions_dir"] or link_id(temp) != tid:
        raise Refuse("the Agent Library pointer, version or versions directory changed before the switch; nothing was switched")
    anchor_unchanged(RUN.fd)
    os.replace(temp, POINTER)
    RUN.own_temp = None
    RUN.switched = name
    durable_dir(D)
    final = {k: x for k, x in r.items() if k != "pending"}
    final["pointer"] = {"text": text, "dev": tid["dev"], "ino": tid["ino"]}
    final["previous"] = pointed(r["pointer"])
    r = write_receipt(final)
    RUN.switched = None
    return r


def recover(r, phase):
    p = r["pending"]
    rest = {k: x for k, x in r.items() if k != "pending"}
    if phase == "new":
        verify_version(find(r, p["version"]))
        rest["pointer"] = {"text": p["text"], "dev": p["dev"], "ino": p["ino"]}
        rest["previous"] = pointed(p["prior"])
        r = write_receipt(rest)
        say("changed", "completed the interrupted switch of %s to %s" % (POINTER, short(p["version"])))
        return r
    r = write_receipt(rest)
    temp = os.path.join(D, p["temp_name"])
    if link_id(temp) == {"text": p["text"], "dev": p["dev"], "ino": p["ino"]}:
        os.unlink(temp)
    say("changed", "dropped an interrupted switch to %s that never reached %s" % (short(p["version"]), POINTER))
    return r


# --- modes --------------------------------------------------------------------

def absolute_data_home():
    if not os.path.isabs(D):
        raise Refuse("the Agent Library data home %r is not absolute (XDG_DATA_HOME must be an absolute path); nothing was changed" % D)


def install():
    absolute_data_home()
    lock_exclusive()
    r = read_receipt()
    phase = classify(r)
    if phase in ("old", "new"):
        r = recover(r, phase)
    current = pointed(r["pointer"]) if r else None
    v = pinned_version(r)
    if current == COMMIT:
        verify_version(v)
        say("ok", "Agent Library %s at %s (receipt-owned, tree verified)" % (short(COMMIT), POINTER))
        return
    if v is not None:
        verify_version(v)
    else:
        if lst(os.path.join(VERSIONS, COMMIT)) is not None:
            raise Refuse("%s exists but the receipt does not record it; it was not adopted or reused" % os.path.join(VERSIONS, COMMIT))
        fetch_pinned(current)
        r = stage_and_record(r)
    switch(r, COMMIT, "update")
    say("changed", "Agent Library %s installed at %s%s" % (short(COMMIT), POINTER,
                                                           " (previous %s retained)" % short(current) if current else ""))


def rollback():
    absolute_data_home()
    lock_exclusive()
    r = read_receipt()
    if r is None:
        classify(r)
        raise Refuse("no Agent Library was installed by this installer (no receipt); nothing to roll back")
    classify(r)
    if "pending" in r:
        raise Refuse("an interrupted switch is recorded; run install.sh (or fm update) first so it completes, then roll back")
    if r["pointer"] is None or r["previous"] is None:
        raise Refuse("no retained previous Agent Library version to roll back to")
    current, previous = pointed(r["pointer"]), r["previous"]
    verify_version(find(r, previous))
    switch(r, previous, "rollback")
    say("changed", "rolled %s back to the retained Agent Library %s (from %s); the next install.sh or fm update returns it to the pin %s"
        % (POINTER, short(previous), short(current), short(COMMIT)))


def emit(state, commit, msg):
    print("status\t%s\t%s\t%s" % (state, commit, msg), flush=True)


def status():
    absolute_data_home()
    held = lock_shared()
    if held == "busy":
        emit("busy", "-", "Agent Library update in progress (another installer holds %s)" % ANCHOR)
        return
    r = read_receipt()
    phase = classify(r)
    if phase in ("old", "new"):
        p = r["pending"]
        live = p["version"] if phase == "new" else (pointed(p["prior"]) or "-")
        emit("pending", live, "Agent Library receipt finalize pending: an interrupted switch to %s awaits completion; rerun install.sh or fm update"
             % short(p["version"]))
        return
    current = pointed(r["pointer"]) if r else None
    if current is None:
        emit("not_installed", "-", "Agent Library %s is not installed at %s" % (short(COMMIT), POINTER))
        return
    verify_version(find(r, current))
    if current == COMMIT:
        pinned_version(r)
        emit("healthy", current, "Agent Library %s at %s (pinned, receipt-owned, tree verified)" % (short(current), POINTER))
    else:
        emit("differs", current, "Agent Library installed %s != pin %s" % (short(current), short(COMMIT)))


def recorded(ident):
    """Whether the receipt on disk now records a version with this identity. A
    receipt that cannot be read safely counts as recording it."""
    try:
        raw = read_raw()
        r = validate(raw) if raw is not None else None
    except Refuse:
        return True
    return r is not None and any(ident == {"dev": v["dev"], "ino": v["ino"]} for v in r["versions"])


def cleanup():
    """Remove only what this run itself created and nothing has recorded. The
    published receipt decides, not this run's bookkeeping: an interrupt can
    land after a receipt write was published but before the run noted it, and
    a recorded version is committed state that is never removed."""
    try:
        if RUN.own_temp and link_id(RUN.own_temp[0]) == RUN.own_temp[1]:
            os.unlink(RUN.own_temp[0])
        if RUN.own_staging:
            st = lst(RUN.own_staging[0])
            if st is not None and stat.S_ISDIR(st.st_mode) and idof(st) == RUN.own_staging[1] \
                    and not recorded(RUN.own_staging[1]):
                shutil.rmtree(RUN.own_staging[0])
        if RUN.own_versions and RUN.raw is None:
            st = lst(VERSIONS)
            if st is not None and idof(st) == RUN.own_versions and not os.listdir(VERSIONS):
                os.rmdir(VERSIONS)
    except OSError as e:
        say("warn", "could not remove this run's own temporary Agent Library entries: %s" % e)


def switched_note():
    if not RUN.switched:
        return ""
    return ("; %s already names the verified Agent Library %s, the previous version is retained, and the receipt still records the switch as pending - rerun install.sh (or fm update) to finish it"
            % (POINTER, short(RUN.switched)))


def interrupted(signum, frame):
    raise KeyboardInterrupt()


signal.signal(signal.SIGTERM, interrupted)
signal.signal(signal.SIGHUP, interrupted)
try:
    {"install": install, "rollback": rollback, "status": status}[MODE]()
except Refuse as e:
    if MODE == "status":
        emit(e.kind, "-", str(e))
    else:
        cleanup()
        say("fail", str(e) + switched_note())
except (Exception, KeyboardInterrupt) as e:
    if MODE == "status":
        emit("ownership", "-", "Agent Library state could not be read: %s" % e)
    else:
        cleanup()
        say("fail", "Agent Library step stopped: %s%s" % (str(e) or type(e).__name__, switched_note()))
PY
}

stack_library_runtime() { # <data-home>
  if [ -n "${AGENT_LIBRARY_ROOT+set}" ]; then
    SL_RUNTIME_MODE=explicit SL_RUNTIME_ROOT=$AGENT_LIBRARY_ROOT
  else
    SL_RUNTIME_MODE=default SL_RUNTIME_ROOT="$1/agent-library"
  fi
  if [ -z "$SL_RUNTIME_ROOT" ]; then
    SL_RUNTIME_REASON='AGENT_LIBRARY_ROOT is exported empty'
  elif [ ! -f "$SL_RUNTIME_ROOT/library/bin/agent-library.ts" ]; then
    SL_RUNTIME_REASON="no library/bin/agent-library.ts under $SL_RUNTIME_ROOT"
  elif ! command -v bun >/dev/null 2>&1; then
    SL_RUNTIME_REASON='bun is not on PATH'
  else
    SL_RUNTIME_REASON=
  fi
}

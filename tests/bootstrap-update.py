#!/usr/bin/env python3
"""Actual updater transitions; no network, live HOME, installer or credentials.

Catches adoption without two-repo preflight, lost branches/remotes, default-main
selection, partial-success claims, and the old-updater bootstrap reachability gap.
Transport-only Git shim allows file fixtures; configured/effective URLs stay real.
"""
import html
import hashlib
import shlex
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
FORK = 'https://github.com/inkayat/firstmate.git'
OFFICIAL = 'https://github.com/kunchenguid/firstmate.git'
CONFIG = 'https://github.com/inkayat/firstmate-config.git'
REAL_GIT = shutil.which('git')
BASE = '37694a817eacc3747d44e45acd7935c8d312b4c5'


def run(*args, env=None, ok=True):
    p = subprocess.run([str(a) for a in args], env=env, text=True,
                       stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    if ok and p.returncode:
        raise AssertionError(f'{args}: {p.returncode}\n{p.stdout}')
    return p


with tempfile.TemporaryDirectory(prefix='fm-bootstrap-') as tmp:
    T = Path(tmp).resolve()
    home = T / 'home'
    home.mkdir()
    tools = T / 'tools'
    tools.mkdir()
    # No inherited environment, Git configuration, SSH agent or provider tokens.
    E = dict(HOME=str(home), PATH=f'{tools}:/usr/bin:/bin',
             GIT_CONFIG_NOSYSTEM='1', GIT_CONFIG_GLOBAL='/dev/null',
             GIT_ALLOW_PROTOCOL='file', GIT_TERMINAL_PROMPT='0',
             GIT_AUTHOR_NAME='Fixture', GIT_AUTHOR_EMAIL='fixture@example.invalid',
             GIT_COMMITTER_NAME='Fixture', GIT_COMMITTER_EMAIL='fixture@example.invalid',
             FM_CONFIG_ENV='/dev/null', REAL_GIT=REAL_GIT, FIXTURE_ROOT=str(T),
             TRANSPORT_LOG=str(T / 'transport.log'))
    E['TMPDIR'] = str(T)
    (tools / 'git').write_text('''#!/bin/bash
set -eu
# Only fixture repositories and file transports. Reject all writes to remotes.
root=; args=("$@")
if [ "${1:-}" = -C ]; then root=$2; shift 2; fi
case ${1:-} in check-ref-format) exec "$REAL_GIT" "$@" ;; esac
case $root in "$FIXTURE_ROOT"/*) ;; *) echo "nonfixture Git root: $root" >&2; exit 96 ;; esac
if [ "${1:-}" = ls-remote ] && [ "${2:-}" = --get-url ]; then exec "$REAL_GIT" "${args[@]}"; fi
if [ "${INJECT_STAGE:-}" = config-merge ] && [ "$root" = "${INJECT_CONFIG:-}" ] && [ "${1:-}" = merge ]; then
  echo 'injected second-repo merge failure' >&2; exit 91
fi
if [ "${INJECT_STAGE:-}" = interrupt ] && [ "$root" = "${INJECT_SOURCE:-}" ] && [ "${1:-}" = checkout ]; then
  kill -TERM "$PPID"; exit 92
fi
if [ "${INJECT_STAGE:-}" = remote-adoption ] && [ "$root" = "${INJECT_SOURCE:-}" ] && [ "${1:-}" = remote ] && [ "${3:-}" = origin ]; then
  case ${2:-} in add|set-url) kill -TERM "$PPID"; exit 93 ;; esac
fi
case ${1:-} in
 push|pull) echo forbidden >&2; exit 96 ;;
 fetch|ls-remote)
  printf '%s\\n' "$*" >> "$TRANSPORT_LOG"
  shift
  extra=()
  while [ "${1#-}" != "$1" ]; do extra+=("$1"); shift; done
  remote=$1; shift
  case $remote in
   origin) url=$("$REAL_GIT" -C "$root" config remote.origin.url) ;;
   *) url=$remote ;;
  esac
  case $url in
   https://github.com/inkayat/firstmate.git) dest=$FIXTURE_ROOT/fork.git ;;
   https://github.com/kunchenguid/firstmate.git) dest=$FIXTURE_ROOT/official.git ;;
   https://github.com/inkayat/firstmate-config.git) dest=$FIXTURE_ROOT/config.git ;;
   *) echo "forbidden transport: $url" >&2; exit 96 ;;
  esac
  if [ "$remote" = origin ] && [ "$#" -eq 0 ]; then
    set -- refs/heads/main:refs/remotes/origin/main
  fi
  exec "$REAL_GIT" -C "$root" "${args[2]}" "${extra[@]}" "$dest" "$@" ;;
esac
exec "$REAL_GIT" "${args[@]}"
''')
    (tools / 'git').chmod(0o755)
    for name in ('pi', 'omp', 'herdr'):
        (tools / name).write_text('#!/bin/sh\nexit 97 # must never run a runtime\n')
        (tools / name).chmod(0o755)

    def git(repo, *args):
        return run(REAL_GIT, '-C', repo, *args, env=E).stdout.strip()

    def init(repo):
        repo.mkdir()
        git(repo, 'init', '-q', '-b', 'main')

    def commit(repo, text):
        git(repo, 'add', '.')
        git(repo, 'commit', '-qm', text)
        return git(repo, 'rev-parse', 'HEAD')

    source = T / 'seed'
    init(source)
    (source / 'AGENTS.md').write_text('fixture official\n')
    official_pin = commit(source, 'official')
    run(REAL_GIT, 'clone', '-q', '--bare', source, T / 'official.git', env=E)
    (source / 'generic-skill-fix').write_text('fixture generic fix\n')
    pin = commit(source, 'generic fix')
    git(source, 'branch', 'inkayat-main')
    run(REAL_GIT, 'clone', '-q', '--bare', source, T / 'fork.git', env=E)
    # Fork default main deliberately remains official: must not select it.
    git(T / 'fork.git', 'update-ref', 'refs/heads/main', official_pin)
    cfg = T / 'candidate'
    init(cfg)
    (cfg / 'bin').mkdir()
    (cfg / 'firstmate').mkdir()
    for name in ('bin/fm-update', 'firstmate/fm-stack-manifest.sh'):
        shutil.copy2(ROOT / name, cfg / name)
    helper = ROOT / 'firstmate/fm-update-migration.sh'
    if helper.exists():
        shutil.copy2(helper, cfg / 'firstmate' / helper.name)
    manifest = (ROOT / 'firstmate/stack-manifest.tsv').read_text()
    manifest = '\n'.join('firstmate_validated_commit\t' + pin if row.startswith('firstmate_validated_commit\t') else row for row in manifest.splitlines()) + '\n'
    (cfg / 'firstmate/stack-manifest.tsv').write_text(manifest)
    (cfg / 'install.sh').write_text('''#!/bin/bash
set -eu
case $HOME in "$FIXTURE_ROOT"/*) ;; *) exit 96 ;; esac
[ "${FAIL_INSTALL:-0}" != 1 ] || exit 9
mkdir -p "$HOME/machine"
printf '%s\\n' "${1:-install}" >> "$HOME/machine/install-log"
if [ "${1:-}" = --verify ]; then echo 'verify: 0 drift item(s), 0 failure(s)'; fi
''')
    (cfg / 'install.sh').chmod(0o755)
    # Real historical updater/parser/manifest, in a fixture-only revision.
    candidate_files = {p.relative_to(cfg): p.read_bytes() for p in cfg.rglob('*') if p.is_file() and '.git' not in p.parts}
    for name in ('bin/fm-update', 'firstmate/fm-stack-manifest.sh', 'firstmate/stack-manifest.tsv'):
        (cfg / name).write_text(run(REAL_GIT, '-C', ROOT, 'show', f'{BASE}:{name}').stdout)
    old_pin = commit(cfg, 'historical installed config')
    for name, data in candidate_files.items():
        (cfg / name).write_bytes(data)
    candidate_pin = commit(cfg, 'candidate bootstrap')
    git(cfg, 'remote', 'add', 'origin', CONFIG)
    run(REAL_GIT, 'clone', '-q', '--bare', cfg, T / 'config.git', env=E)

    def pair(name, layout='official', old=True):
        c, f = T / f'{name}-config', T / f'{name}-source'
        run(REAL_GIT, 'clone', '-q', T / 'config.git', c, env=E)
        git(c, 'remote', 'set-url', 'origin', CONFIG)
        if old:
            # Recreate the actual historical installed branch without discarding work.
            git(c, 'checkout', '-qb', 'installed', old_pin)
            git(c, 'branch', '-D', 'main')  # fixture setup only, never migration
            git(c, 'branch', '-m', 'main')
            git(c, 'branch', '-u', 'origin/main')
        run(REAL_GIT, 'clone', '-q', T / ('official.git' if layout == 'official' else 'fork.git'), f, env=E)
        git(f, 'remote', 'set-url', 'origin', OFFICIAL if layout == 'official' else FORK)
        if layout != 'official':
            git(f, 'checkout', '-qb', 'fixed-main', pin)
            git(f, 'branch', '-D', 'main')
            git(f, 'branch', '-m', 'main')
            git(f, 'config', 'branch.main.remote', 'origin')
            git(f, 'config', 'branch.main.merge', 'refs/heads/main')
            git(f, 'remote', 'add', 'upstream', OFFICIAL)
        git(f, 'remote', 'add', 'devrepo', str(T / 'unused-preserved'))
        return c, f

    def invoke(c, f, *args, script=None, extra=None):
        env = dict(E, FIRSTMATE_ROOT=str(f))
        env.update(extra or {})
        p = run('/bin/bash', script or c / 'bin/fm-update', *args, env=env, ok=False)
        print(f'COMMAND {Path(script or c / "bin/fm-update").name} {args}: exit {p.returncode}\n{p.stdout}', flush=True)
        return p

    c, f = pair('old-blocked', 'fork')
    p = invoke(c, f)
    assert p.returncode and 'expected exactly' in p.stdout
    assert git(c, 'rev-parse', 'HEAD') == old_pin
    assert not (T / 'transport.log').exists(), 'origin guard must precede fetching config'
    # One-condition counterfactual: origin only. Guard moves to unlanded fix.
    git(f, 'remote', 'set-url', 'origin', OFFICIAL)
    p = invoke(c, f)
    assert p.returncode and 'unlanded work' in p.stdout
    assert git(c, 'rev-parse', 'HEAD') == old_pin
    # Disconfirm overbroad claim that every old updater refuses before config fetch.
    c, f = pair('old-clean')
    p = invoke(c, f)
    assert p.returncode == 0
    assert git(c, 'rev-parse', 'HEAD') == candidate_pin
    assert git(f, 'remote', 'get-url', 'origin') == OFFICIAL
    p = invoke(c, f, '--check')
    assert p.returncode and 'expected exactly' in p.stdout, 'old successful update is not migration'
    print('PASS old blocker, one-condition counterfactual and disconfirming clean-official path')
    new_transport_offset = (T / 'transport.log').stat().st_size

    for layout in ('official', 'fork'):
        c, f = pair('bootstrap-' + layout, layout)
        old_head = git(f, 'rev-parse', 'main')
        p = invoke(c, f, '--bootstrap', c, script=cfg / 'bin/fm-update')
        assert p.returncode == 0, 'bootstrap must migrate, update, install and verify'
        assert git(c, 'rev-parse', 'HEAD') == candidate_pin
        assert git(f, 'rev-parse', 'HEAD') == pin
        assert git(f, 'rev-parse', 'main') == old_head
        assert git(f, 'remote', 'get-url', 'origin') == FORK
        assert git(f, 'remote', 'get-url', 'upstream') == OFFICIAL
        assert git(f, 'remote', 'get-url', 'devrepo') == str(T / 'unused-preserved')
        assert git(f, 'symbolic-ref', '--short', 'HEAD') == 'inkayat-main'
        assert git(f, 'symbolic-ref', '--short', 'refs/remotes/origin/HEAD') == 'origin/inkayat-main'
        p = invoke(c, f, '--check')
        assert p.returncode == 0 and 'UPDATE_BRANCH: inkayat-main' in p.stdout
        before = git(f, 'show-ref')
        assert invoke(c, f, '--migrate').returncode == 0
        assert git(f, 'show-ref') == before
        assert invoke(c, f).returncode == 0
        print('PASS bootstrap, native branch resolution, idempotent migration, normal update:', layout)
    c, f = pair('new-updater-legacy', old=False)
    git(f, 'remote', 'add', 'upstream', OFFICIAL)
    assert invoke(c, f, '--migrate').returncode == 0
    assert git(f, 'rev-parse', 'HEAD') == pin
    assert git(f, 'config', 'branch.main.remote') == 'upstream'
    print('PASS already-installed new updater migrates official origin with existing upstream')

    # Execute the documented single command, including acquisition, exact
    # revision checkout, operator approval and the actual updater interface.
    doc = (ROOT / 'docs/update.html').read_text()
    command = html.unescape(doc.split('<pre data-label="one-time bootstrap command"><code>', 1)[1].split('</code></pre>', 1)[0])
    argv = shlex.split(command)
    for layout in ('official', 'fork'):
        c, f = pair('documented-' + layout, layout)
        args = argv[:-2] + [candidate_pin, str(c)]
        p = subprocess.run(args, env=dict(E, FIRSTMATE_ROOT=str(f)),
                           input=candidate_pin + '\n', text=True,
                           stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        print(f'DOCUMENTED COMMAND {layout}: exit {p.returncode}\n{p.stdout}')
        assert p.returncode == 0
        assert git(c, 'rev-parse', 'HEAD') == candidate_pin
        assert git(f, 'symbolic-ref', '--short', 'HEAD') == 'inkayat-main'
        assert git(f, 'rev-parse', 'HEAD') == pin
        print('PASS documented one-command transition:', layout)

    def snapshot(repo):
        return (git(repo, 'rev-parse', 'HEAD'),
                git(repo, 'symbolic-ref', 'HEAD'),
                git(repo, 'config', '--local', '--list'),
                git(repo, 'for-each-ref', 'refs/heads'),
                git(repo, 'status', '--porcelain', '--untracked-files=all'),
                tuple(sorted((str(p.relative_to(repo)), hashlib.sha256(p.read_bytes()).hexdigest())
                             for p in repo.rglob('*') if p.is_file() and '.git' not in p.parts)))
    for supplied, approval in ((candidate_pin, 'not-approved'), ('APPROVED_FULL_CONFIG_COMMIT', candidate_pin)):
        c, f = pair('unapproved-' + supplied[:8])
        before = (snapshot(c), snapshot(f))
        p = subprocess.run(argv[:-2] + [supplied, str(c)], env=dict(E, FIRSTMATE_ROOT=str(f)),
                           input=approval + '\n', text=True,
                           stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        assert p.returncode and (snapshot(c), snapshot(f)) == before
        print('PASS documented command refuses missing revision/approval without installed changes')

    # Mutations catch missing preflight, not incidental output wording.
    for case in ('dirty-source', 'untracked-config', 'unlanded-source',
                 'unlanded-config', 'diverged-source', 'conflicting-upstream',
                 'conflicting-branch', 'wrong-origin', 'wrong-config-origin',
                 'wrong-tracking', 'unfinished-config', 'missing-tool',
                 'ignored-user-file', 'explicit-pushurl', 'bootstrap-self', 'fork-url-rewrite',
                 'missing-origin', 'missing-origin-upstream'):
        c, f = pair(case, 'fork' if case == 'unlanded-source' else 'official',
                    old=(case != 'unlanded-config'))
        extra = {}
        script = cfg / 'bin/fm-update'
        if case == 'bootstrap-self':
            c, f = pair('self-target', old=False)
            script = c / 'bin/fm-update'
        if case == 'dirty-source':
            (f / 'AGENTS.md').write_text('user edit')
        elif case == 'untracked-config':
            (c / 'user-content').write_text('do not delete')
        elif case in ('unlanded-source', 'diverged-source', 'conflicting-branch'):
            (f / 'local-work').write_text('unpublished')
            commit(f, 'local only')
            if case == 'conflicting-branch':
                git(f, 'branch', 'inkayat-main')
                git(f, 'checkout', '-qb', 'clean-main', official_pin)
                git(f, 'config', 'branch.clean-main.remote', 'origin')
                git(f, 'config', 'branch.clean-main.merge', 'refs/heads/main')
                git(f, 'branch', '-m', 'main', 'preserved-local-main')
                git(f, 'branch', '-m', 'main')
            elif case == 'diverged-source':
                (f / 'generic-skill-fix').write_text('competing change')
                commit(f, 'divergent')
        elif case == 'unlanded-config':
            (c / 'local-work').write_text('unpublished')
            commit(c, 'local only')
        elif case == 'conflicting-upstream':
            git(f, 'remote', 'add', 'upstream', 'https://example.invalid/unknown')
        elif case == 'wrong-origin':
            git(f, 'remote', 'set-url', 'origin', 'https://example.invalid/unknown')
        elif case == 'wrong-config-origin':
            git(c, 'remote', 'set-url', 'origin', 'https://example.invalid/config')
        elif case == 'wrong-tracking':
            git(f, 'config', 'branch.main.merge', 'refs/heads/topic')
        elif case == 'unfinished-config':
            (c / '.git/MERGE_HEAD').write_text(old_pin + '\n')
        elif case == 'missing-tool':
            (tools / 'herdr').rename(tools / 'herdr-hidden')
        elif case == 'ignored-user-file':
            (f / '.git/info/exclude').write_text('generic-skill-fix\n')
            (f / 'generic-skill-fix').write_text('ignored user content')
        elif case == 'explicit-pushurl':
            git(f, 'config', 'remote.origin.pushurl', 'https://example.invalid/preserve')
        elif case == 'fork-url-rewrite':
            git(f, 'config', 'url.https://example.invalid/redirect.insteadOf', FORK)
        elif case in ('missing-origin', 'missing-origin-upstream'):
            git(f, 'remote', 'remove', 'origin')
            if case == 'missing-origin-upstream':
                git(f, 'remote', 'add', 'upstream', OFFICIAL)
                git(f, 'config', 'branch.main.remote', 'upstream')
                git(f, 'config', 'branch.main.merge', 'refs/heads/main')
                git(f, 'update-ref', 'refs/remotes/upstream/main', official_pin)
        before = (snapshot(c), snapshot(f))
        p = invoke(c, f, '--bootstrap', c, script=script, extra=extra)
        assert p.returncode != 0, case
        assert 'fm update complete' not in p.stdout
        assert (snapshot(c), snapshot(f)) == before, f'{case} changed persistent work/remotes'
        if case == 'missing-tool':
            (tools / 'herdr-hidden').rename(tools / 'herdr')
        print('PASS preflight refusal preserves both repositories:', case)

    for stage in ('config-merge', 'interrupt', 'install'):
        c, f = pair('partial-' + stage)
        extra = dict(INJECT_STAGE=stage, INJECT_CONFIG=str(c),
                     INJECT_SOURCE=str(f), FAIL_INSTALL='1' if stage == 'install' else '0')
        old_main = git(f, 'rev-parse', 'main')
        p = invoke(c, f, '--bootstrap', c, script=cfg / 'bin/fm-update', extra=extra)
        assert p.returncode and 'PARTIAL MIGRATION' in p.stdout
        assert 'fm update complete' not in p.stdout
        assert git(f, 'rev-parse', 'main') == old_main
        assert git(f, 'remote', 'get-url', 'upstream') == OFFICIAL
        assert git(c, 'rev-parse', 'HEAD') == (candidate_pin if stage == 'install' else old_pin)
        assert invoke(c, f, '--bootstrap', c, script=cfg / 'bin/fm-update').returncode == 0
        print('PASS partial progress reported and same-command retry succeeds:', stage)
    c, f = pair('remote-adoption-gap')
    git(c, 'branch', 'retained-config', old_pin)
    git(f, 'branch', 'retained-official')
    git(f, 'config', 'branch.retained-official.remote', 'origin')
    git(f, 'config', 'branch.retained-official.merge', 'refs/heads/main')
    git(f, 'fetch', T / 'fork.git', 'refs/heads/inkayat-main')
    git(f, 'branch', 'inkayat-main', pin)
    git(f, 'config', 'branch.inkayat-main.remote', 'origin')
    git(f, 'config', 'branch.inkayat-main.merge', 'refs/heads/inkayat-main')
    old_source_tip = git(f, 'rev-parse', 'main')
    old_source_bytes = {str(p.relative_to(f)): p.read_bytes()
                        for p in f.rglob('*') if p.is_file() and '.git' not in p.parts}
    args = argv[:-2] + [candidate_pin, str(c)]
    interrupted = subprocess.run(args, env=dict(E, FIRSTMATE_ROOT=str(f),
                                               INJECT_STAGE='remote-adoption', INJECT_SOURCE=str(f)),
                                 input=candidate_pin + '\n', text=True,
                                 stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    print(f'EXACT REMOTE ADOPTION INTERRUPTION: exit {interrupted.returncode}\n{interrupted.stdout}')
    print('INTERRUPTED SNAPSHOT', snapshot(c), snapshot(f), flush=True)
    assert interrupted.returncode and 'PARTIAL MIGRATION' in interrupted.stdout
    assert 'fm update complete' not in interrupted.stdout
    assert git(c, 'rev-parse', 'HEAD') == old_pin
    assert git(f, 'rev-parse', 'main') == old_source_tip
    assert git(f, 'remote', 'get-url', 'origin') == OFFICIAL
    assert git(f, 'remote', 'get-url', 'upstream') == OFFICIAL
    assert git(f, 'rev-parse', 'retained-official@{upstream}') == official_pin
    assert git(f, 'config', 'branch.inkayat-main.remote') == 'origin'
    retry = subprocess.run(args, env=dict(E, FIRSTMATE_ROOT=str(f)),
                           input=candidate_pin + '\n', text=True,
                           stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    print(f'IDENTICAL DOCUMENTED COMMAND RETRY: exit {retry.returncode}\n{retry.stdout}', flush=True)
    assert retry.returncode == 0, 'own interrupted remote adoption must be retryable'
    assert git(f, 'rev-parse', 'main') == old_source_tip
    assert git(f, 'rev-parse', 'retained-official') == old_source_tip
    assert git(f, 'config', 'branch.main.remote') == 'upstream'
    assert git(f, 'config', 'branch.retained-official.remote') == 'upstream'
    assert git(f, 'rev-parse', 'retained-official@{upstream}') == official_pin
    assert git(f, 'remote', 'get-url', 'origin') == FORK
    assert git(f, 'remote', 'get-url', 'upstream') == OFFICIAL
    assert git(f, 'remote', 'get-url', 'devrepo') == str(T / 'unused-preserved')
    assert git(c, 'rev-parse', 'retained-config') == old_pin
    assert git(c, 'rev-parse', 'HEAD') == candidate_pin
    assert git(f, 'symbolic-ref', '--short', 'refs/remotes/origin/HEAD') == 'origin/inkayat-main'
    assert git(f, 'rev-parse', 'inkayat-main') == pin
    assert git(f, 'config', 'branch.inkayat-main.remote') == 'origin'
    assert all((f / name).read_bytes() == content for name, content in old_source_bytes.items())
    print('PASS exact remote-adoption interruption and identical single-command retry preserve branch tips/tracking/connections/user bytes')
    new_transports = (T / 'transport.log').read_text()[new_transport_offset:]
    assert OFFICIAL not in new_transports, 'migration must never contact official'
    assert 'upstream' not in new_transports
    # Protocol denial is independently exercised, not inferred from URL strings.
    denied = run(REAL_GIT, '-C', cfg, 'ls-remote', 'https://example.invalid/forbidden', env=E, ok=False)
    assert denied.returncode and 'not allowed' in denied.stdout
    print('PASS containment: file-only Git, sanitized env, fixture HOME/roots, runtime execution denied')

    print('BOOTSTRAP TRANSITION TESTS PASSED')

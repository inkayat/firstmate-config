#!/usr/bin/env python3
"""Apply/status/revert seven temporary additions; explicit source roots, no install.

Run from a frozen preparation checkout. Destination revisions remain unchanged.
All selected targets are preflighted before any write. Do not run concurrently
with source edits, installation or updates. Revert removes only exact owned bytes.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile

HERE = Path(__file__).resolve().parent
CONFIG_SOURCE = HERE.parents[1]
TOKEN = b"FM-LIVE-PROBE"


def digest(body):
    return hashlib.sha256(body).hexdigest()


def git(root, *args):
    return subprocess.check_output(["git", "-C", str(root), *args], stderr=subprocess.PIPE).decode().strip()


def source_path(root, relative):
    path = root / relative
    if path.is_symlink() or not path.resolve().is_relative_to(root):
        raise ValueError(f"source path must be a regular file within its explicit root: {path}")
    if not path.is_file():
        raise ValueError(f"source file missing: {path}")
    return path


def owned_block(source):
    begin = f'<!-- BEGIN FM-LIVE-PROBE {source["id"]} (temporary) -->\n'.encode()
    end = f'<!-- END FM-LIVE-PROBE {source["id"]} (temporary) -->\n'.encode()
    if "canonical" in source:
        canonical = source_path(CONFIG_SOURCE, source["canonical"]).read_bytes()
        start = canonical.find(b"\n" + begin)
        if start < 0:
            raise ValueError(f"frozen canonical addition missing: {source['canonical']}")
        block = canonical[start:]
        if digest(canonical[:start]) != source["sha256"]:
            raise ValueError(f"frozen canonical baseline mismatch: {source['canonical']}")
    else:
        block = source_path(HERE, source["addition"]).read_bytes()
    if not block.startswith(b"\n" + begin) or not block.endswith(end) or block.count(TOKEN) != 2:
        raise ValueError(f"invalid frozen marker data: {source['id']}")
    return block


def inspect(body, block, label):
    if TOKEN not in body:
        return "absent", body
    if body.count(TOKEN) != 2 or body.count(block) != 1:
        raise ValueError(f"unexpected, partial, duplicated or altered marker/body: {label}")
    return "applied", body.replace(block, b"", 1)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=["apply", "status", "revert"])
    for name in ("config", "superpowers", "addy"):
        parser.add_argument(f"--{name}-root", type=Path)
    parser.add_argument("--only", choices=["config", "superpowers", "addy"], nargs="+",
                        default=["config", "superpowers", "addy"])
    args = parser.parse_args()
    manifest = json.loads((HERE / "source-manifest.json").read_text())
    selected = set(args.only)
    roots = {}
    for name in selected:
        supplied = getattr(args, f"{name}_root")
        if supplied is None:
            raise ValueError(f"--{name}-root is required for selected source")
        root = supplied.resolve(strict=True)
        if Path(git(root, "rev-parse", "--show-toplevel")).resolve() != root:
            raise ValueError(f"explicit root is not a Git top level: {root}")
        expected = next(s["revision"] for s in manifest["sources"] if s["root"] == name)
        actual = git(root, "rev-parse", "HEAD")
        if actual != expected:
            raise ValueError(f"revision mismatch for {name}: expected {expected}, got {actual}")
        roots[name] = root
    plan = []
    for source in manifest["sources"]:
        if source["root"] not in selected:
            continue
        path = source_path(roots[source["root"]], source["path"])
        block = owned_block(source)
        before = path.read_bytes()
        state, baseline = inspect(before, block, path)
        # Revert owns only the exact block, never unrelated surrounding edits.
        if args.action != "revert" and digest(baseline) != source["sha256"]:
            raise ValueError(f"baseline mismatch: {path}; no writes; revert can preserve surrounding edits")
        after = baseline if args.action == "revert" else baseline + block
        plan.append((path, before, after, state))
    if args.action != "revert":
        for companion in manifest["companions"]:
            if companion["root"] in selected:
                path = source_path(roots[companion["root"]], companion["path"])
                if digest(path.read_bytes()) != companion["sha256"]:
                    raise ValueError(f"referenced companion mismatch: {path}")
    if args.action != "status":
        for path, before, after, state in plan:
            if path.read_bytes() != before:
                raise ValueError(f"source changed during preflight: {path}")
        for path, before, after, state in plan:
            if before == after:
                continue
            if path.read_bytes() != before:
                raise ValueError(f"source changed during application: {path}; earlier targets may have changed")
            temporary = None
            try:
                with tempfile.NamedTemporaryFile(dir=path.parent, prefix=".fm-live-", delete=False) as stream:
                    temporary = Path(stream.name)
                    os.fchmod(stream.fileno(), path.stat().st_mode & 0o7777)
                    stream.write(after)
                os.replace(temporary, path)
            finally:
                if temporary is not None:
                    temporary.unlink(missing_ok=True)
    for path, before, after, state in plan:
        result = state if args.action == "status" else ("absent" if args.action == "revert" else "applied")
        print(f"{result}: {path}")


if __name__ == "__main__":
    try:
        main()
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        print(f"refused: {error}", file=sys.stderr)
        sys.exit(1)

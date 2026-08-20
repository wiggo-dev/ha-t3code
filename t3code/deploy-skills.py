#!/usr/bin/env python3
"""Digest-sync bundled Home Assistant Skills into the Workspace Agent Skills tree (ADR-0003)."""

from __future__ import annotations

import hashlib
import json
import os
import shutil
import sys
from pathlib import Path


def digest_of(path: Path) -> str | None:
    if not path.is_file():
        return None
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(65536), b""):
            h.update(chunk)
    return h.hexdigest()


def list_files(root: Path) -> list[str]:
    if not root.is_dir():
        return []
    files: list[str] = []
    for path in root.rglob("*"):
        if path.is_file():
            files.append(path.relative_to(root).as_posix())
    return sorted(files)


def load_state(state_file: Path) -> dict[str, str]:
    try:
        data = json.loads(state_file.read_text(encoding="utf-8"))
        files = data.get("files", {})
        if isinstance(files, dict):
            return {str(k): str(v) for k, v in files.items()}
    except (OSError, json.JSONDecodeError, TypeError):
        pass
    return {}


def write_state(state_file: Path, files: dict[str, str]) -> None:
    state_file.parent.mkdir(parents=True, exist_ok=True)
    payload = {"version": 1, "files": dict(sorted(files.items()))}
    state_file.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")


def main() -> int:
    source_root = Path(os.environ.get("SKILLS_SOURCE", "/opt/ha-t3code/skills"))
    target_root = Path(os.environ.get("SKILLS_TARGET", "/config/.agents/skills"))
    state_file = Path(os.environ.get("SKILLS_STATE", "/data/managed-skills.json"))

    previous = load_state(state_file)
    next_state: dict[str, str] = {}
    deployed = updated = current = preserved = removed = 0

    target_root.mkdir(parents=True, exist_ok=True)
    source_files = list_files(source_root)

    for rel in source_files:
        key = f"skills/{rel}"
        source_path = source_root / rel
        target_path = target_root / rel
        source_digest = digest_of(source_path)
        if source_digest is None:
            continue
        target_digest = digest_of(target_path)
        recorded = previous.get(key)

        if target_digest is None:
            target_path.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source_path, target_path)
            next_state[key] = source_digest
            deployed += 1
            continue

        if target_digest == source_digest:
            next_state[key] = source_digest
            current += 1
            continue

        if recorded and recorded == target_digest:
            target_path.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source_path, target_path)
            next_state[key] = source_digest
            updated += 1
            continue

        if recorded:
            next_state[key] = recorded
        preserved += 1
        print(
            f"[warning] Keeping your edited {rel} - the add-on's newer version was not applied",
            file=sys.stderr,
        )

    source_keys = {f"skills/{rel}" for rel in source_files}
    for key, recorded_digest in previous.items():
        if not key.startswith("skills/") or key in source_keys:
            continue
        rel = key[len("skills/") :]
        target_path = target_root / rel
        target_digest = digest_of(target_path)
        if target_digest is None:
            continue
        if target_digest != recorded_digest:
            preserved += 1
            print(
                f"[warning] Keeping your edited {rel} - it is no longer shipped by the add-on",
                file=sys.stderr,
            )
            continue
        target_path.unlink(missing_ok=True)
        removed += 1

    write_state(state_file, next_state)
    print(
        f"Skills sync: deployed={deployed} updated={updated} "
        f"current={current} preserved={preserved} removed={removed}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

"""Deterministic membership inventories for reusable frozen resource trees."""
from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
from typing import Any, Mapping


SCHEMA = "witch-resource-input-inventory-v1"
RESOURCE_ROOTS = (
    "Art",
    "GeneratedArt",
    "Audio",
    "WitchAssets.xcassets",
    "WitchGameCore/Sources/WitchGameCore/Resources",
    "PrivacyInfo.xcprivacy",
)


class ResourceInventoryError(ValueError):
    pass


def capture_resource_inventory(native_root: Path) -> dict[str, Any]:
    """Record membership under every resource producer root; content is pinned separately."""
    native_root = Path(native_root).resolve()
    roots: dict[str, Any] = {}

    for relative in RESOURCE_ROOTS:
        source = native_root / relative
        if not source.exists() and not source.is_symlink():
            roots[relative] = {"exists": False, "members": []}
            continue
        if source.is_symlink():
            roots[relative] = {"exists": True, "members": [{"path": ".", "kind": "symlink", "target": os.readlink(source)}]}
            continue
        if source.is_file():
            roots[relative] = {"exists": True, "members": [{"path": ".", "kind": "file"}]}
            continue

        members: list[dict[str, str]] = []

        def fail_walk(error: OSError) -> None:
            raise ResourceInventoryError(f"Cannot inventory resource root {relative}: {error}")

        for directory, dirs, files in os.walk(source, topdown=True, followlinks=False, onerror=fail_walk):
            base = Path(directory)
            retained_dirs = []
            for name in sorted(dirs):
                path = base / name
                rel = path.relative_to(source).as_posix()
                if path.is_symlink():
                    members.append({"path": rel, "kind": "symlink", "target": os.readlink(path)})
                else:
                    retained_dirs.append(name)
            dirs[:] = retained_dirs
            for name in sorted(files):
                path = base / name
                rel = path.relative_to(source).as_posix()
                if path.is_symlink():
                    members.append({"path": rel, "kind": "symlink", "target": os.readlink(path)})
                elif path.is_file():
                    members.append({"path": rel, "kind": "file"})
                else:
                    members.append({"path": rel, "kind": "other"})
        roots[relative] = {"exists": True, "members": sorted(members, key=lambda item: (item["path"], item["kind"], item.get("target", "")))}

    return {"schema": SCHEMA, "roots": roots}


def inventory_sha256(inventory: Mapping[str, Any]) -> str:
    payload = json.dumps(inventory, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8")
    return hashlib.sha256(payload).hexdigest()


def require_reusable_inventory(capture: Mapping[str, Any], current: Mapping[str, Any]) -> None:
    """Fail closed for legacy captures or any before/after/current membership drift."""
    before = capture.get("resourceInputInventoryBefore")
    after = capture.get("resourceInputInventoryAfter")
    before_digest = capture.get("resourceInputInventoryBeforeSHA256")
    after_digest = capture.get("resourceInputInventoryAfterSHA256")
    if not isinstance(before, dict) or not isinstance(after, dict):
        raise ResourceInventoryError("Prior resource capture has no input inventory; fresh assembly required")
    if before.get("schema") != SCHEMA or after.get("schema") != SCHEMA or current.get("schema") != SCHEMA:
        raise ResourceInventoryError("Unsupported resource input inventory schema")
    if before != after:
        raise ResourceInventoryError("Prior resource input membership changed during its capture")
    if before_digest != inventory_sha256(before) or after_digest != inventory_sha256(after):
        raise ResourceInventoryError("Prior resource input inventory digest mismatch")
    if current != after:
        raise ResourceInventoryError("Current resource input membership differs; fresh assembly required")

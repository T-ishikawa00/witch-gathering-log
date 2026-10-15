"""Small fail-closed primitives for bounded local QA runners."""
from __future__ import annotations

import json
import os
from pathlib import Path
import tempfile
from dataclasses import dataclass
from typing import Iterable, Mapping, Sequence


class PrimitiveError(RuntimeError):
    pass


@dataclass(frozen=True)
class OwnedProcess:
    pid: int
    executable: str
    arguments: tuple[str, ...]


def verify_owned_process(
    known_pid: int,
    rows: Iterable[Mapping[str, object]],
    expected_executable: str,
    allowed_arguments: Sequence[str],
) -> OwnedProcess:
    """Require exactly one observed row and an exact PID/path/argv match.

    Each row has integer ``pid``, absolute ``executable``, and sequence ``argv``
    excluding argv[0]. No prefix or subset matching is accepted.
    """
    if type(known_pid) is not int or known_pid <= 0 or not isinstance(expected_executable, str) or not os.path.isabs(expected_executable):
        raise PrimitiveError("invalid expected process identity")
    observed = list(rows)
    if len(observed) != 1 or not isinstance(observed[0], Mapping):
        raise PrimitiveError("unexpected or ambiguous observed process set")
    matches = [r for r in observed if type(r.get("pid")) is int and r.get("pid") == known_pid]
    if len(matches) != 1:
        raise PrimitiveError("known PID missing or ambiguous")
    row = matches[0]
    executable = row.get("executable")
    argv = row.get("argv")
    if executable != expected_executable or not isinstance(argv, (list, tuple)):
        raise PrimitiveError("executable identity mismatch")
    if isinstance(allowed_arguments, (str, bytes)) or not all(isinstance(arg, str) for arg in allowed_arguments):
        raise PrimitiveError("invalid permitted argument vector")
    if not all(isinstance(arg, str) for arg in argv) or tuple(argv) != tuple(allowed_arguments):
        raise PrimitiveError("launch arguments mismatch")
    return OwnedProcess(known_pid, expected_executable, tuple(argv))


def _json_bytes(payload: object) -> bytes:
    return (json.dumps(payload, ensure_ascii=False, sort_keys=True, separators=(",", ":")) + "\n").encode("utf-8")


def _regular_parent(path: Path) -> Path:
    parent = path.parent
    if not parent.is_dir() or parent.is_symlink():
        raise PrimitiveError("parent must be an existing nonsymlink directory")
    return parent


def create_new_evidence(path: str | Path, payload: object) -> None:
    """Create immutable evidence exactly once; never replace an existing path."""
    target = Path(path)
    payload_bytes = _json_bytes(payload)
    _regular_parent(target)
    flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL
    if hasattr(os, "O_NOFOLLOW"):
        flags |= os.O_NOFOLLOW
    try:
        fd = os.open(target, flags, 0o600)
    except FileExistsError as exc:
        raise PrimitiveError("evidence already exists") from exc
    try:
        with os.fdopen(fd, "wb") as stream:
            stream.write(payload_bytes)
            stream.flush()
            os.fsync(stream.fileno())
    except BaseException:
        # Preserve any partial evidence for diagnosis; never silently remove it.
        raise


def update_run_receipt(path: str | Path, payload: object) -> None:
    """Atomically replace a known mutable receipt, requiring an existing file."""
    target = Path(path)
    _regular_parent(target)
    if target.is_symlink() or not target.is_file():
        raise PrimitiveError("mutable receipt must already be a regular file")
    fd, temp_name = tempfile.mkstemp(prefix=f".{target.name}.", suffix=".tmp", dir=target.parent)
    temp = Path(temp_name)
    try:
        os.fchmod(fd, 0o600)
        with os.fdopen(fd, "wb") as stream:
            stream.write(_json_bytes(payload))
            stream.flush()
            os.fsync(stream.fileno())
        if target.is_symlink() or not target.is_file():
            raise PrimitiveError("receipt identity changed during update")
        os.replace(temp, target)
        dirfd = os.open(target.parent, os.O_RDONLY)
        try:
            os.fsync(dirfd)
        finally:
            os.close(dirfd)
    finally:
        # Only our uniquely-created temp file is eligible for removal.
        try:
            temp.unlink()
        except FileNotFoundError:
            pass


def reserve_output_directory(path: str | Path) -> Path:
    """Create one fresh output directory and return the path to use thereafter."""
    target = Path(path)
    if not target.is_absolute() or target.exists() or target.is_symlink():
        raise PrimitiveError("output path must be absolute and unused")
    target.parent.mkdir(parents=True, exist_ok=True)
    if target.parent.is_symlink() or not target.parent.is_dir():
        raise PrimitiveError("output parent is not a real directory")
    target.mkdir(mode=0o700, exist_ok=False)
    return target

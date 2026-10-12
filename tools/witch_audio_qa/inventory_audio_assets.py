#!/usr/bin/env python3
"""Read-only inventory of direct audio files and audio entries inside project ZIP archives."""
from __future__ import annotations
import argparse
import json
from pathlib import Path
import zipfile

EXTENSIONS = {".wav", ".aif", ".aiff", ".caf", ".mp3", ".m4a", ".ogg", ".aac", ".flac"}


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("project_root", type=Path)
    parser.add_argument("--json", type=Path, required=True)
    parser.add_argument("--markdown", type=Path, required=True)
    args = parser.parse_args()
    root = args.project_root.resolve()
    generated = root / "native/AudioCandidates/dsp_sfx_r001"
    direct = []
    archives = []
    errors = []
    for path in sorted(root.rglob("*")):
        if not path.is_file() or path.suffix.lower() not in EXTENSIONS:
            continue
        try:
            relative = path.relative_to(root).as_posix()
        except ValueError:
            continue
        is_candidate = path.is_relative_to(generated)
        direct.append({"path": relative, "candidateGenerated": is_candidate, "bytes": path.stat().st_size})
    for path in sorted(root.rglob("*.zip")):
        try:
            with zipfile.ZipFile(path) as archive:
                for member in archive.infolist():
                    if Path(member.filename).suffix.lower() in EXTENSIONS and not member.is_dir():
                        archives.append({"archive": path.relative_to(root).as_posix(), "member": member.filename, "bytes": member.file_size})
        except (OSError, zipfile.BadZipFile) as exc:
            errors.append({"archive": path.relative_to(root).as_posix(), "error": str(exc)})
    preexisting = [item for item in direct if not item["candidateGenerated"]]
    payload = {
        "authority": "READ_ONLY_INVENTORY",
        "scope": "project checkout files and ZIP members only; no user home scan and no Downloads search",
        "projectRoot": str(root),
        "extensions": sorted(EXTENSIONS),
        "directAudioFileCount": len(direct),
        "preexistingDirectAudioFileCount": len(preexisting),
        "generatedCandidateDirectAudioFileCount": len(direct) - len(preexisting),
        "audioArchiveMemberCount": len(archives),
        "directFiles": direct,
        "archiveMembers": archives,
        "archiveReadErrors": errors,
    }
    args.json.parent.mkdir(parents=True, exist_ok=True)
    args.json.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n")
    md = [
        "# Audio Asset Inventory R001",
        "",
        "Authority: read-only file inventory. This does not establish usage rights, approval, sound quality, or product readiness.",
        "",
        f"- Scope: `{root}` project tree and ZIP members located within it. The scan did not inspect the rest of macOS or Downloads.",
        f"- Audio extensions: {', '.join(sorted(EXTENSIONS))}.",
        f"- Direct files: {len(direct)} total; {len(preexisting)} pre-existing; {len(direct) - len(preexisting)} generated candidate files.",
        f"- Audio entries inside project ZIP archives: {len(archives)}.",
        f"- Archive read errors: {len(errors)}.",
        "",
        "## Direct files",
        "",
    ]
    md += [f"- `{item['path']}` ({item['bytes']} bytes; {'generated candidate' if item['candidateGenerated'] else 'pre-existing'})" for item in direct] or ["- None found."]
    md += ["", "## ZIP members", ""]
    md += [f"- `{item['archive']} :: {item['member']}` ({item['bytes']} bytes)" for item in archives] or ["- None found."]
    if errors:
        md += ["", "## Archive errors", ""] + [f"- `{item['archive']}`: {item['error']}" for item in errors]
    args.markdown.parent.mkdir(parents=True, exist_ok=True)
    args.markdown.write_text("\n".join(md) + "\n")
    print(f"AUDIO_INVENTORY direct={len(direct)} preexisting={len(preexisting)} candidate={len(direct)-len(preexisting)} zip_members={len(archives)} errors={len(errors)}")
    return 1 if errors else 0

if __name__ == "__main__":
    raise SystemExit(main())

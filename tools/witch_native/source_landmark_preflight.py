#!/usr/bin/env python3
"""Non-mutating source-pixel audit for per-frame equipment landmarks.

Creates QA marker/contact images only; source art and overlay metadata are read-only.
Coordinates are displayed against the exact PNG bytes named by each row.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
from typing import Any

from PIL import Image, ImageDraw, ImageFont


COLORS = [
    (255, 60, 60), (30, 200, 255), (255, 220, 0), (80, 255, 100),
    (255, 100, 230), (255, 150, 35), (185, 100, 255), (255, 255, 255),
    (50, 255, 210), (255, 100, 100),
]


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for block in iter(lambda: f.read(1024 * 1024), b""):
            h.update(block)
    return h.hexdigest()


def find_rows(document: dict[str, Any]) -> tuple[str, str, list[dict[str, Any]]]:
    matches: list[tuple[str, str, list[dict[str, Any]]]] = []
    for actor_id, actor_block in document.get("entries", {}).items():
        if not isinstance(actor_block, dict):
            continue
        for key, value in actor_block.items():
            if key == "semanticFrameLandmarksCandidate" and isinstance(value, dict) and isinstance(value.get("rows"), list):
                matches.append((actor_id, key, value["rows"]))
    if len(matches) != 1:
        raise ValueError(f"Expected exactly one semanticFrameLandmarksCandidate block, found {len(matches)}")
    return matches[0]


def make_sheet(rows: list[dict[str, Any]], repo: Path, output: Path, scale: int, cols: int) -> bool:
    font = ImageFont.load_default()
    cell_w = 320 * scale
    tiles: list[Image.Image] = []
    errors: list[dict[str, Any]] = []
    for row in rows:
        source = repo / row["source_path"]
        raw = source.read_bytes()
        actual_sha = hashlib.sha256(raw).hexdigest()
        im = Image.open(source).convert("RGBA")
        expected_size = tuple(row.get("canvas_px", im.size))
        if im.size != expected_size or actual_sha != row.get("sourceSHA256"):
            errors.append({
                "source_path": row["source_path"],
                "expectedSHA256": row.get("sourceSHA256"),
                "actualSHA256": actual_sha,
                "expectedCanvas": list(expected_size),
                "actualCanvas": list(im.size),
            })
        im = im.resize((im.width * scale, im.height * scale), Image.Resampling.NEAREST)
        legend_names = list(row.get("landmarks_px_top_left", {}).keys())
        legend_line_h = 12 * scale
        legend_y = 30 * scale + im.height + 4 * scale
        legend_rows = (len(legend_names) + 2) // 3
        cell_h = legend_y + max(1, legend_rows) * legend_line_h + 4 * scale
        tile = Image.new("RGBA", (cell_w, cell_h), (22, 25, 31, 255))
        tile.alpha_composite(im, (0, 30 * scale))
        draw = ImageDraw.Draw(tile)
        state = row.get("sourceRowState", "state?")
        idx = row.get("frameIndex", "?")
        draw.text((5, 4), f"{state} idx={idx} {Path(row['source_path']).name}", fill="white", font=font)
        landmarks = row.get("landmarks_px_top_left", {})
        for n, (name, point) in enumerate(landmarks.items()):
            color = COLORS[n % len(COLORS)]
            lx = 5 + (n % 3) * (cell_w // 3)
            ly = legend_y + (n // 3) * legend_line_h
            if point is None:
                draw.text((lx, ly), f"{n}:{name}=null", fill=color, font=font)
                continue
            if not isinstance(point, (list, tuple)) or len(point) != 2:
                errors.append({"source_path": row["source_path"], "badPoint": {name: point}})
                continue
            x, y = int(point[0]) * scale, int(point[1]) * scale + 30 * scale
            radius = max(3, 2 * scale)
            draw.ellipse((x-radius, y-radius, x+radius, y+radius), outline=color, width=max(1, scale))
            draw.line((x - 5*scale, y, x + 5*scale, y), fill=color, width=max(1, scale))
            draw.line((x, y - 5*scale, x, y + 5*scale), fill=color, width=max(1, scale))
            draw.text((lx, ly), f"{n}:{name}", fill=color, font=font)
        tiles.append(tile.convert("RGB"))

    output.mkdir(parents=True, exist_ok=True)
    max_cell_h = max((im.height for im in tiles), default=1)
    for start in range(0, len(tiles), cols * 3):
        subset = tiles[start:start + cols * 3]
        sheet = Image.new("RGB", (cols * cell_w, 3 * max_cell_h), (12, 14, 18))
        for offset, tile in enumerate(subset):
            sheet.paste(tile, ((offset % cols) * cell_w, (offset // cols) * max_cell_h))
        sheet.save(output / f"CONTACT_{start // (cols * 3):02d}.jpg", quality=94)
    (output / "SOURCE_CHECK.json").write_text(json.dumps({
        "rows": len(rows),
        "sourceHashesAndCanvasesMatch": not errors,
        "errors": errors,
        "markerColorsByLandmarkOrder": COLORS,
        "warning": "Markers identify proposed coordinates only. Inspect anatomy in source pixels; alpha occupancy alone is not anatomical validation.",
    }, ensure_ascii=False, indent=2) + "\n")
    return bool(errors)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("overlay", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--repo", type=Path, default=Path.cwd())
    parser.add_argument("--scale", type=int, default=2)
    parser.add_argument("--cols", type=int, default=3)
    args = parser.parse_args()
    doc = json.loads(args.overlay.read_text())
    actor_id, block_key, rows = find_rows(doc)
    has_errors = make_sheet(rows, args.repo.resolve(), args.output, args.scale, args.cols)
    print(json.dumps({"actor": actor_id, "landmarkBlock": block_key, "rows": len(rows), "output": str(args.output)}, ensure_ascii=False))
    return 1 if has_errors else 0


if __name__ == "__main__":
    raise SystemExit(main())

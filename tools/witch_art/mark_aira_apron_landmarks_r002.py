#!/usr/bin/env python3
"""Create source-only, marked review contacts for the 24 remaining AIRA apron frames.

This annotates review copies only. It never writes to source PNGs or runtime overlays.
Coordinates are provisional visual readings and are explicitly not runtime fit evidence.
"""
from __future__ import annotations

import hashlib
import json
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[2]
IN = ROOT / "docs/production/current/art/aira_apron_landmark_r003_pending24/SOURCE_FRAME_MANIFEST_R001.json"
OUT = ROOT / "docs/production/current/art/aira_apron_landmark_r003_pending24/marked_r002"

# Manual source-pixel readings from the exact unmarked source contacts.
# Values denote the bottom edge of the central hanging apron, not its underlay center.
POINTS = {
    "AIRA__rest_00.png": (158, 190),
    "AIRA__rest_02.png": (144, 190),
    "AIRA__rest_03.png": (155, 191),
    "AIRA__rest_04.png": (143, 213),
    "AIRA__rest_05.png": (153, 201),
    "AIRA__rest_06.png": (156, 198),
    "AIRA__rest_07.png": (170, 197),
    "AIRA__rest_08.png": (156, 202),
    "AIRA__attack_00.png": (145, 188),
    "AIRA__attack_01.png": (151, 198),
    "AIRA__attack_02.png": (137, 201),
    "AIRA__attack_03.png": (152, 196),
    "AIRA__attack_05.png": (121, 198),
    "AIRA__attack_06.png": (123, 199),
    "AIRA__attack_07.png": (121, 203),
    "AIRA__attack_08.png": (137, 199),
    "AIRA__walk_0.png": (122, 191),
    "AIRA__walk_1.png": (120, 193),
    "AIRA__walk_2.png": (123, 194),
    "AIRA__walk_3.png": (124, 195),
    "AIRA__walk_4.png": (122, 194),
    "AIRA__walk_5.png": (120, 195),
    "AIRA__walk_7.png": (121, 194),
    "AIRA__walk_8.png": (124, 193),
}

def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()

def main() -> None:
    manifest = json.loads(IN.read_text())
    font = ImageFont.load_default()
    marked_rows = []
    full_tiles: list[Image.Image] = []
    zoom_tiles: list[Image.Image] = []
    source_errors = []
    for row in manifest["frames"]:
        filename = Path(row["source_path"]).name
        point = POINTS.get(filename)
        if point is None:
            raise ValueError(f"No manual point for {filename}")
        source = ROOT / row["source_path"]
        im = Image.open(source).convert("RGBA")
        actual_sha = sha(source)
        if list(im.size) != row["canvas_px"] or actual_sha != row["sourceSHA256"]:
            source_errors.append({"file": filename, "size": list(im.size), "sha": actual_sha})
        x, y = point
        if not (0 <= x < im.width and 0 <= y < im.height):
            raise ValueError(f"Out-of-bounds point {filename}: {point}")
        evidence_id = Path(row["bodyAssetID"]).stem.replace("AIRA__", "")
        full = Image.new("RGBA", (im.width * 2, im.height * 2 + 34), (23, 27, 33, 255))
        full.alpha_composite(im.resize((im.width * 2, im.height * 2), Image.Resampling.NEAREST), (0, 34))
        fd = ImageDraw.Draw(full)
        fd.text((4, 4), f"{row['runtimeState']}:{row['runtimeFrameIndex']} {filename}  {im.width}x{im.height}", fill="white", font=font)
        px, py = x * 2, y * 2 + 34
        fd.ellipse((px - 7, py - 7, px + 7, py + 7), outline=(255, 45, 45), width=2)
        fd.line((px - 10, py, px + 10, py), fill=(255, 45, 45), width=1)
        fd.line((px, py - 10, px, py + 10), fill=(255, 45, 45), width=1)
        full_tiles.append(full.convert("RGB"))

        # Fixed source crop gives enough neighboring anatomy to judge the apron edge.
        left, top = max(0, x - 48), max(0, y - 38)
        right, bottom = min(im.width, x + 49), min(im.height, y + 39)
        crop = im.crop((left, top, right, bottom)).resize(((right-left)*5, (bottom-top)*5), Image.Resampling.NEAREST)
        tile = Image.new("RGBA", (crop.width, crop.height + 36), (23, 27, 33, 255))
        tile.alpha_composite(crop, (0, 36))
        zd = ImageDraw.Draw(tile)
        zd.text((4, 4), f"{row['runtimeState']}:{row['runtimeFrameIndex']} {filename} point={x},{y}", fill="white", font=font)
        # Grid is 8 source px; major labels use source-coordinate origin.
        sx, sy = left, top
        for gx in range(((left + 7) // 8) * 8, right, 8):
            ox = (gx-left)*5
            zd.line((ox,36,ox,tile.height), fill=(20, 165, 190, 150), width=1)
            if gx % 16 == 0:
                zd.text((ox+2, 37), str(gx), fill=(255, 230, 70), font=font)
        for gy in range(((top + 7) // 8) * 8, bottom, 8):
            oy = 36+(gy-top)*5
            zd.line((0,oy,tile.width,oy), fill=(20,165,190,150), width=1)
            if gy % 16 == 0:
                zd.text((2,oy+2), str(gy), fill=(255,230,70), font=font)
        qx, qy = (x-left)*5, 36+(y-top)*5
        zd.ellipse((qx-10,qy-10,qx+10,qy+10), outline=(255,45,45), width=3)
        zd.line((qx-16,qy,qx+16,qy), fill=(255,45,45), width=2)
        zd.line((qx,qy-16,qx,qy+16), fill=(255,45,45), width=2)
        zoom_tiles.append(tile.convert("RGB"))
        marked_rows.append({
            **row,
            "landmarkName": "central_hanging_leather_apron_bottom_edge_candidate",
            "landmarkPxTopLeftSource": [x, y],
            "measurementStatus": "UNAPPROVED_VISUAL_SOURCE_CANDIDATES_REQUIRES_INDEPENDENT_REVIEW",
            "measurementBasis": "Manual visual point on the exact source PNG, checked against source-coordinate grid contact. Not alpha-derived, not runtime registration, and not a fit or Human-approval result.",
            "fullMarkerEvidence": f"docs/production/current/art/aira_apron_landmark_r003_pending24/marked_r002/FULL_{evidence_id}.png",
            "zoomMarkerEvidence": f"docs/production/current/art/aira_apron_landmark_r003_pending24/marked_r002/ZOOM_{evidence_id}.png",
        })
        OUT.mkdir(parents=True, exist_ok=True)
        full.save(OUT / f"FULL_{evidence_id}.png")
        tile.save(OUT / f"ZOOM_{evidence_id}.png")

    def contact(tiles: list[Image.Image], filename: str, cols: int, rows_per_page: int) -> None:
        for page, start in enumerate(range(0, len(tiles), cols * rows_per_page)):
            subset = tiles[start:start + cols * rows_per_page]
            tw = max(i.width for i in subset)
            th = max(i.height for i in subset)
            sheet = Image.new("RGB", (tw*cols, th*rows_per_page), (12,14,18))
            for i, tile in enumerate(subset):
                sheet.paste(tile, ((i % cols)*tw, (i//cols)*th))
            sheet.save(OUT / filename.format(page=page), quality=94)
    contact(full_tiles, "CONTACT_FULL_{page:02d}.jpg", 4, 2)
    contact(zoom_tiles, "CONTACT_ZOOM_{page:02d}.jpg", 2, 4)

    result = {
        "schema": "aira_apron_landmarks_source_candidate_r002",
        "status": "UNAPPROVED_VISUAL_SOURCE_CANDIDATES_REQUIRES_INDEPENDENT_REVIEW",
        "runtimeConsumable": False,
        "humanApproved": False,
        "scope": "The 24 exact AIRA source frames excluding R007 idle:1, execute:1, walk:6. Source images are byte-preserved.",
        "landmarkDefinition": "Bottom edge of central hanging leather apron/flap between thighs. Do not substitute outer coat, sleeve, leg, hand, hammer, or foot.",
        "coordinateContract": "Top-left origin, source PNG pixel units; source frame dimensions and SHA come from SOURCE_FRAME_MANIFEST_R001.json.",
        "sourceManifest": "docs/production/current/art/aira_apron_landmark_r003_pending24/SOURCE_FRAME_MANIFEST_R001.json",
        "sourceManifestSHA256": sha(IN),
        "rows": marked_rows,
        "contactEvidence": {
            "full": ["CONTACT_FULL_00.jpg", "CONTACT_FULL_01.jpg"],
            "zoom": ["CONTACT_ZOOM_00.jpg", "CONTACT_ZOOM_01.jpg", "CONTACT_ZOOM_02.jpg"],
        },
        "sourceChecks": {"allSourceHashesAndCanvasesMatch": not source_errors, "errors": source_errors},
        "limitations": [
            "Points are provisional manual readings and require parent/independent visual review.",
            "This document does not establish BODY01/02 visibility, native fit, runtime registration, or Human acceptance.",
            "An unclear edge must be changed to unknown rather than inferred from neighboring frames.",
        ],
    }
    target = OUT / "AIRA_APRON_LANDMARKS_SOURCE_CANDIDATE_R002.json"
    temp = target.with_suffix(".tmp")
    temp.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n")
    temp.replace(target)
    print(json.dumps({"rows": len(marked_rows), "hashCanvasErrors": source_errors, "candidate": str(target.relative_to(ROOT)), "sha256": sha(target)}, ensure_ascii=False))

if __name__ == "__main__":
    main()

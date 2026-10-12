#!/usr/bin/env python3
"""Build additive BODY01/BODY02 candidate anchors from inspected source frames.

Coordinates are review candidates read against the checked-in 16 px contact grids.
This tool never changes source art or renderer manifests.
"""
from __future__ import annotations

import hashlib
import json
from pathlib import Path

from PIL import Image
from PIL import ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[2]
DETAILS = ROOT / "native/Art/GeneratedCandidates/EquipmentDetails"

# Frame-local readings from the source-grid contacts. BODY01 follows the outer
# lower hem at screen-right; it intentionally avoids the center-front white cloth.
LUNA = {
    "walk": [(173,194),(174,194),(176,194),(174,194),(175,195),(176,195),(171,194),(174,194),(175,195)],
    "anticipate": [(174,194),(174,194),(173,194)],
    "execute": [(176,194),(177,194),(167,194)],
    "recover": [(176,194),(175,194),(176,194)],
    "idle": [(176,194),(175,194),(176,194)],
    "hit": [(176,194),(176,194),(176,194)],
    "resolve": [(176,194),(175,194),(176,194)],
}
ERNA = {
    "standard": {
        "walk": [(189,207),(191,208),(191,206),(190,206),(190,206),(191,206),(190,207),(191,207),(191,206)],
        "anticipate": [(191,204),(192,204),(192,203)],
        "execute": [(194,201),(195,204),(195,204)],
        "recover": [(193,205),(193,204),(192,205)],
        "idle": [(190,204),(191,204),(190,204)],
        "hit": [(191,204),(191,204),(191,204)],
        "resolve": [(190,204),(191,204),(190,204)],
    },
    "travel": {
        "walk": [(188,207),(189,208),(189,206),(189,207),(190,207),(189,206),(188,208),(189,207),(189,207)],
        "anticipate": [(190,204),(191,204),(191,203)],
        "execute": [(192,201),(194,204),(194,204)],
        "recover": [(192,204),(192,204),(191,205)],
        "idle": [(189,204),(190,204),(189,204)],
        "hit": [(189,204),(189,204),(189,204)],
        "resolve": [(189,204),(190,204),(189,204)],
    },
}


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def make_row(actor: str, costume: str, state: str, idx: int, asset_id: str,
             source_rel: str, point: tuple[int, int], grid: str) -> dict:
    source = ROOT / source_rel
    image = Image.open(source).convert("RGBA")
    w, h = image.size
    x, y = point
    if not (0 <= x < w and 0 <= y < h):
        raise ValueError(f"out-of-canvas point {source_rel}: {point}")
    alpha = image.getpixel((x, y))[3]
    row = {
        "actorID": actor,
        "costume": costume,
        "state": state,
        "runtimeFrameIndex": idx,
        "bodyAssetID": asset_id,
        "runtimeBodyAssetID": asset_id,
        "canvas_px": [w, h],
        "source_path": source_rel,
        "sourceSHA256": sha(source),
        "contactGridEvidence": grid,
        "landmarks_px_top_left": {
            "BODY01_hemTab": {
                "status": "measured_candidate",
                "point": [x, y],
                "confidence": "visual_grid_approx_6px",
                "notes": "候補点。画面右側の外套/上着の下裾端に沿う。正面中央の白布・肌・脚を避ける小さな内布タブ用の基準点。原画に素材を追加した状態や遮蔽は未検証。",
                "sourcePixelAlpha": alpha,
            },
            "BODY02_cloakLining": {
                "status": "unknown_occluded",
                "point": None,
                "notes": "この焼き込みフレームでは裾の内側面を外側の縁/刺繍から確実に分離できない。裏地を推測で表面へ置かず、接続点は未測定。",
            },
        },
    }
    return row


def main() -> None:
    luna_base = json.loads((DETAILS / "luna_book_frame_landmarks_r002.json").read_text())
    luna_by_key = {(r["state"], r["frameIndex"]): r for r in luna_base["rows"]}
    rows = []
    for state, points in LUNA.items():
        for idx, point in enumerate(points):
            base = luna_by_key[(state, idx)]
            rows.append(make_row(
                "LUNA", "book_candidate", state, idx, base["bodyAssetID"],
                base["source_path"], point,
                f"native/Art/GeneratedCandidates/EquipmentDetails/body_hem_lining_contacts_r001/luna_{state}_grid_2x.jpg",
            ))

    erna_base = json.loads((DETAILS / "erna_standard_travel_landmarks_r002.json").read_text())
    for costume, states in ERNA.items():
        for state, points in states.items():
            frames = erna_base["states"][costume][state]["frames"]
            if len(frames) != len(points):
                raise ValueError(f"point count mismatch {costume}/{state}")
            for idx, (frame, point) in enumerate(zip(frames, points)):
                filename = Path(frame["runtimeBodyAssetID"]).name
                source_rel = f"native/GeneratedArt/layered_motion_r001/{filename}"
                rows.append(make_row(
                    "C_WITCH", costume, state, idx, frame["runtimeBodyAssetID"],
                    source_rel, point,
                    f"native/Art/GeneratedCandidates/EquipmentDetails/erna_landmark_contacts_r002/{costume}_{state}_grid_2x.png",
                ))

    # Make row-addressable source contacts with the registered point overlaid.
    evidence_root = DETAILS / "body_hem_lining_contacts_r001" / "marked"
    evidence_root.mkdir(parents=True, exist_ok=True)
    groups: dict[tuple[str, str, str], list[dict]] = {}
    for row in rows:
        groups.setdefault((row["actorID"], row["costume"], row["state"]), []).append(row)
    for (actor, costume, state), group in groups.items():
        group.sort(key=lambda r: r["runtimeFrameIndex"])
        scale, cell_w, image_h, label_h, cols = 2, 512, 512, 32, 3
        rows_count = (len(group) + cols - 1) // cols
        sheet = Image.new("RGBA", (cols * cell_w, rows_count * (image_h + label_h)), (248, 248, 248, 255))
        for cell_index, row in enumerate(group):
            src = Image.open(ROOT / row["source_path"]).convert("RGBA")
            card = Image.new("RGBA", src.size, (248, 248, 248, 255))
            card.alpha_composite(src)
            draw = ImageDraw.Draw(card, "RGBA")
            for x in range(0, 257, 16):
                draw.line((x, 0, x, 255), fill=(28, 111, 220, 110), width=1)
            for y in range(0, 257, 16):
                draw.line((0, y, 255, y), fill=(28, 111, 220, 110), width=1)
            x, y = row["landmarks_px_top_left"]["BODY01_hemTab"]["point"]
            draw.ellipse((x-3, y-3, x+3, y+3), fill=(255, 0, 0, 255), outline=(255, 245, 0, 255), width=1)
            card = card.resize((cell_w, image_h), Image.Resampling.NEAREST)
            col, line = cell_index % cols, cell_index // cols
            sheet.alpha_composite(card, (col * cell_w, line * (image_h + label_h)))
            label = Image.new("RGBA", (cell_w, label_h), (248, 248, 248, 255))
            ImageDraw.Draw(label).text((6, 5), f"{actor}/{costume} {state} local {row['runtimeFrameIndex']}  BODY01={x},{y}", fill=(20,20,20,255))
            sheet.alpha_composite(label, (col * cell_w, line * (image_h + label_h) + image_h))
            row["markedContactSheet"] = str((evidence_root / f"{actor.lower()}_{costume}_{state}_r001.png").relative_to(ROOT))
            row["markedContactCellIndex"] = cell_index
        sheet_path = evidence_root / f"{actor.lower()}_{costume}_{state}_r001.png"
        tmp = sheet_path.with_suffix(".tmp.png")
        sheet.save(tmp, format="PNG")
        tmp.replace(sheet_path)

    out = {
        "schema": "body01_hem_body02_lining_landmarks_r001",
        "status": "UNAPPROVED_MEASURED_CANDIDATE",
        "humanApproval": False,
        "scope": "27 Luna book-body frames + 54 Erna standard/travel runtime frames; attachment-point candidates only",
        "coordinateSystem": "source image pixel coordinates, origin top-left; canvas is 256x256",
        "authority": "Derived from world R1 gear intent and visually checked source-grid contacts. Does not approve equipment appearance, art changes, or renderer integration.",
        "sourceReferences": [
            "docs/design/sources/world_r1/Witch_World_Design_R1_20261008/data/gear.csv",
            "native/GeneratedArt/luna_book_motion_candidates_r001/LUNA_BOOK_MOTION_CANDIDATES_R001.json",
            "native/GeneratedArt/layered_motion_r001/MANIFEST.json",
            "native/Art/GeneratedCandidates/EquipmentDetails/luna_book_frame_landmarks_r002.json",
            "native/Art/GeneratedCandidates/EquipmentDetails/erna_standard_travel_landmarks_r002.json",
        ],
        "measurement": {
            "method": "Each source frame has an addressable marker contact showing the exact BODY01 point against that original 256x256 frame and a 16-source-pixel grid. Coordinates are approximate visual readings, not segmentation-derived truth; marker contacts allow per-image correspondence review.",
            "body01": "Small detail anchor follows the screen-right outer lower hem; intentionally avoids center-front white cloth and exposed skin/legs. Runtime fit, layer order, and exact clipping remain unverified.",
            "body02": "Marked unknown/occluded on every row because the baked source frames do not expose a separable inner lining surface with enough certainty. Do not render until Art supplies a validated surface/mask or separate layer.",
            "uncertaintyPx": 6,
            "runtimeFitVerified": False,
        },
        "rows": rows,
    }
    target = DETAILS / "body01_hem_body02_lining_landmarks_r001.json"
    target.write_text(json.dumps(out, ensure_ascii=False, indent=2) + "\n")
    print(f"wrote {target.relative_to(ROOT)} rows={len(rows)} body02_unknown={sum(r['landmarks_px_top_left']['BODY02_cloakLining']['point'] is None for r in rows)}")
    print("alpha-zero BODY01 points:", sum(r["landmarks_px_top_left"]["BODY01_hemTab"]["sourcePixelAlpha"] == 0 for r in rows))


if __name__ == "__main__":
    main()

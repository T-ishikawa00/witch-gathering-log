#!/usr/bin/env python3
"""Pack four additive boss-arena foreground candidates without changing source art."""
from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
ART = ROOT / "native/Art"
OUT = ART / "GeneratedCandidates/BackgroundLayers/boss_foreground_r001"
CANVAS = (941, 1672)
SOURCES = {
    "R02": Path("/Users/PUBLIC_USER/.codex/generated_images/01a12399-b8c7-76a0-adb6-39606fe83b65/exec-8c22b7e3-35e8-4032-870b-d7097cd48bba.png"),
    "R03": Path("/Users/PUBLIC_USER/.codex/generated_images/01a12399-b8c7-76a0-adb6-39606fe83b65/exec-abd565b4-b772-4bba-b031-bbac3c106e4d.png"),
    "R04": Path("/Users/PUBLIC_USER/.codex/generated_images/01a12399-b8c7-76a0-adb6-39606fe83b65/exec-d3b4098f-f197-47fa-8e43-6b46ef108c63.png"),
    "R05": Path("/Users/PUBLIC_USER/.codex/generated_images/01a12399-b8c7-76a0-adb6-39606fe83b65/exec-8742cf1a-5d78-45bf-a352-e5cbdf9a218d.png"),
}
BASES = {
    region: ART / f"BackgroundPreviews/BG_{region}_BOSS/BG_{region}_BOSS__fullframe_review_candidate__r001.png"
    for region in SOURCES
}


def sha(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for block in iter(lambda: f.read(1024 * 1024), b""):
            h.update(block)
    return h.hexdigest()


def atomic_bytes(path: Path, data: bytes) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_name(path.name + ".tmp")
    with tmp.open("wb") as f:
        f.write(data)
        f.flush()
        os.fsync(f.fileno())
    os.replace(tmp, path)


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    qa_dir = OUT / "qa"
    qa_dir.mkdir(parents=True, exist_ok=True)
    records = []
    for region, source in SOURCES.items():
        base_path = BASES[region]
        if not source.is_file() or not base_path.is_file():
            raise FileNotFoundError(f"missing source/base for {region}: {source} / {base_path}")
        with Image.open(source) as im:
            im.load()
            if im.mode != "RGBA":
                raise ValueError(f"{region} candidate must retain generated RGBA alpha; got {im.mode}")
            if abs(im.width / im.height - CANVAS[0] / CANVAS[1]) > 0.001:
                raise ValueError(f"{region} candidate aspect mismatch: {im.size}")
            original_size = im.size
            if original_size[0] > CANVAS[0] or original_size[1] > CANVAS[1]:
                raise ValueError(f"{region} candidate exceeds reference canvas: {original_size}")
            # The R03 output is one source pixel shorter; top-left registration is preserved
            # and the missing bottom row is transparent padding, not painted content.
            packed = Image.new("RGBA", CANVAS, (0, 0, 0, 0))
            packed.alpha_composite(im, (0, 0))
            target = OUT / f"BG_{region}_BOSS_foreground_candidate_r001.png"
            import io
            b = io.BytesIO()
            packed.save(b, format="PNG", optimize=True)
            atomic_bytes(target, b.getvalue())

        with Image.open(target) as layer, Image.open(base_path) as base:
            base = base.convert("RGBA")
            if base.size != CANVAS:
                raise ValueError(f"{region} boss base canvas mismatch: {base.size}")
            preview = base.copy()
            preview.alpha_composite(layer)
            qap = qa_dir / f"BG_{region}_BOSS_composite_candidate_r001.jpg"
            import io
            b = io.BytesIO()
            preview.convert("RGB").save(b, format="JPEG", quality=92)
            atomic_bytes(qap, b.getvalue())
            alpha = layer.getchannel("A")
            total = CANVAS[0] * CANVAS[1]
            zero_ratio = sum(v == 0 for v in alpha.getdata()) / total
            middle_top = alpha.crop((int(CANVAS[0] * .15), 0, int(CANVAS[0] * .85), int(CANVAS[1] * .75)))
            middle_top_data = list(middle_top.getdata())
            middle_top_alpha_gt16 = sum(v > 16 for v in middle_top_data) / len(middle_top_data)
            record = {
                "scene_id": f"BG_{region}_BOSS",
                "source_fullframe_path": base_path.relative_to(ART).as_posix(),
                "source_fullframe_sha256": sha(base_path),
                "source_fullframe_canvas_px": list(CANVAS),
                "generated_source_path": str(source),
                "generated_source_sha256": sha(source),
                "generated_source_canvas_px": list(original_size),
                "packed_foreground_path": target.relative_to(ART).as_posix(),
                "packed_foreground_sha256": sha(target),
                "packed_foreground_canvas_px": list(CANVAS),
                "alpha_zero_ratio": round(zero_ratio, 8),
                "central_70pct_upper_75pct_alpha_gt16_ratio": round(middle_top_alpha_gt16, 8),
                "composition_preview": qap.relative_to(ART).as_posix(),
                "base_z": -20,
                "foreground_z": 12,
                "source_depth_recovered": False,
                "status": "UNAPPROVED_GENERATED_BOSS_FOREGROUND_CANDIDATE",
                "known_limitations": [
                    "Generated edge framing only; it is not recovered source depth or an adopted art plate.",
                    "The full-frame base remains intact beneath this additive overlay.",
                    "Central alpha leakage ratio is a pixel diagnostic, not proof of actor visibility or good composition.",
                    "SpriteKit registration, enemy/party occlusion, and Human visual review are pending."
                ]
            }
            records.append(record)
            overlay = {
                "status": "UNAPPROVED_GENERATED_BOSS_FOREGROUND_LAYER_CANDIDATE",
                "complete_layered_background": False,
                "entries": {
                    f"BG_{region}_BOSS": {
                        "kind": "background_kit",
                        "selectedPNG": record["source_fullframe_path"],
                        "sceneLayers": [
                            {"path": record["source_fullframe_path"], "z": -20},
                            {"path": record["packed_foreground_path"], "z": 12}
                        ],
                        "status": "GENERATED_EDGE_FOREGROUND_CANDIDATE_FULLFRAME_BASE_HELD_FIXED",
                        "candidateRegistration": "COMMON_941x1672_TOPLEFT_SOURCE_SPACE; SIMULATOR_OCCLUSION_CHECK_REQUIRED",
                        "humanAdoption": "PENDING",
                        "sourceDepthRecovered": False,
                        "candidateManifest": "GeneratedCandidates/BackgroundLayers/boss_foreground_candidate_manifest_r001.json",
                        "qaPreview": record["composition_preview"]
                    }
                }
            }
            overlay_path = ART / f"runtime_overlay_bg_{region.lower()}_boss_scene_layers_candidate_r001.json"
            atomic_bytes(overlay_path, (json.dumps(overlay, ensure_ascii=False, indent=2) + "\n").encode())
            record["runtime_overlay"] = overlay_path.relative_to(ART).as_posix()

    manifest = {
        "schema": "witch.boss_scene_layers_candidate_manifest.v1",
        "revision": "r001",
        "status": "UNAPPROVED_CANDIDATE_ONLY",
        "scene_layer_contract": "keep selected full-frame candidate fixed at z=-20; additive transparent edge foreground at z=12; use common source-space 941x1672 canvas",
        "candidate_records": records,
        "source_assets_untouched": True,
        "human_adoption": False,
        "complete_layered_background": False
    }
    atomic_bytes(ART / "GeneratedCandidates/BackgroundLayers/boss_foreground_candidate_manifest_r001.json", (json.dumps(manifest, ensure_ascii=False, indent=2) + "\n").encode())
    print(json.dumps({r["scene_id"]: {"packed": r["packed_foreground_path"], "sha256": r["packed_foreground_sha256"], "alpha0": r["alpha_zero_ratio"], "center_top_gt16": r["central_70pct_upper_75pct_alpha_gt16_ratio"], "overlay": r["runtime_overlay"]} for r in records}, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()

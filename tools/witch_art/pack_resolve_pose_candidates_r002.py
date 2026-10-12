#!/usr/bin/env python3
"""Pack the seven remaining resolve-only sprite candidates without modifying sources."""
from __future__ import annotations

import hashlib
import io
import json
import os
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[2]
ART = ROOT / "native/Art"
CANVAS = (512, 512)
ANCHOR = (256, 490)
FPS = 8
GEN = Path("/Users/PUBLIC_USER/.codex/generated_images")
# One constant fit factor applies to every frame of an actor's clip. The
# marsh-lizard imagegen frame 1 nearly touches the canvas edge at 1.0, so its
# entire three-frame clip is packed 5% smaller rather than trimming alpha.
ACTOR_FIT_SCALE = {"ACT_E_R02_02": 0.95, "ACT_E_R02_04": 0.95}
ACTORS = {
    "ACT_B_R01_B": {
        "semantics": ["Tree guardian begins upright and rooted after the battle; no breakage.", "Canopy and boughs begin to dip while the roots remain planted.", "Tree guardian settles lower with branches hanging and crown bowed; roots remain planted."],
        "still": "ActorStills/ACT_B_R01_B/ACT_B_R01_B__still__B_R01_B_ANCIENT_TREE_base_v1.png",
        "sources": ["01a12399-b8c7-76a0-adb6-39606fe83b65/exec-265de273-a35b-45fd-bad4-9ee64d942c0f.png", "01a12399-b8c7-76a0-adb6-39606fe83b65/exec-645f20d3-5d76-40f5-acdf-77f580ea4c0b.png", "01a12399-b8c7-76a0-adb6-39606fe83b65/exec-14272392-7077-41fb-9a9d-1584b7832b1f.png"],
    },
    "ACT_B_R02_A": {
        "semantics": ["Stalk bends and cap dips; weight shifts into root feet.", "Cap lowers near the floor; stalk and root feet fold.", "Cap rests low on its side; stalk limp and root feet tucked."],
        "still": "ActorStills/ACT_B_R02_A/ACT_B_R02_A__still__r001.png",
        "sources": ["01a12399-b8c7-76a0-adb6-39606fe83b65/exec-f7e1ffec-b4a7-4ff5-8af5-22e0c2188072.png", "01a12399-b8c7-76a0-adb6-39606fe83b65/exec-67db757f-2382-4daa-a63b-cf40d776f66e.png", "01a12399-b8c7-76a0-adb6-39606fe83b65/exec-9a39e856-6fcd-4072-9f6c-24a349a042f8.png"],
    },
    "ACT_B_R02_B": {
        "semantics": ["Head and belly lower; forelegs bend and tail trails down.", "Body coils lower; legs tuck and tail curls around.", "Lizard lies in a compact side coil with head low and eyes closed."],
        "still": "ActorStills/ACT_B_R02_B/ACT_B_R02_B__still__r001.png",
        "sources": ["01a12399-b8c7-76a0-adb6-39606fe83b65/exec-8e9ef002-8003-44ba-b10a-40492661c68e.png", "01a12399-b8c7-76a0-adb6-39606fe83b65/exec-b12bfb54-ee87-441f-af89-18c6ee73e38f.png", "01a12399-b8c7-76a0-adb6-39606fe83b65/exec-37c5fdf2-ac44-4141-8b05-342dea66cd47.png"],
    },
    "ACT_E_R01_01": {
        "semantics": ["Boar begins to kneel; forelegs bend and head lowers.", "Chest sinks closer to ground; legs tuck and tusks angle down.", "Boar lies low on its side with legs tucked and eyes closed."],
        "still": "ActorStills/ACT_E_R01_01/ACT_E_R01_01__still__E_R01_01_MOSS_TUSK_BOAR_sprite_prototype_v2.png",
        "sources": ["01a12399-b8c7-76a0-adb6-39606fe83b65/exec-b625c8b1-0af0-432b-a058-2f5afd1acb5a.png", "01a12399-b8c7-76a0-adb6-39606fe83b65/exec-2f63b40b-5521-4f61-a015-32326fb15648.png", "01a12399-b8c7-76a0-adb6-39606fe83b65/exec-8f16ba63-25c1-448c-a9a8-a925dfa54a9b.png"],
    },
    "ACT_E_R02_01": {
        "semantics": ["Round spore body compresses slightly; short root feet bend.", "Body sinks and tilts to one side; feet tuck and pore closes partly.", "Spore creature rests flattened on its side with pore closed."],
        "still": "ActorStills/ACT_E_R02_01/ACT_E_R02_01__still__r002.png",
        "sources": ["01a12399-b8c7-76a0-adb6-39606fe83b65/exec-1b0fdd46-dde7-42c8-a971-ba40ecb5f335.png", "01a12399-b8c7-76a0-adb6-39606fe83b65/exec-2cc6719e-f146-46d3-8d83-77144267d26e.png", "01a12399-b8c7-76a0-adb6-39606fe83b65/exec-82cdf4d7-e39e-46db-acc8-259b5d17feee.png"],
    },
    "ACT_E_R02_02": {
        "semantics": ["Marsh lizard lowers shoulders and bends forelegs; tail relaxes.", "Belly approaches ground, legs fold, and tail curls gently beside the body.", "Lizard rests in a compact low side coil, head down and eye closed."],
        "still": "ActorStills/ACT_E_R02_02/ACT_E_R02_02__still__r001.png",
        "sources": ["01a12399-b8c7-76a0-adb6-39606fe83b65/exec-19a931d2-f5f0-4138-9c5b-c6f1e91fc415.png", "01a12399-b8c7-76a0-adb6-39606fe83b65/exec-2e954278-b091-455a-898d-a82b4a7bdbaf.png", "01a12399-b8c7-76a0-adb6-39606fe83b65/exec-8e589a54-8e49-4d99-b339-c0d2f610d913.png"],
    },
    "ACT_E_R02_04": {
        "semantics": ["Moon moth descends; body lowers and open wings angle downward.", "Moth lands and partly folds wings around its body.", "Moth rests low with patterned wings wrapped over body and eyes closed."],
        "still": "ActorStills/ACT_E_R02_04/ACT_E_R02_04__still__r001.png",
        "sources": ["01a12399-b8c7-76a0-adb6-39606fe83b65/exec-9c5e5705-2efe-4180-b548-1187c6cb256b.png", "01a12399-b8c7-76a0-adb6-39606fe83b65/exec-ecb8c6bd-2901-4de8-a714-787b189fe7cc.png", "01a12399-b8c7-76a0-adb6-39606fe83b65/exec-a2f78fb2-762d-44a0-90a1-6af650e871c8.png"],
    },
}


def sha(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for block in iter(lambda: f.read(1024 * 1024), b""):
            h.update(block)
    return h.hexdigest()


def atomic(path: Path, data: bytes) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_name(path.name + ".tmp")
    with tmp.open("wb") as f:
        f.write(data)
        f.flush()
        os.fsync(f.fileno())
    os.replace(tmp, path)


def main() -> None:
    entries, records = {}, []
    contact = Image.new("RGB", (3 * 190, len(ACTORS) * 295), (36, 39, 43))
    draw = ImageDraw.Draw(contact)
    for row, (actor, info) in enumerate(ACTORS.items()):
        still = ART / info["still"]
        if not still.is_file():
            raise FileNotFoundError(still)
        base = ART / "GeneratedCandidates" / actor / "resolve_only_r002"
        frames_dir = base / "frames"
        frame_paths, frame_records = [], []
        for i, rel in enumerate(info["sources"]):
            source = GEN / rel
            if not source.is_file():
                raise FileNotFoundError(source)
            with Image.open(source) as im:
                im.load()
                if im.mode != "RGBA":
                    raise ValueError(f"source alpha must be preserved for {actor} frame {i}: {im.mode}")
                source_size = list(im.size)
                fit = ACTOR_FIT_SCALE.get(actor, 1.0)
                fitted = im.resize((round(CANVAS[0] * fit), round(CANVAS[1] * fit)), Image.Resampling.LANCZOS)
                reduced = Image.new("RGBA", CANVAS, (0, 0, 0, 0))
                reduced.alpha_composite(fitted, ((CANVAS[0] - fitted.width)//2, (CANVAS[1] - fitted.height)//2))
            alpha = reduced.getchannel("A").point(lambda v: 255 if v > 16 else 0)
            box = alpha.getbbox()
            if box is None:
                raise ValueError(f"empty frame: {source}")
            x0, y0, x1, y1 = box
            dx, dy = ANCHOR[0] - round((x0 + x1) / 2), ANCHOR[1] - y1
            frame = Image.new("RGBA", CANVAS, (0, 0, 0, 0))
            frame.alpha_composite(reduced, (dx, dy))
            packed_box = frame.getchannel("A").point(lambda v: 255 if v > 16 else 0).getbbox()
            if not packed_box or packed_box[0] < 8 or packed_box[2] > CANVAS[0] - 8 or packed_box[1] < 4 or packed_box[3] > CANVAS[1] - 4:
                raise ValueError(f"unsafe frame gutter {actor} {i}: {packed_box}")
            target = frames_dir / f"resolve_{i:03d}.png"
            b = io.BytesIO(); frame.save(b, "PNG", optimize=True); atomic(target, b.getvalue())
            frame_paths.append(target)
            frame_records.append({"index": i, "semantic_pose": info["semantics"][i], "generated_source_path": str(source), "generated_source_sha256": sha(source), "source_canvas_px": source_size, "actor_clip_constant_fit_scale": ACTOR_FIT_SCALE.get(actor, 1.0), "source_alpha16_bbox_after_uniform_fit_px": list(box), "translation_px": [dx, dy], "packed_path": target.relative_to(ART).as_posix(), "packed_sha256": sha(target), "packed_canvas_px": list(CANVAS), "packed_alpha16_bbox_px": list(packed_box), "anchor_px": list(ANCHOR)})
            comp = Image.new("RGBA", CANVAS, (24, 27, 31, 255)); comp.alpha_composite(frame); comp.thumbnail((180, 260), Image.Resampling.LANCZOS)
            x, y = i * 190 + (190 - comp.width)//2, row * 295 + 25
            contact.paste(comp.convert("RGB"), (x, y)); draw.text((i * 190 + 4, row * 295 + 6), f"{actor} R{i}", fill="white")
        paths = [p.relative_to(ART).as_posix() for p in frame_paths]
        entries[actor] = {"kind": "enemy_actor_kit", "status": "UNAPPROVED_RESOLVE_ONLY_POSE_CANDIDATE", "complete_animation": False, "clips": {"resolve": {"frames": paths, "frame_count": 3, "fps": FPS, "duration_seconds": 0.375, "loop": False, "canvas_px": list(CANVAS), "anchor": list(ANCHOR), "display_scale": 1.0, "status": "UNAPPROVED_AUTHORED_RESOLVE_CANDIDATE", "complete_animation": False, "movement_semantics": " | ".join(info["semantics"]), "anchor_status": "VISUAL_ESTIMATE_UNAPPROVED"}}, "sequenceFrames": {"resolve": paths}}
        records.append({"actorId": actor, "revision": "resolve_only_r002", "status": "UNAPPROVED_AUTHORED_RESOLVE_ONLY_CANDIDATE", "referenceStill": info["still"], "referenceStillSHA256": sha(still), "canvas_px": list(CANVAS), "anchor_px": list(ANCHOR), "fps": FPS, "frames": frame_records, "natural_motion_complete": False})

    overlay_path = ART / "runtime_overlay_zzzzzzzzzz_resolve_candidates_r002.json"
    overlay = {"status": "UNAPPROVED_PARTIAL_MOTION_CANDIDATE_OVERLAY", "complete_animation": False, "human_approval": False, "source_art_untouched": True, "entries": entries}
    atomic(overlay_path, (json.dumps(overlay, ensure_ascii=False, indent=2) + "\n").encode())
    qa = ART / "GeneratedCandidates/resolve_candidates_r002_contact_dark.jpg"
    b = io.BytesIO(); contact.save(b, "JPEG", quality=94); atomic(qa, b.getvalue())
    manifest_path = ART / "GeneratedCandidates/resolve_candidates_manifest_r002.json"
    manifest = {"schema": "witch.enemy_resolve_pose_batch_candidate.v1", "revision": "r002", "status": "UNAPPROVED_CANDIDATE_ONLY", "overlay": overlay_path.relative_to(ART).as_posix(), "qa_contact_dark": qa.relative_to(ART).as_posix(), "actors": records, "source_assets_untouched": True, "human_adoption": False, "complete_animation": False, "limitations": ["Three sampled pose candidates do not prove natural continuous resolve animation.", "Dark composite QA does not replace native screen review.", "Sources are uniformly resized and packed on a shared canvas; source RGB/alpha is not edited."]}
    atomic(manifest_path, (json.dumps(manifest, ensure_ascii=False, indent=2) + "\n").encode())
    print(json.dumps({"overlay": str(overlay_path), "manifest": str(manifest_path), "qa_contact": str(qa), "actors": list(entries)}, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()

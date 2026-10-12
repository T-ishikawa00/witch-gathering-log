#!/usr/bin/env python3
"""Version R005 AIRA measurements with runtime clip-local frame indices."""
from pathlib import Path
import re

source = Path(__file__).with_name("build_aira_landmarks_r005.py")
text = source.read_text()
text = text.replace("r005", "r006")
text = text.replace("'r005'", "'r006'")
text = text.replace("state,fi=next((s,ix) for ix,s,fi in stateIndex[group] if ix==i)",
                    "state,fi=next((s,local_idx) for ix,s,local_idx in stateIndex[group] if ix==i)")
text = text.replace("equipment_semantic_frame_landmarks_r006", "equipment_semantic_frame_landmarks_r006")
text = text.replace("aira_body03_frame_registration_r006", "aira_body03_frame_registration_r006")
text = text.replace("Individual frameIndex now follows runtime clip-local frame arrays; sourceFrameIndex remains the source suffix.",
                    "Runtime frameIndex follows clip-local enumerated arrays; sourceFrameIndex preserves original suffix.")
if "state,fi=next((s,local_idx)" not in text:
    raise SystemExit("failed to patch frame index expression")
exec(compile(text, str(source), "exec"), {"__name__": "__main__", "__file__": str(source)})

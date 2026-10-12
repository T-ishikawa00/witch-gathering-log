#!/usr/bin/env python3
"""Assemble a non-destructive, candidate-only SpriteKit art pack from audited Mac sources.

The source checkout is read-only. Every copied file is byte-hash checked; existing
destination files may only be reused when their bytes already match.
"""
from __future__ import annotations

import csv
import hashlib
import json
import re
import shutil
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
MAC = Path('/Users/PUBLIC_USER/Projects/idle-loot-rpg')
PROD = MAC / 'assets/g2/production/codex_unified_20261008T221040Z_fa70940c'
REFINE = MAC / 'assets/g2/production/codex_refinement_20261010T013601JST_49a31ab7'
R008_ASSETS = REFINE / 'game/native_r008/WitchG2Refinement.app/Assets'
LEDGER = MAC / 'docs/qa/g2_refinement_20261010_r002/UPDATED_159_LEDGER_R002.csv'
STATIC14 = MAC / 'docs/qa/g2_refinement_20261010_r002/STATIC14_R006.json'
DEST = ROOT / 'native/Art'
PNG = '.png'


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open('rb') as f:
        for block in iter(lambda: f.read(1024 * 1024), b''):
            h.update(block)
    return h.hexdigest()


def copy_record(asset_id: str, category: str, status: str, source: Path,
                relative: Path, source_role: str, source_revision: str | None = None) -> dict:
    if not source.is_file():
        raise FileNotFoundError(source)
    target = DEST / relative
    target.parent.mkdir(parents=True, exist_ok=True)
    source_hash = sha256(source)
    if target.exists():
        target_hash = sha256(target)
        if source_hash != target_hash:
            raise RuntimeError(f'refusing to overwrite differing destination: {target}')
    else:
        shutil.copyfile(source, target)
        target_hash = sha256(target)
        if source_hash != target_hash:
            raise RuntimeError(f'copy hash mismatch: {target}')
    return {
        'asset_id': asset_id,
        'category': category,
        'asset_stage': status,
        'source_role': source_role,
        'source_revision': source_revision,
        'source_path': str(source),
        'bundle_relative_path': str(relative),
        'sha256': source_hash,
        'bytes': target.stat().st_size,
        'pixel_metadata': image_metadata(target),
    }


def image_metadata(path: Path) -> dict:
    try:
        from PIL import Image
        with Image.open(path) as image:
            return {'width': image.width, 'height': image.height,
                    'mode': image.mode, 'format': image.format}
    except Exception:
        return {'width': None, 'height': None, 'mode': None, 'format': 'PNG_UNREADABLE'}


def mapped_path(asset_id: str, kind: str, role: str, src: Path) -> Path:
    name = src.name
    if kind == 'enemy_actor_kit':
        if role == 'runtime_actor_frame' or role.startswith('runtime_actor_frame'):
            # State folders retain the clip identity so e.g. idle/001.png and
            # execute/001.png cannot collide in the Bundle namespace.
            return Path('Enemies') / asset_id / src.parent.name / name
        return Path('ActorStills') / asset_id / f'{asset_id}__still__{name}'
    if kind == 'background_kit':
        return Path('Backgrounds') / asset_id / name
    if kind == 'area_variant':
        return Path('BackgroundVariants') / asset_id / name
    if kind == 'gear_icon':
        return Path('GearIcons') / asset_id / name
    if kind == 'material_icon':
        return Path('MaterialIcons') / asset_id / name
    if kind == 'gather_prop':
        return Path('GatherProps') / asset_id / name
    return Path('Candidates') / asset_id / name


def keep_role(kind: str, role: str, src: Path) -> bool:
    role_l = role.lower()
    if src.suffix.lower() != PNG:
        return False
    if kind == 'enemy_actor_kit':
        return role.startswith('runtime_actor_frame') or role in {
            'source', 'protected_existing_source', 'runtime_candidate', 'runtime_256'
        }
    if kind == 'background_kit':
        return role.startswith('runtime_layer_candidate') or role in {
            'runtime_flat_candidate', 'source_layer_far', 'source_layer_back',
            'source_layer_playfield', 'source_layer_front', 'protected_existing_source'
        }
    if kind == 'area_variant':
        return role.startswith('runtime_') or role == 'source'
    if kind in ('gear_icon', 'material_icon'):
        return role in ('runtime_64', 'runtime_128', 'runtime_256')
    if kind == 'gather_prop':
        return role in ('runtime_present_64', 'runtime_present_128', 'runtime_present_256',
                        'runtime_collected_64', 'runtime_collected_128', 'runtime_collected_256')
    return False


def main() -> None:
    DEST.mkdir(parents=True, exist_ok=True)
    ledger = list(csv.DictReader(LEDGER.open(encoding='utf-8')))
    latest = {r['asset_id']: r for r in ledger}
    records: list[dict] = []
    unit_rows: list[dict] = []
    manifest_root = PROD / 'deliveries'

    # Current audited app files: 24 discrete character poses, R01 six-state
    # enemy sequence, 80 cue frames, and five field layers. These are candidates.
    for src in sorted(R008_ASSETS.rglob('*.png')):
        rel = src.relative_to(R008_ASSETS)
        parts = rel.parts
        if parts[0] == 'Characters':
            asset_id = parts[1]
            category = 'party_character_pose'
            status = 'STATIC_POSE_CANDIDATE_FULL_ANIMATION_INTEGRATION_REQUIRED'
            target = rel
        elif parts[0] == 'Enemies':
            asset_id = parts[1]
            category = 'enemy_actor_kit'
            status = latest.get(asset_id, {}).get('stage', 'PARTIAL_NATIVE_FRAME_SEQUENCE')
            target = rel
        elif parts[0] == 'Background':
            asset_id = 'BG_R01_FIELD'
            category = 'background_kit'
            status = latest.get(asset_id, {}).get('stage', 'PARTIAL_NATIVE_LAYER_SET')
            target = Path('Backgrounds') / asset_id / src.name
        else:
            # Keep effects named by their original stable actor/environment IDs.
            category = 'regional_effect_candidate'
            match = re.match(r'((?:ACT_[BE]_R\d{2}_[A-Z0-9]+)|ENV_R\d{2}_\d{2})', src.stem)
            asset_id = match.group(1) if match else 'FX_R01'
            status = 'PARTIAL_NATIVE_REPLAY_CUE_NOT_FULL_KIT'
            target = Path('Effects') / asset_id / src.name
        records.append(copy_record(asset_id, category, status, src, target,
                                   'native_r008_app_asset', 'R008'))

    # Include the current runtime-sized candidate outputs (all existing frames
    # and state variants) from the 159-item art ledger. No absent assets are
    # synthesized and no non-runtime contact sheets are imported.
    for row in ledger:
        asset_id, kind, stage = row['asset_id'], row['kind'], row['stage']
        manifest = manifest_root / asset_id / 'delivery_manifest_r001.json'
        before = len(records)
        if manifest.is_file():
            payload = json.loads(manifest.read_text(encoding='utf-8'))
            for file_row in payload.get('files', []):
                source = Path(file_row.get('path', ''))
                role = file_row.get('role', 'unknown')
                if not keep_role(kind, role, source) or not source.is_file():
                    continue
                records.append(copy_record(asset_id, kind, stage, source,
                    mapped_path(asset_id, kind, role, source), role, row['revision']))
        copied = len(records) - before
        unit_rows.append({'asset_id': asset_id, 'region_id': row['region_id'], 'kind': kind,
                          'display_name': row['display_name'], 'stage': stage,
                          'full_r4_kit_complete': row['full_r4_kit_complete'],
                          'human_adoption': row['Human_adoption'],
                          'physical_iphone': row['physical_iPhone'],
                          'candidate_png_count_from_delivery_manifest': copied,
                          'result': 'CANDIDATE_FILES_COPIED' if copied else 'NO_RUNTIME_PNG_IN_BASE_DELIVERY'})

    # Latest static repair candidates: keep only named runtime candidates, not
    # rejection boards, matte comparisons, or source-edit layers.
    repair_index = json.loads(STATIC14.read_text(encoding='utf-8'))
    for item in repair_index.get('items', []):
        asset_id = item['asset_id']
        for index, entry in enumerate(item.get('runtime_candidate', [])):
            source = MAC / entry['path']
            if not source.is_file() or source.suffix.lower() != PNG:
                continue
            disposition = (entry.get('disposition') or '').lower()
            if 'reject' in disposition:
                continue
            # The caller can see the exact status in the asset manifest.
            records.append(copy_record(asset_id, latest.get(asset_id, {}).get('kind', 'static_repair'),
                item.get('overall_status', 'UNRESOLVED_NO_PROMOTION'), source,
                Path('StaticRepairCandidates') / asset_id / f'{index:02d}_{source.name}',
                'latest_runtime_candidate_unapproved', 'STATIC14_R006_latest_candidate'))

    # The latest 21-actor comparison projects include real standalone PNGs,
    # but they are one static illustration each, never an animation kit.
    actor_root = REFINE / 'actors'
    for actor_dir in sorted(actor_root.glob('ACT_*')):
        if not actor_dir.is_dir():
            continue
        candidates = []
        for source in actor_dir.rglob('*__runtime_candidate__r*.png'):
            # Ignore edited/rejected alternates; retain the highest numbered
            # ordinary candidate revision within this actor's directory.
            if 'imagegen_edit' in str(source).lower() or 'rejected' in str(source).lower():
                continue
            rev = re.search(r'__runtime_candidate__r(\d+)', source.name)
            candidates.append((int(rev.group(1)) if rev else 0, source))
        if not candidates:
            continue
        _, source = max(candidates, key=lambda pair: pair[0])
        aid = actor_dir.name
        row = latest.get(aid, {})
        records.append(copy_record(aid, 'enemy_actor_kit',
            row.get('stage', 'STATIC_CANDIDATE_ANIMATION_MISSING'), source,
            Path('ActorStills') / aid / f'{aid}__still__{source.name.split("__runtime_candidate__")[1]}',
            'latest_actor_still_candidate_animation_missing', source.parent.name))

    # Full-frame background/area images from the R4 refinement delivery are
    # review candidates only. Preserve them by stable ID and keep them separate
    # from layered runtime backgrounds.
    for unit in ledger:
        if unit['kind'] not in ('background_kit', 'area_variant'):
            continue
        asset_id = unit['asset_id']
        candidate_dirs = sorted(REFINE.glob(f'background/new_12_delivery_r*/{asset_id}/runtime'))
        for runtime_dir in candidate_dirs:
            for source in sorted(runtime_dir.glob('*.png')):
                records.append(copy_record(asset_id, unit['kind'],
                    'FULLFRAME_LAYOUT_REVIEW_CANDIDATE_LAYERS_MISSING', source,
                    Path('BackgroundPreviews') / asset_id / source.name,
                    'fullframe_review_candidate_layers_missing', runtime_dir.parent.name))

    # Rebuild only the manifest. Files from the earlier r001 pose pack are
    # included through their source-app counterparts and are hash-checked.
    packed = {'schema': 'witch-ios-art-candidate-manifest-r002',
        'status': 'CANDIDATES_ONLY_NO_HUMAN_ADOPTION_NO_PRODUCTION_ACCEPTANCE',
        'source_checkout': str(MAC), 'source_is_read_only': True,
        'authority_reference': {'path': 'docs/design/visual/witch_characters_R1.png',
            'sha256': sha256(ROOT / 'docs/design/visual/witch_characters_R1.png'),
            'role': 'top-level approved character appearance reference; opaque contact sheet, not runtime sprites'},
        'export_contract': {'basis': 'docs/design/sources/all_regions_r4/Witch_AllRegions_ArtSpec_R4_20261009/docs/03_ANIMATION_EXPORT_CONTRACT.md',
            'actor_states': ['idle','anticipate','execute','recover','hit','resolve'],
            'transparent_alpha_and_anchor_metadata_required': True,
            'frame_sequence_or_cutout_source_required': True,
            'stills_and_MP4_alone_do_not_pass_animation': True,
            'ios_device_test': 'NOT_TESTED'},
        'counts': {'catalog_units': len(unit_rows),
            'copied_png_records_including_aliases': len(records),
            'copied_png_bytes_including_aliases': sum(r['bytes'] for r in records),
            'unique_asset_ids_with_copied_png': len({r['asset_id'] for r in records})},
        'catalog_units': unit_rows, 'files': records,
        'gaps': {'cat_equipment': {'required_count': 4, 'stable_ids': 'UNKNOWN_IN_CURRENT_SOURCE',
            'status': 'NO_CANONICAL_CAT_EQUIPMENT_ROWS_OR_RUNTIME_PNGS_IN_159_CATALOG'},
            'costumes_and_furniture': {'status': 'DESIGN_CANDIDATES_ONLY_NO_RUNTIME_ART_OR_STABLE_IDS',
            'source': 'docs/design/shared/20261010_r1/sources/commerce_r2/'},
            'ui_a': {'status': 'DIRECTION_REFERENCE_ONLY_NOT_RUNTIME_ASSET',
                'source': 'docs/design/shared/20261010_r1/sources/ui_a/UI_DIRECTION_R2_AB_ORIGINAL.png'}}}
    out = DEST / 'asset_manifest_r002.json'
    out.write_text(json.dumps(packed, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    counts = Counter(r['category'] for r in records)
    print(json.dumps({'manifest': str(out), 'file_records': len(records),
                      'unique_asset_ids': len({r['asset_id'] for r in records}),
                      'bytes': sum(r['bytes'] for r in records),
                      'by_category': counts}, ensure_ascii=False, indent=2))


if __name__ == '__main__':
    main()

#!/usr/bin/env python3
"""Add verified regional candidates and emit a scene-consumer runtime index.

All imported files remain unapproved candidate art. Sources are read-only; all
copies are SHA-256 checked and never overwrite differing destination bytes.
"""
from __future__ import annotations

import hashlib
import json
import re
import shutil
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
MAC = Path('/Users/PUBLIC_USER/Projects/idle-loot-rpg')
DEST = ROOT / 'native/Art'
MANIFEST_PATH = DEST / 'asset_manifest_r002.json'
REF = MAC / 'assets/g2/production/codex_refinement_20261010T013601JST_49a31ab7'
INTEGRATION = MAC / 'assets/g2/production/codex_integration_20261009T133015Z_ddbec58c'
UNIFIED = MAC / 'assets/g2/production/codex_unified_20261008T221040Z_fa70940c'
ACTOR_STATES = ['idle', 'walk', 'anticipate', 'execute', 'recover', 'hit', 'resolve']


def digest(p: Path) -> str:
    h = hashlib.sha256()
    with p.open('rb') as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b''):
            h.update(chunk)
    return h.hexdigest()


def image_meta(p: Path) -> dict:
    try:
        from PIL import Image
        with Image.open(p) as im:
            return {'width': im.width, 'height': im.height,
                    'mode': im.mode, 'format': im.format}
    except Exception:
        return {'width': None, 'height': None, 'mode': None, 'format': 'PNG_UNREADABLE'}


def copy_verified(asset_id: str, category: str, status: str, source: Path,
                  rel: Path, role: str, revision: str) -> dict:
    if not source.is_file():
        raise FileNotFoundError(source)
    target = DEST / rel
    target.parent.mkdir(parents=True, exist_ok=True)
    source_hash = digest(source)
    if target.exists():
        if digest(target) != source_hash:
            raise RuntimeError(f'refusing to overwrite differing asset: {target}')
    else:
        shutil.copyfile(source, target)
        if digest(target) != source_hash:
            raise RuntimeError(f'copy hash mismatch: {target}')
    return {'asset_id': asset_id, 'category': category, 'asset_stage': status,
            'source_role': role, 'source_revision': revision,
            'source_path': str(source), 'bundle_relative_path': str(rel),
            'sha256': source_hash, 'bytes': target.stat().st_size,
            'pixel_metadata': image_meta(target)}


def catalog_by_kind(manifest: dict, category: str) -> list[dict]:
    return [u for u in manifest['catalog_units'] if u['kind'] == category]


def regional_source_additions(m: dict) -> list[dict]:
    additions = []
    # Regional full-frame scene candidates missing from the latest app bundle.
    bg_sources = {
        'BG_R03_FIELD': INTEGRATION / 'actualN/background/regional_continuation/BG_R03_FIELD/runtime/BG_R03_FIELD__candidate_r001.png',
        'BG_R04_FIELD': INTEGRATION / 'background/regional_continuation/BG_R04_FIELD/r001/runtime/BG_R04_FIELD__source_candidate_r001.png',
        'BG_R05_FIELD': INTEGRATION / 'background/regional_continuation/BG_R05_FIELD/r002_lighting/runtime/BG_R05_FIELD__source_candidate_r002_lighting.png',
    }
    for aid, src in bg_sources.items():
        revision = 'r002_lighting' if aid == 'BG_R05_FIELD' else 'r001'
        additions.append(copy_verified(aid, 'background_kit', 'REGIONAL_FULLFRAME_SOURCE_CANDIDATE_NOT_FULL_R4_KIT', src,
            Path('Backgrounds') / aid / f'{aid}__field_source_candidate__{revision}.png',
            'regional_source_candidate_flat_not_layered', revision))

    # Use the newest checked runtime effect manifest available per region:
    # R01 baseline and R02-R05 r002 (128px masters, eight timed frames each).
    for region in range(1, 6):
        rev = 1 if region == 1 else 2
        mf = INTEGRATION / 'effects' / f'R{region:02d}' / f'effect_manifest_r{rev:03d}.json'
        data = json.loads(mf.read_text(encoding='utf-8'))
        for group_name in ('environment_effects', 'combat_effects'):
            for effect in data.get(group_name, []):
                effect_id = effect['effect_id']
                # R01 combat IDs are source-specific cues. Keep them grouped
                # under the canonical actor ID when possible to reuse R008.
                stable_actor = re.match(r'(ACT_[BE]_R\d{2}_[A-Z0-9]+)', effect_id)
                if stable_actor:
                    folder_id = stable_actor.group(1)
                else:
                    folder_id = effect_id
                for frame in effect.get('frames', []):
                    source = Path(frame['path'])
                    additions.append(copy_verified(effect_id, 'regional_effect_candidate',
                        'ANIMATED_EFFECT_TIMED_CANDIDATE_NOT_GAME_INTEGRATED', source,
                        Path('Effects') / folder_id / source.name,
                        group_name, f'R{region:02d}_effect_manifest_r{rev:03d}'))
    # New R01 canopy shadow overlay is a separate option, not a replacement
    # for ENV_R01_03's canonical 8-frame set.
    variant = INTEGRATION / 'effects/R01/canopy_shadow_alpha_compare_r003/effect_variant_manifest_r003.json'
    vd = json.loads(variant.read_text(encoding='utf-8'))
    for frame in vd.get('frames', []):
        source = Path(frame['path'])
        additions.append(copy_verified('ENV_R01_03', 'regional_effect_candidate',
            'ALPHA_OVERLAY_VARIANT_REVIEW_CANDIDATE', source,
            Path('Effects/ENV_R01_03') / source.name,
            'additional_canopy_shadow_variant', 'R003'))
    return additions


def selected_file(files: list[dict], aid: str, category: str, predicate) -> dict | None:
    options = [f for f in files if f['asset_id'] == aid and f['category'] == category and predicate(f)]
    return sorted(options, key=lambda f: f['bundle_relative_path'])[0] if options else None


def runtime_index(m: dict) -> dict:
    files = m['files']
    units = m['catalog_units']
    entries: dict[str, dict] = {}
    for unit in units:
        aid, kind = unit['asset_id'], unit['kind']
        if kind == 'gear_icon':
            f = selected_file(files, aid, kind, lambda x: x['pixel_metadata']['width'] == 128 and x['pixel_metadata']['height'] == 128)
            entries[aid] = {'kind': kind, 'selectedPNG': f['bundle_relative_path'] if f else None,
                'pixelSize': [128, 128] if f else None, 'status': 'STATIC_ICON_CANDIDATE' if f else 'MISSING',
                'humanAdoption': unit.get('human_adoption', 'PENDING_INDIVIDUAL')}
        elif kind == 'material_icon':
            f = selected_file(files, aid, kind, lambda x: x['pixel_metadata']['width'] == 128 and x['pixel_metadata']['height'] == 128)
            entries[aid] = {'kind': kind, 'selectedPNG': f['bundle_relative_path'] if f else None,
                'pixelSize': [128, 128] if f else None, 'status': 'STATIC_ICON_CANDIDATE' if f else 'MISSING',
                'humanAdoption': unit.get('human_adoption', 'PENDING_INDIVIDUAL')}
        elif kind == 'gather_prop':
            phases = {}
            for phase in ('present', 'collected'):
                f = selected_file(files, aid, kind,
                    lambda x: phase in x['source_role'] and x['pixel_metadata']['width'] == 128 and x['pixel_metadata']['height'] == 128)
                phases[phase] = f['bundle_relative_path'] if f else None
            entries[aid] = {'kind': kind, 'selectedPNG': phases, 'pixelSize': [128, 128],
                'status': 'TWO_STATE_STATIC_CANDIDATES' if all(phases.values()) else 'PARTIAL_OR_MISSING'}
        elif kind == 'party_character_pose':
            poses = [f for f in files if f['asset_id'] == aid and f['category'] == kind]
            by_state = {}
            for f in poses:
                match = re.search(r'__(idle|anticipate|execute|recover|hit|resolve)__', f['bundle_relative_path'])
                if match:
                    by_state[match.group(1)] = f['bundle_relative_path']
            entries[aid] = {'kind': kind, 'selectedPNG': by_state, 'states_present': sorted(by_state),
                'status': '24_STATIC_POSES_ANIMATION_INTEGRATION_REQUIRED', 'fps': None,
                'canvas_px': [256, 256], 'anchor': None, 'anchor_status': 'UNKNOWN_NOT_SUPPLIED',
                'animation': 'STATIC_DISCRETE_POSES_NOT_CONTINUOUS_CLIPS'}
        elif kind == 'enemy_actor_kit':
            seq_files = [f for f in files if f['asset_id'] == aid and f['category'] == kind and f['bundle_relative_path'].startswith(f'Enemies/{aid}/')]
            still_files = [f for f in files if f['asset_id'] == aid and f['category'] == kind and f['bundle_relative_path'].startswith(f'ActorStills/{aid}/') and 'parts_atlas' not in f['bundle_relative_path'].lower()]
            states: dict[str, list[str]] = defaultdict(list)
            flat_frames = []
            for f in seq_files:
                rel = f['bundle_relative_path']
                p = Path(rel)
                if p.parent.name in ACTOR_STATES:
                    states[p.parent.name].append(rel)
                elif re.match(r'(idle|walk|anticipate|execute|recover|hit|resolve)_\d+\.png$', p.name):
                    st = re.match(r'([a-z]+)_', p.name).group(1)
                    states[st].append(rel)
                elif p.parent.name == 'frames':
                    flat_frames.append(rel)
            for st in states:
                states[st].sort()
            still = sorted(still_files, key=lambda x: x['bundle_relative_path'])[0] if still_files else None
            selected = {st: paths for st, paths in sorted(states.items())}
            if flat_frames:
                selected['all_frames'] = sorted(flat_frames)
            entries[aid] = {'kind': kind, 'selectedPNG': still['bundle_relative_path'] if still else None,
                'sequenceFrames': selected or None,
                'states_present': sorted(states), 'status': 'FRAME_SEQUENCE_CANDIDATE' if states or flat_frames else ('STATIC_FULL_BODY_CANDIDATE_ANIMATION_MISSING' if still else 'NO_USABLE_FULL_BODY_PNG'),
                'fps': None, 'canvas_px': still['pixel_metadata'] and [still['pixel_metadata']['width'], still['pixel_metadata']['height']] if still else None,
                'anchor': None, 'anchor_status': 'SEE_CLIP_METADATA_WHEN_AVAILABLE' if states or flat_frames else 'UNKNOWN_NOT_SUPPLIED',
                'partsAtlasExcluded': True}
        elif kind == 'background_kit':
            imgs = [f for f in files if f['asset_id'] == aid and f['category'] == kind]
            chosen = next((f for f in imgs if 'source_candidate' in f['bundle_relative_path']), None)
            if chosen is None:
                chosen = next((f for f in imgs if f['source_role'] == 'fullframe_review_candidate_layers_missing'), None)
            layers = [f for f in imgs if f['source_role'] in ('native_r008_app_asset', 'runtime_layer_candidate', 'runtime_flat_candidate', 'protected_existing_source')]
            entries[aid] = {'kind': kind,
                'selectedPNG': chosen['bundle_relative_path'] if chosen else None,
                'layers': [f['bundle_relative_path'] for f in layers] if layers else None,
                'status': ('FULLFRAME_REVIEW_CANDIDATE_LAYERS_MISSING' if chosen['source_role'] == 'fullframe_review_candidate_layers_missing' else 'FLAT_SOURCE_CANDIDATE_NOT_FULL_KIT') if chosen else ('PARTIAL_LAYERED_CANDIDATE' if layers else 'MISSING'),
                'humanAdoption': unit.get('human_adoption', 'PENDING_INDIVIDUAL')}
        elif kind == 'area_variant':
            f = selected_file(files, aid, kind, lambda x: x['source_role'] == 'fullframe_review_candidate_layers_missing')
            entries[aid] = {'kind': kind, 'selectedPNG': f['bundle_relative_path'] if f else None,
                'status': 'FULLFRAME_REVIEW_CANDIDATE_LAYERS_MISSING' if f else 'MISSING'}

    # Promote missing field IDs from the canonical background coverage into
    # index with the newly sourced, explicitly provisional candidate.
    for aid in ('BG_R03_FIELD', 'BG_R04_FIELD', 'BG_R05_FIELD'):
        f = next((x for x in files if x['asset_id'] == aid and x['source_role'] == 'regional_source_candidate_flat_not_layered'), None)
        entries[aid] = {'kind': 'background_kit', 'selectedPNG': f['bundle_relative_path'] if f else None,
            'layers': None, 'status': 'FLAT_SOURCE_CANDIDATE_NOT_FULL_KIT' if f else 'MISSING',
            'sourceRevision': f['source_revision'] if f else None,
            'humanAdoption': 'PENDING'}

    effects: dict[str, dict] = {}
    for f in files:
        if f['category'] != 'regional_effect_candidate':
            continue
        if f['source_role'] == 'native_r008_app_asset':
            continue
        effect_id = f['asset_id']
        entry = effects.setdefault(effect_id, {'selectedPNG': [], 'frames': [], 'status': 'ANIMATED_EFFECT_CANDIDATE_NOT_GAME_INTEGRATED'})
        # Only manifest-timed frames are in the canonical sequence; keep
        # special variants discoverable but outside the automatic frame set.
        record = {'path': f['bundle_relative_path'], 'sha256': f['sha256'],
                  'canvas_px': [f['pixel_metadata']['width'], f['pixel_metadata']['height']]}
        if f['source_role'] in ('environment_effects', 'combat_effects'):
            entry['frames'].append(record)
        elif f['source_role'] == 'additional_canopy_shadow_variant':
            entry.setdefault('optionalVariants', []).append(record)
    # Restore source timing and grouping from the checked regional manifests.
    effect_groups = {}
    for region in range(1, 6):
        rev = 1 if region == 1 else 2
        mf = INTEGRATION / 'effects' / f'R{region:02d}' / f'effect_manifest_r{rev:03d}.json'
        data = json.loads(mf.read_text(encoding='utf-8'))
        for name, kit in (('environment_effects', f'ENV_R{region:02d}'), ('combat_effects', f'FX_R{region:02d}')):
            effect_groups.setdefault(kit, {'effectIds': [], 'status': 'CANDIDATE_FRAME_SEQUENCES_NOT_FULL_GAME_INTEGRATED'})
            for eff in data.get(name, []):
                eid = eff['effect_id']; effect_groups[kit]['effectIds'].append(eid)
                e = effects.setdefault(eid, {'frames': [], 'status': 'ANIMATED_EFFECT_CANDIDATE_NOT_GAME_INTEGRATED'})
                ordered = []
                for frame in eff.get('frames', []):
                    base = Path(frame['path']).name
                    match = next((f for f in files if f['asset_id'] == eid and Path(f['bundle_relative_path']).name == base), None)
                    if match:
                        ordered.append({'path': match['bundle_relative_path'], 'sha256': match['sha256'],
                                        'duration_ms': frame.get('duration_ms'), 'canvas_px': [128, 128]})
                e['frames'] = ordered
                e['selectedPNG'] = ordered[0]['path'] if ordered else None
                e['fps'] = 8 if ordered and all(x.get('duration_ms') == 125 for x in ordered) else None
                e['canvas_px'] = [128, 128] if ordered else None
                e['anchor'] = 'normalized_scene_anchor_at_runtime' if ordered else None
                e['anchor_status'] = 'CONTRACT_CALLER_SUPPLIES_NORMALIZED_ANCHOR' if ordered else 'UNKNOWN'
                e['loop'] = True if ordered else None
    for kit in effect_groups.values():
        kit['effectIds'].sort()

    # Character poses are tracked outside the 159-unit game-art ledger.
    # Expose all 24 candidate poses under the four canonical runtime IDs.
    for aid in ('ERNA', 'LUNA', 'AIRA', 'NOIR'):
        poses = [f for f in files if f['asset_id'] == aid and f['category'] == 'party_character_pose']
        by_state = {}
        for f in poses:
            match = re.search(r'__(idle|anticipate|execute|recover|hit|resolve)__', f['bundle_relative_path'])
            if match:
                by_state[match.group(1)] = f['bundle_relative_path']
        entries[aid] = {'kind':'party_character_pose', 'selectedPNG':by_state,
            'states_present':sorted(by_state), 'status':'STATIC_POSE_CANDIDATE_FULL_ANIMATION_INTEGRATION_REQUIRED',
            'canvas_px':[256,256], 'anchor':None, 'anchor_status':'UNKNOWN_NOT_SUPPLIED',
            'fps':None, 'animation':'STATIC_DISCRETE_POSES_NOT_CONTINUOUS_CLIPS'}

    # Attach actor clip metadata only where a concrete source contract exists.
    for aid in ('ACT_E_R01_01', 'ACT_E_R02_03', 'ACT_B_R03_A'):
        if aid not in entries:
            continue
        if aid == 'ACT_E_R01_01':
            meta_path = INTEGRATION / 'actors/ACT_E_R01_01/spritekit_manifest_r001.json'
            meta = json.loads(meta_path.read_text(encoding='utf-8'))
            clips = {}
            for state, clip in meta['states'].items():
                names = [Path(x).name for x in clip['frames']]
                actual = [x for x in entries[aid]['sequenceFrames'].get(state, [])]
                clips[state] = {'frames': actual, 'frame_count': len(actual), 'fps': clip.get('fps'),
                    'duration_seconds': clip.get('duration_seconds'), 'loop': clip.get('loop'),
                    'canvas_px': clip.get('canvas_px'), 'anchor': clip.get('foot_anchor_px'),
                    'anchor_type': 'foot_anchor_px', 'metadata_source': str(meta_path)}
            entries[aid].update({'clips': clips, 'fps': 24, 'canvas_px': [768,512],
                'anchor': {'type':'foot_anchor_px','value_px':[415,450]},
                'status': 'SIX_STATE_FRAME_SEQUENCE_TECH_CANDIDATE_NOT_GAME_INTEGRATED'})
        elif aid == 'ACT_E_R02_03':
            meta_path = INTEGRATION / 'actors/ACT_E_R02_03/runtime/manifest_r003.json'
            meta = json.loads(meta_path.read_text(encoding='utf-8'))
            clips = {}
            all_frames = entries[aid]['sequenceFrames'].get('all_frames', [])
            for state in meta['runtime']['states']:
                start = state['first_frame']; count = state['frame_count']
                clips[state['id']] = {'frames': all_frames[start:start+count], 'frame_count': count,
                    'fps': meta['runtime']['fps'], 'duration_seconds': state['duration_seconds'],
                    'loop': state['loop']}
            # The source contract's pixel anchors exceed its declared 384x256
            # output canvas. Retain values as evidence but do not pass them to
            # the renderer until corrected.
            entries[aid].update({'clips': clips, 'fps': meta['runtime']['fps'],
                'canvas_px': meta['runtime']['canvas_px'],
                'anchor': meta['runtime']['target_anchors'],
                'states_present':sorted(clips),
                'anchor_status': 'SOURCE_CONTRACT_COORDINATES_OUTSIDE_OUTPUT_CANVAS_UNRESOLVED',
                'status': 'SIX_STATE_FRAME_SEQUENCE_CANDIDATE_ANCHOR_CONTRACT_INVALID'})
        else:
            meta_path = UNIFIED / 'runtime/hammer_r004/delivery_manifest_r004.json'
            meta = json.loads(meta_path.read_text(encoding='utf-8'))
            clips = {}
            for state, clip in meta['clips'].items():
                actual = entries[aid]['sequenceFrames'].get(state, [])
                clips[state] = {'frames': actual, 'frame_count': len(actual),
                    'fps': clip.get('fps'), 'duration_seconds': clip.get('duration_s'),
                    'loop': clip.get('loop'), 'status': clip.get('status')}
            entries[aid].update({'clips': clips, 'fps': 24, 'canvas_px': meta['canvas_px'],
                'anchor': meta['registration']['foot_registration_xy'],
                'anchor_type': 'foot_registration_xy',
                'status': 'FIVE_STATE_FRAME_SEQUENCE_RESOLVE_MISSING_TECH_CANDIDATE'})

    # Populate explicit catalog gaps for actor state coverage and requested IDs.
    requested_bg_ids = [f'BG_R{r:02d}_{t}' for r in range(1, 6) for t in ('FIELD', 'BOSS')]
    for aid in requested_bg_ids:
        entries.setdefault(aid, {'kind':'background_kit','selectedPNG':None,'layers':None,'status':'NO_RUNTIME_CANDIDATE'})
    for aid in ['ENV_R%02d' % r for r in range(1,6)] + ['FX_R%02d' % r for r in range(1,6)]:
        entries[aid] = {'kind': 'effect_kit', **effect_groups.get(aid, {'effectIds': [], 'status':'MISSING'})}

    status_counts = defaultdict(int)
    for x in entries.values(): status_counts[x['kind']] += 1
    # Exact minimal Bundle payload for a consumer that does not add the entire
    # candidate-review folder. Keeps unselected size variants and alternates out.
    payload_paths: set[str] = set()
    def collect_selected(value):
        if isinstance(value, str) and value.endswith('.png'):
            payload_paths.add(value)
        elif isinstance(value, dict):
            for child in value.values(): collect_selected(child)
        elif isinstance(value, list):
            for child in value: collect_selected(child)
    for entry in entries.values():
        collect_selected(entry.get('selectedPNG'))
        collect_selected(entry.get('layers'))
        collect_selected(entry.get('sequenceFrames'))
        for clip in entry.get('clips', {}).values(): collect_selected(clip.get('frames'))
    for effect in effects.values(): collect_selected([x['path'] for x in effect.get('frames', [])])
    record_by_path = {}
    for f in files:
        record_by_path.setdefault(f['bundle_relative_path'], f)
    bundle_payload = []
    for path in sorted(payload_paths):
        f = record_by_path.get(path)
        physical = DEST / path
        bundle_payload.append({'path':path, 'sha256':f['sha256'] if f else digest(physical),
            'bytes':f['bytes'] if f else physical.stat().st_size})
    return {'schema': 'witch_scene_runtime_index_r001',
        'status': 'candidate_asset_resolution_only_not_human_adopted_or_device_verified',
        'bundle_root': 'native/Art',
        'path_convention': 'paths are Bundle-relative from native/Art; selectedPNG null means runtime art absent',
        'source_authority': {'asset_manifest':'asset_manifest_r002.json',
            'animation_export_contract':'docs/design/sources/all_regions_r4/Witch_AllRegions_ArtSpec_R4_20261009/docs/03_ANIMATION_EXPORT_CONTRACT.md',
            'original_sources_read_only': True},
        'actor_state_contract': ACTOR_STATES,
        'actor_contract_note': 'Only enumerated frame clips count as animation candidates. A still or 24 key poses are never clip completion.',
        'counts_by_kind': dict(sorted(status_counts.items())),
        'minimal_bundle_payload': {'files':bundle_payload, 'unique_file_count':len(bundle_payload),
            'bytes':sum(x['bytes'] for x in bundle_payload),
            'rule':'selected PNGs, layers, enumerated actor frames, clip frames and effect frames only; excludes unselected size variants, preview alternatives, and optional variants'},
        'entries': dict(sorted(entries.items())),
        'effects': dict(sorted(effects.items()))}


def main() -> None:
    manifest = json.loads(MANIFEST_PATH.read_text(encoding='utf-8'))
    # A previous staging pass left exact-byte flat aliases for two actor frame
    # sets. Do not select or copy them again; account for their on-disk paths so
    # the bundle manifest remains exhaustive and transparent about duplication.
    known_paths = {x['bundle_relative_path'] for x in manifest['files']}
    hashes_by_actor: dict[str, dict[str, dict]] = defaultdict(dict)
    for row in manifest['files']:
        if row['category'] == 'enemy_actor_kit':
            hashes_by_actor[row['asset_id']].setdefault(row['sha256'], row)
    for actor_id in ('ACT_B_R03_A', 'ACT_E_R02_03'):
        for path in sorted((DEST / 'Enemies' / actor_id).glob('*.png')):
            rel = path.relative_to(DEST).as_posix()
            if rel in known_paths:
                continue
            sha = digest(path)
            match = hashes_by_actor[actor_id].get(sha)
            if not match:
                raise RuntimeError(f'unmapped pre-existing actor alias: {path}')
            alias = dict(match)
            alias.update({'source_role':'preexisting_flat_alias_duplicate_not_selected',
                'source_revision':'preexisting_bundle_alias_audit_r001',
                'bundle_relative_path':rel,'sha256':sha,'bytes':path.stat().st_size,
                'pixel_metadata':image_meta(path)})
            manifest['files'].append(alias)
            known_paths.add(rel)
    # Avoid duplicate manifest rows if this script is re-run.
    existing_keys = {(x['asset_id'], x['bundle_relative_path']) for x in manifest['files']}
    additions = [x for x in regional_source_additions(manifest)
                 if (x['asset_id'], x['bundle_relative_path']) not in existing_keys]
    manifest['files'].extend(additions)
    manifest['counts']['copied_png_records_including_aliases'] = len(manifest['files'])
    manifest['counts']['copied_png_bytes_including_aliases'] = sum(x['bytes'] for x in manifest['files'])
    manifest['counts']['unique_asset_ids_with_copied_png'] = len({x['asset_id'] for x in manifest['files']})
    MANIFEST_PATH.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    index = runtime_index(manifest)
    (DEST / 'runtime_index.json').write_text(json.dumps(index, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print(json.dumps({'added_manifest_records':len(additions), 'manifest_counts':manifest['counts'],
        'index_counts_by_kind':index['counts_by_kind'], 'index_entries':len(index['entries']),
        'effect_sequences':len(index['effects'])}, ensure_ascii=False, indent=2))


if __name__ == '__main__':
    main()

#!/usr/bin/env python3
"""Build a per-ID candidate-content ledger from an already audited immutable app.

Bundle presence, historical runtime evidence and Human acceptance are deliberately
separate. A previous run is never silently promoted to a current-build result.
"""
from __future__ import annotations
import argparse
import hashlib
import json
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CURRENT = ROOT / "docs/production/current"
PARTY = {"C_WITCH": "ERNA", "C_APPRENTICE": "LUNA", "C_SMITH": "AIRA", "C_FAMILIAR": "NOIR"}


def verified_effect_history(path):
    """Attach dated raw evidence without promoting it to a current-build pass."""
    if path is None:
        return {}, None
    document = json.loads(path.read_text())
    digest = hashlib.sha256(path.read_bytes()).hexdigest()
    result = {}
    for row in document["assets"]:
        ident = row["assetID"]
        if ident in result:
            raise ValueError(f"Duplicate historical effect ID: {ident}")
        evidence = []
        for item in row["historicalCommittedTrace"]["evidence"]:
            raw = ROOT / item["path"]
            pin = item.get("runPin")
            if pin is None and ident == "ACT_E_R03_04_magnet_pullcue":
                pin = document["magnetCommittedBattlePin"]
                if pin["artReceiptPath"] != item["path"] or pin["artReceiptSHA256"] != item["actualSHA256"]:
                    raise ValueError("Magnet evidence does not match its separate run pin")
                refs = [{"path": pin["runPath"], "sha256": pin["runSHA256"]},
                        {"path": pin["casePath"], "sha256": pin["caseSHA256"]}]
            elif pin is not None and "path" in pin:
                refs = [pin]
            elif pin is not None and "resultReceipt" in pin:
                refs = [pin["resultReceipt"]]
                if pin.get("eventCueAudit") is not None:
                    refs.append(pin["eventCueAudit"])
            else:
                raise ValueError(f"Unknown historical effect provenance schema: {ident}")
            if hashlib.sha256(raw.read_bytes()).hexdigest() != item["actualSHA256"]:
                raise ValueError(f"Historical effect receipt changed: {raw}")
            for ref in refs:
                run = ROOT / ref["path"]
                if hashlib.sha256(run.read_bytes()).hexdigest() != ref["sha256"]:
                    raise ValueError(f"Historical effect run changed: {run}")
            if not item.get("rawTraceVerified") or item.get("rawCountForEffectID", 0) <= 0:
                raise ValueError(f"Historical effect observation is not verified: {ident}")
            evidence.append({"scope": "HISTORICAL_BUILD_ONLY", "assetID": ident,
                             "rawReceipt": item["path"], "rawReceiptSHA256": item["actualSHA256"],
                             "rawCountForEffectID": item["rawCountForEffectID"],
                             "traceRowsForEffectID": item.get("traceRowsForEffectID"),
                             "boundEventStatus": item.get("boundEventStatus"),
                             "runPin": pin, "currentBuildRuntimePass": False})
        result[ident] = evidence
    return result, {"path": str(path.resolve()), "sha256": digest,
                    "rule": "Dated raw/run hashes rechecked; runtime and Human acceptance are not transferred."}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--bundle-ledger", type=Path, required=True)
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--effect-history", type=Path)
    args = parser.parse_args()
    audit = json.loads(args.bundle_ledger.read_text())
    app = Path(audit["target"]["app"])
    assert hashlib.sha256((app / "WitchGathering").read_bytes()).hexdigest() == audit["target"]["executableSHA256"]
    catalog = json.loads((app / "catalog_overlay.json").read_text())
    entries = {row["id"]: row for row in audit["runtimeEntries"]}
    files = {row["path"]: row for row in audit["bundleFiles"]}
    effect_history, effect_history_source = verified_effect_history(args.effect_history)
    runs = []
    for path in sorted((CURRENT / "native").glob("*/RUN.json")):
        if not any(word in path.parent.name for word in ("movement_audit", "gear_motion", "attachment_audit", "book_motion", "party_motion")):
            continue
        doc = json.loads(path.read_text())
        for case in doc.get("cases", []):
            runs.append({"path": str(path.relative_to(CURRENT)), "app": doc.get("app"), "executableSHA256": doc.get("executableSHA256", doc.get("sha256")), "runStatus": doc.get("status"), "case": case})

    def assets(paths):
        return [{"path": path, "present": path in files, "sha256": files.get(path, {}).get("sha256"), "pngDecode": files.get(path, {}).get("image", {}).get("status")} for path in sorted(set(paths))]

    def entry_assets(key):
        return assets(ref["bundlePath"] for ref in entries.get(key, {}).get("pathReferences", []) if ref.get("bundlePath") and ref.get("referenceRole") not in {"supporting_reference", "supporting_or_source_reference"})

    def matching_assets(token):
        return assets(path for path in files if token in Path(path).name and Path(path).suffix.lower() in {".png", ".jpg"})

    rows = []
    def add(scope, ident, runtime, art, evidence=None, gaps=None, readiness="PARTIAL", **extra):
        rows.append({"scope": scope, "id": ident, "runtime": runtime, "assets": art,
                     "historicalRuntimeEvidence": evidence or [], "readiness": readiness,
                     "humanApproval": "PENDING_NOT_INFERRED_FROM_QA",
                     "humanApprovalScope": "NEW_RUNTIME_CANDIDATES_NOT_ORIGINAL_DESIGNS",
                     "gaps": gaps or [], **extra})

    for actor, sprite in PARTY.items():
        add("party_character", actor, "four-actor combat and authored candidate pose playback", entry_assets(sprite) + matching_assets(sprite),
            gaps=["Continuous natural-motion quality and final art acceptance remain pending; equipped layers have separate rows."], spriteID=sprite,
            originalDesignApproval="USER_STATED_APPROVED_ORIGINAL_DESIGN",
            originalDesignAuthority="User supplemental instructions identify the four existing character designs as approved; this does not approve added motion or layers.")
    for region in catalog["regions"]:
        rid = region["id"]
        add("region", rid, "region progression, gathering, field/boss scene routes", entry_assets("BG_" + rid + "_FIELD") + entry_assets("BG_" + rid + "_BOSS"),
            gaps=["New enemy mechanics require their own current-source combat QA; a background capture is not a balance test."])
    enemy_coverage = {row["enemyID"]: row for row in audit["catalogCoverage"]["enemies"]}
    for enemy in catalog["enemies"]:
        actor = "ACT_" + enemy["id"]
        evidence = [run for run in runs if run["case"].get("actor") == actor]
        add("enemy_or_boss", enemy["id"], "candidate encounter and seven-state renderer", entry_assets(actor), evidence,
            ["Human natural-motion acceptance pending.", "Historical state receipts do not prove all current combat mechanics."],
            stateCoverage=enemy_coverage.get(enemy["id"], {}).get("stateCoverage", {}),
            registeredPoseOverrides=enemy_coverage.get(enemy["id"], {}).get("registeredPoseOverrides", {}),
            partRigContract=enemy_coverage.get(enemy["id"], {}).get("partRigContract"),
            catalogActionPattern=enemy.get("actionPattern"), boss=enemy.get("boss", False))
    for gear in catalog["gear"]:
        gid = gear["id"]
        art = entry_assets("ICO_" + gid)
        detail = "DETAIL_" + gid
        if detail in entries:
            art += entry_assets(detail); worn = "SMALL_DETAIL_RENDERER_CANDIDATE"
        elif gid.startswith("EQ_W_"):
            art += assets(["GeneratedArt/STAFF_" + gid + ".png"]); worn = "INDEPENDENT_STAFF_CANDIDATE"
        elif gid.startswith("EQ_A_"):
            art += assets(["GeneratedArt/BOOK_" + gid + ".png"]); worn = "INDEPENDENT_BOOK_WITH_27_BODY_FRAMES_CANDIDATE"
        else:
            worn = "HUMAN_DECISION_PENDING" if gid == "EQ_S_01" else "PROPOSAL_ICON_ONLY_NO_WORN_ART"
        evidence = [run for run in runs if run["case"].get("gearID") == gid or run["case"].get("fixture", "") == "book-" + gid]
        gaps = ["Item-level visual adoption and continuous attachment quality remain pending."]
        if detail in entries:
            gaps.append("Detail load receipts and visual fit are separate; see the detail audit and focused Smith follow-up.")
        if gid == "EQ_S_01": gaps.append("Wood-core interpretation is unresolved; approved metal hammer identity is preserved.")
        proposal = gid in {"EQ_F_BODY_01", "EQ_F_HAND_01", "EQ_F_FEET_01", "EQ_F_RING_01"}
        if proposal: gaps.append("Additional Familiar proposal; not an adopted launch product and worn art is unmade.")
        add("gear_type", gid, "candidate craft/equip/growth commands", art, evidence, gaps, wornAppearance=worn,
            designScope="UNAPPROVED_FAMILIAR_EXTENSION" if proposal else "R4_EXISTING_GEAR_TYPE")
    for challenge in catalog["challenges"]:
        add("challenge", challenge["id"], "candidate real battle/reward command", [], gaps=["Human playtest and post-mechanic-change progression/diversity checks remain distinct."], catalogStatus=challenge.get("status"))
    for product in audit["catalogCoverage"]["candidateProducts"]["appearances"]:
        add("appearance_candidate", product["id"], "owned/selected appearance projected separately from stats", assets(product["matchingBundlePaths"]),
            gaps=["Not an approved sale item; final art/continuous attachment adoption remains pending."])
    for product in audit["catalogCoverage"]["candidateProducts"]["furniture"]:
        add("furniture_candidate", product["id"], "owned/placed state and character-use renderer", assets(product["matchingBundlePaths"]),
            gaps=["Not an approved sale item; Human art and interaction acceptance pending."])
    for mid in audit["catalogCoverage"]["materials"]:
        add("material_icon", mid, "material/recipe/gather inventory icon", entry_assets("ICO_" + mid), gaps=["Human icon meaning/legibility acceptance pending."])
    for key, entry in entries.items():
        if entry["kind"] == "gather_prop":
            add("gather_prop", key, "gather scene prop candidate", entry_assets(key), gaps=["Individual in-scene readability/occlusion acceptance pending."])
        elif entry["kind"] == "area_variant":
            # Full-frame previews are inventoried as source art even when the runtime
            # resolver explicitly excludes them from render-ready resource paths.
            art = assets(ref["bundlePath"] for ref in entry.get("pathReferences", []) if ref.get("bundlePath"))
            available = any(item["present"] for item in art)
            add("area_variant", key, "candidate scene resource; routing/layers require separate runtime evidence", art,
                gaps=["No usable bundled image." if not available else "Full-frame image alone does not prove separate background layers or runtime area selection.",
                      "Individual region composition and occlusion quality remain pending."],
                readiness="PARTIAL" if available else "NOT_PRODUCED", entryStatus=entry.get("runtimeStatus"),
                runtimeRouteVerifiedByThisAudit=False)
    effects = json.loads((app / "Art/effect_contract_candidate_r001.json").read_text())
    if effect_history and set(effect_history) != set(effects["entries"]):
        raise ValueError("Historical/current effect ID sets differ; reconcile explicitly")
    for eid, contract in effects["entries"].items():
        history = effect_history.get(eid, [])
        add("effect", eid, "metadata-driven cue/impact or environment playback candidate", matching_assets(eid),
            evidence=history,
            gaps=["Historical event/environment observations are linked with their original build; changed current routes need focused revalidation. Naturalness and Human acceptance remain separate."
                  if history else "Single-clip playback is separate from every actual combat-event binding; inspect effect_binding_audit reports."],
            effectContract=contract)
    # UI/audio rows describe this immutable build's source, not the possibly newer checkout.
    receipt = json.loads(Path(audit["target"]["buildReceipt"]).read_text())
    source_hashes = receipt["source_sha256"]
    screens = {
        "home": ("家 / A案", "native/WitchApp/App.swift"),
        "explore": ("探索", "native/WitchApp/App.swift"),
        "companions": ("仲間", "native/WitchApp/App.swift"),
        "workshop": ("工房", "native/WitchApp/App.swift"),
        "journal": ("採集帳", "native/WitchApp/App.swift"),
        "equipment": ("装備", "native/WitchApp/WorkflowViews.swift"),
        "opening": ("開封", "native/WitchApp/WorkflowViews.swift"),
        "gacha": ("魔導庫", "native/WitchApp/GachaViews.swift"),
        "gacha_rules": ("確率", "native/WitchApp/GachaViews.swift"),
        "appearance": ("試着", "native/WitchApp/App.swift"),
        "furniture": ("模様替え", "native/WitchApp/App.swift"),
        "shop": ("商店", "native/WitchApp/App.swift"),
        "settings": ("設定", "native/WitchApp/App.swift"),
        "gathering_result": ("採集の成果", "native/WitchApp/GatheringSummary.swift"),
    }
    for key, (title, source) in screens.items():
        if source not in source_hashes:
            raise ValueError(f"Required UI source absent from frozen build receipt: {source}")
        add("ui_surface", key, "native candidate view: " + title, [],
            gaps=["Bundle/source presence is not current-build interaction, accessibility, visual quality or physical-device acceptance."],
            frozenSource={"path": source, "sha256": source_hashes.get(source)},
            productionPurchaseEnabled=False if key == "shop" else None)
    for effect in ("uiSelect", "gather", "craft", "equip", "attack", "hit", "victory", "defeat"):
        add("audio_effect", effect, "locally synthesized 24kHz mono PCM candidate", [],
            gaps=["No finished mix or physical-iPhone listening acceptance inferred from DSP/player tests."],
            frozenSource={"path": "native/WitchApp/WitchAudioCoordinator.swift", "sha256": source_hashes.get("native/WitchApp/WitchAudioCoordinator.swift")})
    music_manifest=app/'Music/MANIFEST.json'
    if music_manifest.is_file():
        for track in json.loads(music_manifest.read_text()).get('tracks',[]):
            add('background_music',track['id'],'original scene cue with native loop/crossfade candidate',
                assets(['Music/'+track['file']]),
                gaps=['Signal/manifest presence does not prove runtime playback, listening quality or physical-device acceptance.'],
                score={k:v for k,v in track.items() if k!='scoreEvents'},
                frozenSource={'path':'native/WitchApp/WitchMusicCoordinator.swift','sha256':source_hashes.get('native/WitchApp/WitchMusicCoordinator.swift')})
    else:
        add('audio_production','background_music','no production asset or integration',[],
            gaps=['Authored scene music remains unproduced.'],readiness='NOT_PRODUCED')
    add('audio_production','character_voice','no production asset or integration',[],
        gaps=['Voice direction, casting and recording remain unresolved; no fabricated voice catalog.'],readiness='NOT_PRODUCED')
    gates = {
        "physical_iphone": "Physical-device operation, thermal/performance, lifecycle and VoiceOver evidence unavailable.",
        "apple_sandbox": "Local Xcode purchases are not Apple Sandbox purchases; account/environment needed.",
        "server_authority": "Offline synthetic ES256/X509/JWS validation exists as isolated QA. Apple-signed positive evidence, production account/entitlement authority and a production paid-draw service remain unverified or unimplemented.",
        "formal_products": "Candidate product examples, prices and odds are not approved sale specifications.",
        "release_signing": "Signing, distribution and submission are not performed or authorized by local QA.",
    }
    for key, gap in gates.items():
        add("release_gate", key, "NOT_SATISFIED", [], gaps=[gap], readiness="INCOMPLETE")
    counts = Counter(row["scope"] for row in rows)
    output = {"schema": "content_matrix_r003", "bundleLedger": str(args.bundle_ledger.resolve()), "target": audit["target"],
              "evidenceRule": "Historical runs keep their exact bundle and result. No current-source, Human or natural-motion acceptance is inferred.",
              "counts": dict(counts), "readinessCounts": dict(Counter(row["readiness"] for row in rows)), "rowCount": len(rows), "rows": rows}
    if effect_history_source is not None:
        output["historicalEffectEvidenceSource"] = effect_history_source
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(output, ensure_ascii=False, indent=2) + "\n")
    md = ["# 個別コンテンツ台帳", "", "参照bundle: `" + str(app) + "`。PARTIAL=部分完成、NOT_PRODUCED=未制作、INCOMPLETE=未達gate。画像存在・過去の呼出検証・現行実戦・自然さ・Human承認を別欄で保持する。完成認定は本台帳から推定しない。", "", "| 種別 | ID | 技術状態 | 同梱画像参照 | 判定 |", "|---|---|---|---:|---|"]
    for row in rows:
        md.append(f"| {row['scope']} | `{row['id']}` | {row.get('wornAppearance', row['runtime'])} | {len(row['assets'])} | {row['readiness']} / 追加候補はHuman未承認 |")
    md += ["", "既存4人のキャラクターデザインはユーザー指示で承認済み。ここで未承認とする対象は追加した動作・レイヤー・実装候補であり、既存デザインの承認を取り消すものではない。", "", "JSONには個別SHA、7状態、未達条件、過去QAの実行bundleを収録。R4既存29装備のうち28型は着用候補経路があり、EQ_S_01は木芯仕様判断待ち。猫追加4型は提案アイコン段階。いずれも正式採用や商品数の確定を意味しない。"]
    args.out.with_suffix(".md").write_text("\n".join(md) + "\n")
    print(json.dumps({"out": str(args.out), "rowCount": len(rows), "counts": dict(counts)}, ensure_ascii=False))


if __name__ == "__main__":
    main()

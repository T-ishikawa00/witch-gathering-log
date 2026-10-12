#!/usr/bin/env python3
"""Compare exported source-profile Swift traces with locked Python fixture logs."""
import argparse,collections,hashlib,json
from pathlib import Path

ROOT=Path(__file__).resolve().parents[2]
FIXTURES=ROOT/'native/WitchGameCore/Tests/WitchGameCoreTests/Fixtures'

def sha(data):return hashlib.sha256(data).hexdigest()
def canon(value):return json.dumps(value,ensure_ascii=False,sort_keys=True,separators=(',',':')).encode()

def keys(seed,source,swift):
    def exact(category):
        if category=='castStart':
            p=[(e['t_ms'],e.get('source'),e.get('root'),e.get('skill')) for e in source if e['kind']=='cast_start']
            def skill(e):
                target=e.get('targetID')
                if target in ('basic','C_WITCH_BASIC'):return e.get('sourceID','')+'_BASIC'
                return {'seed':'SK_W_SEED','burst':'SK_W_BURST','mark':'SK_F_MARK','dash':'SK_F_DASH','heal':'SK_A_HEAL','ward':'SK_A_WARD','guard':'SK_S_GUARD','hammer':'SK_S_HAMMER'}.get(target,target)
            s=[(e.get('timestampMs'),e.get('sourceID'),e.get('rootActionID'),skill(e)) for e in swift if e['kind']=='cast_start']
        elif category=='damage':
            p=[(e['t_ms'],e.get('root'),e.get('source'),e.get('hp_loss')) for e in source if e['kind']=='damage']
            s=[(e.get('timestampMs'),e.get('rootActionID'),e.get('sourceID'),e.get('amount')) for e in swift if e['kind'] in {'direct','poison_seed','smith_hammer','chase','counter'}]
        elif category=='enemyHit':
            p=[(e['t_ms'],e.get('root'),e.get('target'),e.get('hp_loss')) for e in source if e['kind']=='enemy_hit']
            s=[(e.get('timestampMs'),e.get('rootActionID'),e.get('targetID'),e.get('amount')) for e in swift if e['kind']=='enemy_hit']
        elif category=='poisonTick':
            p=[(e['t_ms'],e.get('hp_loss')) for e in source if e['kind']=='dot']
            s=[(e.get('timestampMs'),e.get('amount')) for e in swift if e['kind']=='poison_tick']
        elif category=='poisonApply':
            p=[(e['t_ms'],e.get('source'),e.get('stacks')) for e in source if e['kind']=='poison_apply']
            s=[(e.get('timestampMs'),e.get('sourceID'),e.get('amount')) for e in swift if e['kind']=='poison_stack']
        elif category=='heal':
            p=[(e['t_ms'],e.get('source'),e.get('target'),e.get('effective')) for e in source if e['kind']=='heal']
            s=[(e.get('timestampMs'),e.get('sourceID'),e.get('targetID'),e.get('amount')) for e in swift if e['kind']=='heal']
        elif category=='barrier':
            p=[(e['t_ms'],e.get('source'),e.get('target'),e.get('amount')) for e in source if e['kind']=='barrier']
            s=[(e.get('timestampMs'),e.get('sourceID'),e.get('targetID'),e.get('amount')) for e in swift if e['kind'] in {'barrier','heal_barrier'}]
        elif category=='mark':
            p=[(e['t_ms'],e.get('source'),e.get('expiry',0)-e['t_ms']) for e in source if e['kind']=='mark']
            s=[(e.get('timestampMs'),e.get('sourceID'),e.get('amount')) for e in swift if e['kind']=='mark']
        else:raise KeyError(category)
        pc=collections.Counter(p);sc=collections.Counter(s)
        missing=list((pc-sc).elements());extra=list((sc-pc).elements())
        return {'pythonCount':len(p),'swiftCount':len(s),'exactMatches':sum((pc&sc).values()),'pythonOnly':missing,'swiftOnly':extra,'exact':not missing and not extra}

    out={name:exact(name) for name in ['castStart','damage','enemyHit','poisonTick','poisonApply','heal','barrier','mark']}
    pd=[(e['t_ms'],e.get('actor'),tuple(e.get('selected') or [])) for e in source if e['kind']=='support_decision']
    sd=[]
    for e in swift:
        if e['kind']!='support_decision':continue
        target=e.get('targetID','');selected=() if target in ('','none|boss') else tuple(target.split('|'))
        if selected:
            actor=e.get('sourceID','');action=selected[0]
            aliases={'seed':'SK_W_SEED','burst':'SK_W_BURST','mark':'SK_F_MARK','dash':'SK_F_DASH','heal':'SK_A_HEAL','ward':'SK_A_WARD','guard':'SK_S_GUARD','hammer':'SK_S_HAMMER'}
            selected=(actor+'_BASIC' if action=='basic' else aliases.get(action,action),)+selected[1:]
        sd.append((e.get('timestampMs'),e.get('sourceID'),selected))
    pc=collections.Counter(pd);sc=collections.Counter(sd)
    ponly=list((pc-sc).elements());sonly=list((sc-pc).elements())
    out['supportDecision']={'pythonCount':len(pd),'swiftCount':len(sd),'exactMatches':sum((pc&sc).values()),'pythonOnly':ponly,'swiftOnly':sonly}

    all_p=[];all_s=[]
    for name,result in out.items():
        if isinstance(result,dict) and 'pythonOnly' in result and 'swiftOnly' in result:
            all_p.extend((item[0],name,item) for item in result['pythonOnly'])
            all_s.extend((item[0],name,item) for item in result['swiftOnly'])
    first=None
    for t in sorted({row[0] for row in all_p+all_s}):
        ptime=[row[1:] for row in all_p if row[0]==t];stime=[row[1:] for row in all_s if row[0]==t]
        if ptime or stime:
            first={'timeMs':t,'pythonOnly':ptime,'swiftOnly':stime,'meaning':'earliest unmatched aligned event projection; raw event-list order/schema is not directly compared'}
            break
    out['firstAlignedEventProjectionDivergence']=first

    # Compare the shared state-changing projections as a timestamped multiset;
    # raw list ordering is not comparable where the source schema splits records.
    ptime=collections.defaultdict(list);stime=collections.defaultdict(list)
    for name in ['castStart','damage','enemyHit','poisonTick','poisonApply','heal','barrier','mark']:
        for event in out[name]['pythonOnly']:ptime[event[0]].append((name,event))
        for event in out[name]['swiftOnly']:stime[event[0]].append((name,event))
    mismatch=next((t for t in sorted(set(ptime)|set(stime)) if ptime[t] or stime[t]),None)
    out['firstAlignedStateChangeDivergence']={'timeMs':mismatch,'pythonOnly':ptime[mismatch] if mismatch is not None else [],'swiftOnly':stime[mismatch] if mismatch is not None else [],'meaning':'earliest unmatched timestamp in compared action/HP/support projections; not raw event-index divergence'}
    decision_time=min([e[0] for e in ponly+sonly],default=None)
    first_nonempty=min([e[0] for e in ponly+sonly if e[2]],default=None)
    out['firstSupportDecisionKeyDivergence']={'firstUnmatchedAtMs':decision_time,'pythonOnly':next((e for e in ponly if e[0]==decision_time),None),'swiftOnly':next((e for e in sonly if e[0]==decision_time),None),'firstPythonOnlyAtMs':min((e[0] for e in ponly),default=None),'firstSwiftOnlyAtMs':min((e[0] for e in sonly),default=None),'firstUnmatchedSelectedActionAtMs':first_nonempty,'unmatchedSelectedActionCount':sum(bool(e[2]) for e in ponly+sonly)}
    out['pythonKindCounts']=dict(collections.Counter(e['kind'] for e in source))
    out['swiftKindCounts']=dict(collections.Counter(e['kind'] for e in swift))
    return out

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--swift-dir',type=Path,required=True)
    parser.add_argument('--output-dir',type=Path,required=True)
    args=parser.parse_args();args.output_dir.mkdir(parents=True,exist_ok=True)
    reports=[]; failures=[]; known_residuals=[]
    for seed in ['100049','100069']:
        fixture_path=FIXTURES/f'R6B_KNOWN_{seed}_TRACE_R1.json'
        fixture_bytes=fixture_path.read_bytes();fixture=json.loads(fixture_bytes);ref=fixture['referenceResult'];source=ref['log']
        swift_summary=json.loads((args.swift_dir/f'swift_{seed}_summary.json').read_text())
        swift_path=args.swift_dir/swift_summary['swiftEventsFile'];swift_bytes=swift_path.read_bytes();swift=json.loads(swift_bytes)
        canonical_log_sha=sha(canon(source))
        comparisons=keys(seed,source,swift)
        source_hash_ok=(canonical_log_sha==ref['log_sha256']==fixture['sourceProfile']['reference_log_sha256'])
        swift_source_hash_ok=(swift_summary.get('sourceFixtureReferenceLogSHA256')==ref['log_sha256'] and swift_summary.get('sourceProfileReferenceLogSHA256')==fixture['sourceProfile']['reference_log_sha256'])
        input_hash_ok=(ref.get('input_fingerprint')==fixture['sourceProfile'].get('input_fingerprint'))
        outcome_ok=(swift_summary.get('swiftWon')==(ref['outcome']=='VICTORY'))
        boss_hp_ok=(swift_summary.get('swiftRemainingEnemyHP')=={fixture['boss']['id']:ref['boss_remaining_hp']})
        party_hp_ok=(swift_summary.get('swiftRemainingPartyHP')==ref['party_remaining_hp'])
        elapsed_ok=(swift_summary.get('swiftElapsedMs')==ref['elapsed_ms'])
        terminal_ok=outcome_ok and boss_hp_ok and party_hp_ok and elapsed_ok
        state_names=['castStart','damage','enemyHit','poisonTick','poisonApply','heal','barrier','mark']
        state_changes_ok=all(comparisons[n]['exact'] for n in state_names)
        selected_ok=comparisons['firstSupportDecisionKeyDivergence']['unmatchedSelectedActionCount']==0
        unmatched_empty_decisions=[e for e in comparisons['supportDecision']['pythonOnly']+comparisons['supportDecision']['swiftOnly'] if not e[2]]
        record_only=bool(unmatched_empty_decisions) and state_changes_ok and selected_ok and terminal_ok and source_hash_ok and swift_source_hash_ok and input_hash_ok
        status='PASS_WITH_RECORDING_GRANULARITY_RESIDUAL' if record_only else ('PASS' if state_changes_ok and selected_ok and terminal_ok and source_hash_ok and swift_source_hash_ok and input_hash_ok else 'FAIL')
        checks={'canonicalEventListAndSourceProfileHashMatch':source_hash_ok,'swiftExportFixtureHashMetadataMatch':swift_source_hash_ok,'inputFingerprintMatchesFixture':input_hash_ok,'stateChangingProjectionsMatch':state_changes_ok,'selectedActionDecisionsMatch':selected_ok,'terminalOutcomeHPAndElapsedMatch':terminal_ok}
        report={'seed':seed,'status':status,'checks':checks,'fixtureFileSHA256':sha(fixture_bytes),'pythonReference':{'eventCount':len(source),'storedLogSHA256':ref['log_sha256'],'sourceProfileReferenceLogSHA256':fixture['sourceProfile']['reference_log_sha256'],'recomputedCanonicalEventListSHA256':canonical_log_sha,'canonicalHashMatchesStored':canonical_log_sha==ref['log_sha256'],'inputFingerprint':ref.get('input_fingerprint'),'elapsedMs':ref['elapsed_ms'],'outcome':ref['outcome'],'bossRemainingHP':ref['boss_remaining_hp'],'partyRemainingHP':ref['party_remaining_hp']},'swiftExport':{'summary':swift_summary,'eventsFileSHA256':sha(swift_bytes),'eventCount':len(swift)},'rawCountDeltaSwiftMinusPython':len(swift)-len(source),'unmatchedNoActionDecisionRecords':unmatched_empty_decisions,'comparisons':comparisons}
        reports.append(report)
        if status=='FAIL': failures.append(seed)
        if record_only: known_residuals.append(seed)
    overall='FAIL' if failures else ('KNOWN_RESIDUALS_ONLY' if known_residuals else 'PASS')
    payload={'status':overall,'approval':'UNAPPROVED_TEST_OVERLAY','comparisonScope':'locked source-profile fixtures only','failureSeeds':failures,'knownRecordingGranularityResidualSeeds':known_residuals,'reports':reports}
    (args.output_dir/'R6_TRACE_COMPARISON_R003.json').write_text(json.dumps(payload,ensure_ascii=False,indent=2)+'\n')
    lines=['# R6 exported trace comparison R003','', f'Overall result: **{overall}**. This is an unapproved test overlay comparison of the two locked source-profile fixtures only. Actual Swift `CombatEvent` arrays were exported by additive XCTest. Python log SHA is recomputed over canonical JSON bytes (`ensure_ascii=False`, sorted keys, compact separators), matching `canonical(x)` in the vendored `battle_r5.py`. The comparator exits nonzero for canonical/source-profile or exported-fixture hash mismatch, any normalized state-changing projection mismatch, any selected-action decision mismatch, or terminal outcome/HP/time mismatch. Unmatched empty/no-action support-decision records alone are classified as recording-granularity residuals, not event or gameplay parity.', '', 'The output distinguishes normalized event projections from raw event-list length/schema. A PASS does not assert full raw event-array equality, ordinary campaign coverage, or Human approval.', '']
    for r in reports:
        p=r['pythonReference'];s=r['swiftExport']['summary'];c=r['comparisons']
        decision=c['firstSupportDecisionKeyDivergence']
        lines += [f"## Seed {r['seed']} — {r['status']}", '', f"- Python events: {p['eventCount']}; Swift events: {r['swiftExport']['eventCount']} (raw count delta {r['rawCountDeltaSwiftMinusPython']:+d}).", f"- Reference canonical event-list SHA-256: recomputed `{p['recomputedCanonicalEventListSHA256']}`; stored/sourceProfile hashes match: `{p['canonicalHashMatchesStored']}`. Input fingerprint match: `{r['checks']['inputFingerprintMatchesFixture']}`. Fixture bytes SHA-256: `{r['fixtureFileSHA256']}`.", f"- Terminal parity: `{r['checks']['terminalOutcomeHPAndElapsedMatch']}`; Python `{p['outcome']}` at {p['elapsedMs']} ms, boss HP {p['bossRemainingHP']}, party HP `{p['partyRemainingHP']}`; Swift won={s['swiftWon']} at {s['swiftElapsedMs']} ms, boss HP {s['swiftRemainingEnemyHP']}, party HP `{s['swiftRemainingPartyHP']}`.", f"- State-changing projections exact: `{r['checks']['stateChangingProjectionsMatch']}`; first difference `{c['firstAlignedStateChangeDivergence']}`.", f"- First normalized event projection difference: `{c['firstAlignedEventProjectionDivergence']}`.", '- Event projection matches: '+', '.join(f"{n} {v['exactMatches']}/{v['pythonCount']}" for n,v in c.items() if isinstance(v,dict) and 'exactMatches' in v and n!='supportDecision')+'.', f"- Selected-action decision parity: `{r['checks']['selectedActionDecisionsMatch']}`; unmatched selected actions {decision['unmatchedSelectedActionCount']}. Unmatched empty/no-action decision records: {len(r['unmatchedNoActionDecisionRecords'])} (recording granularity only when all gameplay checks pass).", '']
    (args.output_dir/'R6_TRACE_COMPARISON_R003.md').write_text('\n'.join(lines))
    return 1 if failures else 0
if __name__=='__main__':raise SystemExit(main())

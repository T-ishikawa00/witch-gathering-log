#!/usr/bin/env python3
"""Exercise equipped details through committed combat and isolated save relaunch."""
import argparse, hashlib, json, time
from pathlib import Path
from party_motion_audit import run, wait, BUNDLE
from party_frame_audit import expected_details, ACTOR_IDS


def sha(data):
    return hashlib.sha256(data).hexdigest()


def no_hp_discrepancies(receipt):
    # BattlePlayback emits a JSON object keyed by entity ID, not a count.
    return json.loads(receipt['value']) == {}


def equipped(snapshot, actor):
    gear = {g['id']: g for g in snapshot['gear']}
    return {slot: {'instanceID': uid, 'definitionID': gear[uid]['definitionID']}
            for slot, uid in snapshot['equippedGearIDs'].items()
            if slot.startswith(ACTOR_IDS[actor] + '|')}


def expected_slot_ids(snapshot, actor, expected):
    slots = {'body','hands','feet','amulet','ring'}
    if actor == 'NOIR' or any(g.startswith(('EQ_S_', 'EQ_F_')) for g in expected):
        slots.add('weapon')
    return {g['definitionID'] for slot,g in equipped(snapshot,actor).items()
            if slot.split('|')[-1] in slots}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--app', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--device', required=True)
    parser.add_argument('--actor', choices=list(ACTOR_IDS), required=True)
    parser.add_argument('fixtures', nargs='+')
    args = parser.parse_args()
    expected = {f: expected_details(args.actor, f) for f in args.fixtures}
    if any(ids is None for ids in expected.values()):
        parser.error('Only details- or detail-item- fixtures are supported')
    app, out = args.app.resolve(), args.output.resolve()
    out.mkdir(parents=True, exist_ok=False)
    receipt = app.parent / 'BUILD_RECEIPT.json'
    build = json.loads(receipt.read_text())
    assert build['status'] == 'SIMULATOR_BUILD_PASS'
    assert build['executable_sha256'] == sha((app/'WitchGathering').read_bytes())
    run('xcrun', 'simctl', 'install', args.device, str(app))
    folder = Path(run('xcrun','simctl','get_app_container',args.device,BUNDLE,'data'))/'Library/Application Support/Witch03to05R1'
    report = {'scope':'PERSISTED_QA_FIXTURE_COMMITTED_BATTLE_NOT_EARNED_PROGRESSION_OR_ART_APPROVAL',
              'app':str(app), 'buildReceiptSHA256':sha(receipt.read_bytes()),
              'executableSHA256':build['executable_sha256'], 'actor':args.actor,
              'device':args.device, 'cases':[], 'humanApproved':False}
    for fixture in args.fixtures:
        case = out / fixture
        case.mkdir()
        key = 'gear-battle-' + sha((str(out)+'|'+fixture).encode())[:24]
        save = folder/('qa-'+key+'-save.json')
        result = {'fixture':fixture,'saveKey':key,'expectedIDs':sorted(expected[fixture])}
        try:
            assert not save.exists(), 'Unique isolated save already exists'
            started = time.time()
            run('xcrun','simctl','launch','--terminate-running-process',args.device,BUNDLE,
                '--qa-isolated','--qa-save-key='+key,'--qa-persist-fixture',
                '--qa-fixture='+fixture,'--qa-encounter=E_R01_01')
            battle = wait(folder/'last_battle.json',started,lambda r:True,timeout=150)
            art = wait(folder/'last_battle_art.json',started,lambda r:True)
            hp = wait(folder/'last_presentation_hp.json',started,lambda r:True)
            before = json.loads((folder/'battle_before.json').read_text())
            after_bytes = save.read_bytes()
            after = json.loads(after_bytes)['snapshot']
            for name,data in [('battle',battle),('battle_art',art),('presentation_hp',hp),('battle_before',before)]:
                (case/(name+'.json')).write_text(json.dumps(data,ensure_ascii=False,indent=2))
            (case/'post_battle_save.json').write_bytes(after_bytes)
            run('xcrun','simctl','io',args.device,'screenshot',str(case/'battle_result.png'))
            restart = time.time()
            run('xcrun','simctl','launch','--terminate-running-process',args.device,BUNDLE,
                '--qa-isolated','--qa-save-key='+key,'--screen=仲間','--qa-pose=idle')
            restarted_art = wait(folder/'last_appearance_art.json',restart,lambda r:True)
            restarted_bytes = save.read_bytes()
            restarted = json.loads(restarted_bytes)['snapshot']
            (case/'post_restart_save.json').write_bytes(restarted_bytes)
            (case/'restart_art.json').write_text(json.dumps(restarted_art,ensure_ascii=False,indent=2))
            run('xcrun','simctl','io',args.device,'screenshot',str(case/'restarted.png'))
            actual_ids = expected_slot_ids(after,args.actor,expected[fixture])
            def rendered_ids(data):
                appearance=json.loads(data['value'])['appearance']
                return {v for k,v in appearance.items() if k.startswith('DETAIL|'+ACTOR_IDS[args.actor]+'|')}
            checks = {
                'won':after['lastCombatResult']['won'],
                'revisionAdvancedOne':after['revision'] == before['revision']+1,
                'expectedRewardCoin':after['currency']['coin']-before['currency'].get('coin',0) == 2,
                'expectedRewardMaterial':after['materials'].get('M_R01_E1',0)-before['materials'].get('M_R01_E1',0) == 1,
                'equippedExpectedIDs':expected[fixture] == actual_ids,
                'sameInstancesBeforeAndAfterBattle':equipped(before,args.actor)==equipped(after,args.actor),
                'sameInstancesAfterRestart':equipped(after,args.actor)==equipped(restarted,args.actor),
                'battleRenderedExpectedIDs':expected[fixture] == rendered_ids(art),
                'restartRenderedExpectedIDs':expected[fixture] == rendered_ids(restarted_art),
                'restartBytesUnchanged':after_bytes == restarted_bytes,
                'presentationHPMismatchesZero':no_hp_discrepancies(hp),
            }
            result.update(checks=checks,equipped=equipped(after,args.actor),
                          beforeRevision=before['revision'],afterRevision=after['revision'],
                          saveSHA256=sha(after_bytes),status='PASS' if all(checks.values()) else 'FAIL')
        except Exception as error:
            result.update(status='FAIL',error=str(error))
        report['cases'].append(result)
        (out/'RUN.json').write_text(json.dumps(report,ensure_ascii=False,indent=2))
        print(fixture,result['status'],result.get('error',result.get('checks')),flush=True)
    report['status']='PASS' if all(c['status']=='PASS' for c in report['cases']) else 'FAIL'
    (out/'RUN.json').write_text(json.dumps(report,ensure_ascii=False,indent=2))
    if report['status']=='FAIL':raise SystemExit(1)


if __name__ == '__main__':
    main()

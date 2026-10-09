"""R5 battle receipts over unchanged R2/R3 economic operations.
Only the local R01 reference slice. No device or real database mutation.
"""
from compare_candidates import *
from progression_bridge import Campaign,ENEMIES,sha
from dataclasses import asdict
from collections import Counter

class CampaignR5(Campaign):
    def battle(self,boss_id,seed,record=False,disabled=frozenset(),boss_override=None):
        en=ENEMIES[boss_id]
        if en['encounter_gate'] not in self.gates:raise ValueError('future boss')
        if boss_id=='B_R01_B' and len(self.eco.roster_xp)!=4:raise ValueError('four-member join incomplete')
        boss=copy.deepcopy(boss_override or (boss_variant('redistribute_pause') if boss_id=='B_R01_B' else LOCAL['bosses'][boss_id]))
        before=self.inventory_hash();result=BattleR5(self.loadout(),boss,seed,record,disabled).run()
        rid=sha([before,boss_id,seed,result['input_fingerprint'],result['outcome']])
        receipt={'battle_id':rid,'boss_id':boss_id,'outcome':result['outcome'],'snapshot_hash':before,'result_hash':sha(result),'elapsed_ms':result['elapsed_ms'],'combat_rules_version':'G2C_R5_FIXED10000_CANDIDATE'}
        self.verified_battles[rid]=copy.deepcopy(receipt)
        return result,copy.deepcopy(receipt)

def intro_r5():
    old=intro_state();new=CampaignR5(old.eco);new.__dict__.update(copy.deepcopy(old.__dict__));return new

def prepare_r5(hours=6):
    s=intro_r5();r,receipt=s.battle('B_R01_A',100001)
    if r['outcome']!='VICTORY':raise ValueError('intro reference failed; no automatic progression')
    s.commit_victory(receipt);s.join('C_APPRENTICE');s.survey_deep_fixture();s.join('C_SMITH')
    templates=['EQ_BODY_01','EQ_BODY_01','EQ_AMU_01','EQ_AMU_01'];ops=list(Counter('RC_'+t for t in templates).items())
    s.collect_cost(ops)
    for i,t in enumerate(templates):s.craft(t,f'craft:{i}',f'craft-op:{i}')
    for i,a in enumerate(['C_SMITH','C_APPRENTICE','C_WITCH','C_APPRENTICE']):s.equip(f'craft:{i}',a)
    if hours*3600000>s.eco.last_wall_ms:s.advance(hours*3600000-s.eco.last_wall_ms)
    return s

"""R6-B development after R6-A holdout revealed offense regression.
Does NOT replace or rewrite the first frozen policy or its evidence.
"""
from support_ai import *
from dataclasses import replace
CANDIDATES={
 'healing_ward_only':SupportPolicy('healing_ward_only',False,True,True,True,heal_rank='lowest_ratio',timed_ward_value=True),
 'healing_only':SupportPolicy('healing_only',False,False,True,False,heal_rank='lowest_ratio'),
 'guard_healing':SupportPolicy('guard_healing',True,False,True,True,heal_rank='lowest_ratio'),
 'ward25':SupportPolicy('ward25',True,True,True,True,ward_min_use_bp=2500,heal_rank='lowest_ratio',timed_ward_value=True),
}

class CoordinatedBattleR6(BattleR6):
    """Two-stage support planning at one logical instant: smith before healer.
    Times, windups, effects and cooldowns do not change. All existing event
    classes retain order (DOT < expiry < impact < reaction < AI < timeout).
    Within the AI phase only, cover is planned before wards so actual pending
    casts are visible. No hypothetical cover, future RNG, or instant shield.
    """
    AI_ORDER={'C_SMITH':0,'C_APPRENTICE':1,'C_WITCH':2,'C_FAMILIAR':3}
    def push(self,t,priority,kind,payload):
        p=priority*10+(self.AI_ORDER[payload['aid']] if kind=='ai' else 0)
        return super().push(t,p,kind,payload)
    def run(self):
        out=super().run();out['ai_planning_order']=self.AI_ORDER
        out['input_fingerprint']=sha({'pre_coordinator':out['input_fingerprint'],'scheduler':'R6B_COVER_BEFORE_HEAL_AI_PHASE_ONLY'})
        return out

"""R6-B locked evaluation entry point; candidate, not production approval."""
from support_ai_b import CoordinatedBattleR6, CANDIDATES
class FinalBattleR6(CoordinatedBattleR6):
    def __init__(self,*args,**kwargs):
        if 'support_policy' in kwargs:raise ValueError('Final candidate has no AI policy setting')
        super().__init__(*args,support_policy=CANDIDATES['healing_ward_only'],**kwargs)

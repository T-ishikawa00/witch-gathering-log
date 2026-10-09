"""Single locked R6 model entry point; no player-configurable AI policy."""
from support_ai import BattleR6, POLICIES

class SelectedBattleR6(BattleR6):
    def __init__(self,*args,**kwargs):
        if 'support_policy' in kwargs:raise ValueError('Use development comparator explicitly to compare policies')
        super().__init__(*args,support_policy=POLICIES['timed_support'],**kwargs)

"""Non-destructive fixed-point facade over R2, for the R5 reference experiment.
One display HP/power/defense = 10_000 integer units. Basis points stay unscaled.
No prices, item identities, latent affixes or R2 source files are changed.
"""
from dataclasses import dataclass
from fractions import Fraction

@dataclass(frozen=True)
class Profile:
    precision_scale:int=10000
    no_self_cover_charge:bool=True
    urgent_support:bool=False
    temporal_forecast:bool=True

class PrecisionRules:
    def __init__(self,base,scale=10000):
        if scale!=10000:raise ValueError('supported fixed precision scale: 10000')
        self.base=base;self.scale=scale
    def __getattr__(self,k):return getattr(self.base,k)
    def item_primary(self,item):
        g=self.base;g.validate_item(item)
        r=g.RANKS[item.rank]['multiplier_bp'];e=10000+300*item.enhancement
        return {stat:value*r*e*self.scale//100_000_000 for stat,value in g.GEAR[item.template_id]['item_stat_budget'].items()}
    def actor_stats(self,actor_id,level,items,awakening=0):
        g=self.base
        # Retain every input constraint, modifier, cap and eligibility rule.
        out=g.actor_stats(actor_id,level,items,awakening)
        a=g.ACTORS[actor_id]
        flat={s:(a['base'][s]+a['per_level'][s]*(level-1))*self.scale for s in a['base']}
        for it in items:
            for stat,value in self.item_primary(it).items():flat[stat]+=value
        for stat in ('hp','power','defense'):
            bonus=min(g.DATA['caps'][stat+'_pct'],max(0,out.get(stat+'_pct',0)))
            out[stat]=flat[stat]*(10000+bonus)//10000
        return out
    def defense_fraction(self,defense,attacker_level):
        if defense<0 or not 1<=attacker_level<=60:raise ValueError('invalid defense')
        k=(100+8*(attacker_level-1))*self.scale
        return min(Fraction(7,10),Fraction(defense,defense+k))
    def direct_incoming(self,raw_damage,defense,attacker_level,guarded=False,special_reduction_bp=0):
        if raw_damage<0:raise ValueError('negative damage')
        v=Fraction(raw_damage)*(1-self.defense_fraction(defense,attacker_level))
        if guarded:v*=Fraction(65,100)
        v*=Fraction(10000-max(0,min(3000,special_reduction_bp)),10000)
        return v.numerator//v.denominator

"""Limited affix-mechanism laboratory, not a complete endgame engine.
Retains source R6-B AI and H1 rarity math. Uses ONLY base 13 equipment types;
no evolved core rules, awakenings, multi-enemy combat, or purchase execution.
Authors enemy inputs separately. Never patches acceptance guards or game data.
"""
from pathlib import Path
from dataclasses import replace,asdict
from functools import partial
from unittest.mock import patch
import sys,json,hashlib,copy
sys.dont_write_bytecode=True
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'source/rarity_catalog_r2/tools'))
import model as old
b=old.b;g=b.g;e=b.e
import precision_rules
ORDER=tuple(b.ORDER)
SLOTS=('weapon','body','hands','feet','amulet','ring')
WEAPONS=dict(zip(('C_WITCH','C_APPRENTICE','C_SMITH','C_FAMILIAR'),('EQ_W_01','EQ_A_01','EQ_S_01','EQ_F_01')))
def template(a,s):
 if s=='weapon':return WEAPONS[a]
 if a=='C_FAMILIAR' and s!='amulet':return 'EQ_F_'+{'body':'BODY','hands':'HAND','feet':'FEET','ring':'RING'}[s]+'_01'
 return {'body':'EQ_BODY_01','hands':'EQ_HAND_01','feet':'EQ_FEET_01','amulet':'EQ_AMU_01','ring':'EQ_RING_01'}[s]
VARIABLE={('C_WITCH',x) for x in ('weapon','hands','amulet','ring')}|{('C_SMITH','weapon'),('C_SMITH','body'),('C_APPRENTICE','weapon'),('C_FAMILIAR','weapon')}
BUILD_NAMES={'BALANCED':'基準・汎用','BURST':'破砕・直接攻撃','TOXIN':'呪毒・持久','FORTRESS':'回復・受け流し'}
def affixes(a,s,build):
 if (a,s) not in VARIABLE or build=='BALANCED':
  return {'C_WITCH':('AF_HP','AF_POWER','AF_CDR'),'C_SMITH':('AF_HP','AF_DEF','AF_GUARD'), 'C_APPRENTICE':('AF_HP','AF_HEAL','AF_CDR'),'C_FAMILIAR':('AF_HP','AF_POWER','AF_HASTE')}[a]
 if build=='BURST':return {'C_WITCH':('AF_POWER','AF_CRIT','AF_DIRECT'),'C_SMITH':('AF_POWER','AF_DIRECT','AF_CRIT'),'C_APPRENTICE':('AF_HEAL','AF_CDR','AF_POWER'),'C_FAMILIAR':('AF_CHASE','AF_POWER','AF_HASTE')}[a]
 if build=='TOXIN':return {'C_WITCH':(('AF_POWER','AF_HASTE','AF_CDR') if s=='weapon' else ('AF_DOT','AF_POWER','AF_CDR')),'C_SMITH':('AF_DEF','AF_GUARD','AF_COUNTER'),'C_APPRENTICE':('AF_HEAL','AF_WARD','AF_CDR'),'C_FAMILIAR':('AF_CHASE','AF_CDR','AF_POWER')}[a]
 if build=='FORTRESS':return {'C_WITCH':('AF_HP','AF_DEF','AF_CDR'),'C_SMITH':('AF_COUNTER','AF_GUARD','AF_DEF'),'C_APPRENTICE':('AF_HEAL','AF_WARD','AF_CDR'),'C_FAMILIAR':('AF_CHASE','AF_HP','AF_CDR')}[a]
 raise ValueError(build)
def party(build='BALANCED',quality='Q4',q=800):
 if build not in BUILD_NAMES:raise ValueError('unknown build')
 out=[]
 for a in ORDER:
  items=[]
  for s in SLOTS:
   tid=template(a,s);ids=affixes(a,s,build)
   uid=('common' if (a,s) not in VARIABLE else build)+':'+a+':'+s
   it=g.Item(uid,tid,quality,5,10,tuple(g.Affix(x,q) for x in ids),locked=True)
   g.validate_item(it);items.append(it)
  out.append(b.PartyInput(a,60,tuple(items),0))
 g.validate_party_loadout({p.actor_id:list(p.items) for p in out})
 return out

def bosses():
 # Authored lab profiles; no special build tags, immunities or dynamic scaling.
 base={'level':60,'hp':120000,'power':1000,'defense':250,'dot_resist_bp':0,'first_telegraph_ms':1800,'time_limit_ms':120000}
 def action(id,coef,wind,hits,recover,rest,aoe=False,heavy=False):return {'id':id,'coefficient_bp':coef,'windup_ms':wind,'hit_offsets_ms':hits,'recovery_ms':recover,'rest_ms':rest,'aoe':aoe,'heavy':heavy}
 return {
  'OPENINGS':dict(base,id='LAB_OPENINGS',name='長い後隙',power=1800,actions=[action('CHARGE',14000,2200,[0],3000,3500,False,True)]),
  'ARMORED':dict(base,id='LAB_ARMORED',name='高防護・継続戦',defense=1600,hp=90000,power=800,actions=[action('TAPS',7500,1300,[0,450,900],1600,2000)]),
  'PRESSURE':dict(base,id='LAB_PRESSURE',name='全体圧力',hp=90000,power=1200,actions=[action('SWEEP',11000,1700,[0],1000,1800,True,False)]),
  'COUNTERS':dict(base,id='LAB_COUNTERS',name='短周期の単体攻撃',hp=90000,power=1400,actions=[action('STRIKE',8500,1500,[0],500,300,False,False)])
 }
def fight(build,boss,seed,quality='Q4',record=False):
 with patch.object(precision_rules,'PrecisionRules',partial(old.RarityRules,multipliers=old.MODELS['H1_RECOMMENDED'])):
  obj=b.FinalBattleR6(party(build,quality),copy.deepcopy(boss),seed,record=record)
  out=obj.run()
 return out

def digest(x):return hashlib.sha256(json.dumps(x,sort_keys=True,ensure_ascii=False,default=str).encode()).hexdigest()
if __name__=='__main__':
 for k,bo in bosses().items():
  print(k,flush=True)
  for bu in BUILD_NAMES:
   r=fight(bu,bo,101)
   print(bu,r['outcome'],r['elapsed_ms'],r['boss_remaining_hp'],r['metrics'],flush=True)

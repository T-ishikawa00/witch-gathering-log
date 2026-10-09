"""Structural design checks only. No combat/economy/engagement claims.
Usage: python3 tools/validate_catalog.py [path/to/world_catalog.json]
Standard library only; does not touch the game project or network.
"""
from __future__ import annotations
from pathlib import Path
import json, sys, copy, hashlib

BASE=Path(__file__).resolve().parents[1]
GROUPS=[
 ('V01','全テーブル内のIDの一意性'),('V02','11到達フラグの参照・循環・順位'),
 ('V03','地域・エリア・敵・素材・入手先の参照'),('V04','各素材に現存する入手経路'),
 ('V05','全素材に用途が存在'),('V06','レシピの親装備・出力・対象者・工房'),
 ('V07','29レシピの解放時点で材料・親・対象者・工房へ到達可能'),
 ('V08','装備進化の非循環性'),('V09','10ボスそれぞれ2候補の準備装備が挑戦前に入手可能'),
 ('V10','ボスの初回素材は撃破後。進行キーとして消費しない'),
 ('V11','確率・必要数・能力の未決値をnullで区別'),('V12','5地域・20エリア・30敵・50素材・29装備の提案範囲'),
 ('V13','原本ファイルのSHA-256一致')]

def validate(d:dict,check_files:bool=True)->dict:
 errors=[]; results=[]
 def error(code,detail):errors.append({'check':code,'detail':detail})
 maps={}
 tables=['gates','regions','areas','enemies','materials','sources','gear','recipes','actors','decision_register']
 for table in tables:
  rows=d.get(table,[]);ids=[r.get('id') for r in rows]
  if len(ids)!=len(set(ids)) or None in ids:error('V01',table+' ID重複／欠落')
  maps[table]={r['id']:r for r in rows if 'id'in r}
 gates=maps['gates'];gates_visited=set();stack=set()
 def gate_visit(g):
  if g not in gates:error('V02','不明なgate:'+str(g));return
  if g in stack:error('V02','gate循環:'+g);return
  if g in gates_visited:return
  stack.add(g)
  for p in gates[g]['requires']:
   gate_visit(p)
   if p in gates and gates[p]['rank']>=gates[g]['rank']:error('V02',g+' 前提順位')
  stack.remove(g);gates_visited.add(g)
 for g in gates:gate_visit(g)
 def rank(g):return gates.get(g,{}).get('rank',10**6)
 def exists(tbl,id_,code='V03'):
  if id_ not in maps[tbl]:error(code,f'{tbl}:{id_} が存在しない');return False
  return True
 for r in d['regions']:
  for k in ('entry_gate','inner_gate','clear_gate'):exists('gates',r[k])
 for a in d['areas']:
  exists('regions',a['region_id']);exists('gates',a['unlock_gate'])
 for e in d['enemies']:
  for tbl,col in [('regions','region_id'),('areas','area_id'),('gates','encounter_gate'),('materials','material_id')]:exists(tbl,e[col])
  if e['victory_gate']:exists('gates',e['victory_gate'])
 for m in d['materials']:exists('regions',m['region_id']);exists('gates',m['first_available_gate'])
 for s in d['sources']:
  for tbl,col in [('regions','region_id'),('areas','area_id'),('materials','material_id'),('gates','available_gate')]:exists(tbl,s[col])
  if s['enemy_id']:exists('enemies',s['enemy_id'])
  mat=maps['materials'].get(s['material_id']);area=maps['areas'].get(s['area_id']);enemy=maps['enemies'].get(s['enemy_id'])
  if mat and mat['region_id']!=s['region_id']:error('V03',s['id']+' 素材原産地と入手先不一致')
  if area and area['region_id']!=s['region_id']:error('V03',s['id']+' エリア不一致')
  if area and rank(s['available_gate'])<rank(area['unlock_gate']):error('V03',s['id']+' エリア解放前の素材')
  if enemy and (enemy['material_id']!=s['material_id'] or enemy['area_id']!=s['area_id']):error('V03',s['id']+' 敵との対応不一致')
 for m in d['materials']:
  sources=[s for s in d['sources'] if s['material_id']==m['id']]
  if not sources:error('V04',m['id']+' 入手先なし')
  elif rank(m['first_available_gate'])!=min(rank(s['available_gate']) for s in sources):error('V04',m['id']+' 初入手gate不一致')
  uses=[r['id'] for r in d['recipes'] if any(x['material_id']==m['id'] for x in r['ingredients'])]
  if not uses:error('V05',m['id']+' 用途なし')
  if uses!=m['recipe_ids']:error('V05',m['id']+' 用途の派生ビュー不一致')
 recipes_by_output={r['output_gear_id']:r for r in d['recipes']}
 if len(recipes_by_output)!=len(d['recipes']):error('V06','このR1では出力ごと1レシピ。重複出力。')
 for r in d['recipes']:
  exists('gear',r['output_gear_id'],'V06');exists('gates',r['unlock_gate'],'V06')
  if r['parent_template_id']:exists('gear',r['parent_template_id'],'V06')
  if r['station'] not in ['witch_bench','forge']:error('V06',r['id']+' 未定義工房')
  for x in r['ingredients']:exists('materials',x['material_id'],'V06')
 for g in d['gear']:
  if g['id']not in recipes_by_output:error('V06',g['id']+' レシピなし')
  for a in g['actor_ids']:exists('actors',a,'V06')
  r=recipes_by_output.get(g['id'])
  if r and (r['parent_template_id']!=g['parent_template_id'] or r['unlock_gate']!=g['unlock_gate']):error('V06',g['id']+' 親／gate不一致')
 # Dependency closure by acquisition stage.
 closure={}; provenance=[]
 for gate in sorted(gates.values(),key=lambda g:g['rank']):
  now=gate['rank'];mats={s['material_id'] for s in d['sources'] if rank(s['available_gate'])<=now};made=set()
  changed=True
  while changed:
   changed=False
   for r in d['recipes']:
    if rank(r['unlock_gate'])>now:continue
    parent=r['parent_template_id'];g=maps['gear'].get(r['output_gear_id'])
    if not g:continue
    station_ok=(r['station']=='witch_bench' or now>=rank(maps['actors']['C_SMITH']['join_gate']))
    actor_ok=all(rank(maps['actors'].get(a,{}).get('join_gate'))<=now for a in g['actor_ids'])
    if station_ok and actor_ok and (parent is None or parent in made) and all(x['material_id']in mats for x in r['ingredients']):
     if g['id']not in made:made.add(g['id']);changed=True
  closure[gate['id']]=made
  provenance.append({'gate':gate['id'],'rank':now,'available_materials':len(mats),'craftable_templates':len(made)})
 for r in d['recipes']:
  if r['output_gear_id']not in closure.get(r['unlock_gate'],set()):error('V07',r['id']+' 解放時点に制作不能（必要数と戦闘勝率は対象外）')
 visited=set();anc=set()
 def gear_visit(g):
  if g not in maps['gear']:return
  if g in anc:error('V08','進化循環:'+g);return
  if g in visited:return
  anc.add(g);p=maps['gear'][g]['parent_template_id']
  if p:gear_visit(p)
  anc.remove(g);visited.add(g)
 for g in maps['gear']:gear_visit(g)
 for b in (e for e in d['enemies']if e['kind']!='normal'):
  candidates=b['prep_gear_ids'];accessible=closure.get(b['encounter_gate'],set())
  if len(set(candidates))<2:error('V09',b['id']+' 準備候補2種未満')
  for gid in candidates:
   if gid not in accessible:error('V09',b['id']+' 戦前に作れない:'+gid)
  sources=[s for s in d['sources'] if s['enemy_id']==b['id']]
  if any(s['available_gate']!=b['victory_gate'] for s in sources):error('V10',b['id']+' 固有素材の入手gate')
  if rank(b['victory_gate'])<=rank(b['encounter_gate']):error('V10',b['id']+' 前後関係')
 for m in d['materials']:
  if m['is_progression_key']:error('V10',m['id']+' 進行キーが素材化されている')
 for s in d['sources']:
  if s['probability'] is not None or s['quantity']is not None or s['numeric_status']!='TUNE_PENDING':error('V11',s['id']+' 未決数値を自動補完')
 for r in d['recipes']:
  if any(x['quantity']is not None or x['status']!='TUNE_PENDING' for x in r['ingredients']):error('V11',r['id']+' 未決数量を補完')
 for g in d['gear']:
  if g['stats']is not None or g['rarity']is not None:error('V11',g['id']+' 性能を確定扱い')
 sizes={'regions':5,'areas':20,'enemies':30,'materials':50,'sources':50,'gear':29,'recipes':29}
 for k,n in sizes.items():
  if len(d[k])!=n:error('V12',k+f' R1予定数{n}との不一致')
 for r in d['regions']:
  es=[e for e in d['enemies'] if e['region_id']==r['id']]
  if len([e for e in es if e['kind']=='normal'])!=4 or len([e for e in es if e['kind']!='normal'])!=2:error('V12',r['id']+' 敵構成')
 if check_files:
  for rf in d['references']:
   p=BASE/'reference'/rf['name']
   if not p.exists() or hashlib.sha256(p.read_bytes()).hexdigest()!=rf['sha256']:error('V13','原本不一致:'+rf['name'])
 for cid,title in GROUPS:results.append({'id':cid,'name':title,'status':'FAIL' if any(e['check']==cid for e in errors) else 'PASS'})
 return {'pass':not errors,'checks':results,'errors':errors,'acquisition_closure':provenance,'scope_warning':'素材・レシピ・到達の構造検査のみ。戦闘勝率・必要周回数・経済の無限増殖・ユーザー体験・iPhone性能は未検証。'}

def negative_tests(d:dict)->list:
 tests=[]
 def run(name,mutator):
  t=copy.deepcopy(d);mutator(t);r=validate(t,False);tests.append({'case':name,'detected':not r['pass'],'failure_checks':sorted(set(x['check'] for x in r['errors']))})
 run('存在しない素材IDをレシピへ混入',lambda t:t['recipes'][0]['ingredients'][0].update(material_id='M_MISSING'))
 run('霊枝の全入手先を削除',lambda t:t.update(sources=[s for s in t['sources'] if s['material_id']!='M_R01_G1']))
 run('初期素材を最終ボス後へ移動',lambda t:t['sources'][0].update(available_gate='G_R05_B'))
 run('初期杖に末端杖を親指定して循環',lambda t:t['gear'][0].update(parent_template_id='EQ_W_P2'))
 run('素材IDの重複',lambda t:t['materials'].append(copy.deepcopy(t['materials'][0])))
 run('最初のボスの準備に最終素材装備を要求',lambda t:next(e for e in t['enemies']if e['kind']=='miniboss').update(prep_gear_ids=['EQ_AMU_03','EQ_W_G2']))
 run('開始フラグを最終クリアへ依存させる',lambda t:t['gates'][0].update(requires=['G_R05_B']))
 run('未決レシピ必要数を0に自動補完',lambda t:t['recipes'][0]['ingredients'][0].update(quantity=0))
 return tests

if __name__=='__main__':
 path=Path(sys.argv[1]) if len(sys.argv)>1 else BASE/'data/world_catalog.json'
 d=json.loads(path.read_text(encoding='utf-8'));r=validate(d);r['negative_tests']=negative_tests(d)
 out=BASE/'qa/structural_validation.json';out.parent.mkdir(parents=True,exist_ok=True)
 out.write_text(json.dumps(r,ensure_ascii=False,indent=2),encoding='utf-8')
 print(json.dumps(r,ensure_ascii=False,indent=2));sys.exit(0 if r['pass'] and all(x['detected']for x in r['negative_tests']) else 1)

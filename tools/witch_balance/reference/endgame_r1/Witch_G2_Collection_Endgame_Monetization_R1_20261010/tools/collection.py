"""Goal-specific acquisition study, NOT install-to-endgame progression.
All 33 types already unlocked/crafted, R05 explored, 24h/day collection credited.
Uses stated uniform affix/pity rules with a new NumPy sampler (not original hash
RNG). No item selection, reforge, battle, ad bonus, or payment execution.
"""
from pathlib import Path
import json,math,sys
import numpy as np
from lab import ROOT,g,e,b,old
TARGETS={
 'EQ_W_P2':{'name':'呪毒の杖','desired':['AF_DOT','AF_CDR','AF_POWER']},
 'EQ_W_G2':{'name':'結界の杖','desired':['AF_WARD','AF_CDR','AF_POWER']},
 'EQ_A_03':{'name':'回復の本','desired':['AF_HEAL','AF_CDR','AF_WARD']},
 'EQ_S_03':{'name':'反撃の槌','desired':['AF_COUNTER','AF_GUARD','AF_CDR']},
 'EQ_F_03':{'name':'追撃の触媒','desired':['AF_CHASE','AF_HASTE','AF_DIRECT']}}
METRICS=('READY_2_AFFIX_SR','LATENT_2_AFFIX_PROJECT','LR_2_AFFIX','LR_3_AFFIX_Q900')
PERSONAS=('FREE_NO_AD','AD_ONLY','ONE_OUTFIT','ONE_SMALL_PURCHASE','VALUE_PACK_ONLY','VALUE_PLUS_DELIVERY','REGULAR_100_PER_30D','HIGH_BUDGET_400_PER_30D')
def vector_step(top,mid,forced,qr,tr):
 quality=np.select([qr<100,qr<500,qr<2500,qr<6500],[4,3,2,1],default=0)
 quality=np.where(top==99,4,np.where((mid==19)&(quality<3),3,quality))
 selected=((quality==4)&forced)|(tr<5000)
 return quality,selected,np.where(quality==4,0,top+1),np.where(quality>=3,0,mid+1),np.where(quality==4,~selected,forced)
def affix_flags(rng,size,n,q,source):
 if source=='natural':
  a=rng.integers(0,n,size);bb=rng.integers(0,n-1,size);bb+=bb>=a
  lo=np.minimum(a,bb);hi=np.maximum(a,bb)
  c=rng.integers(0,n-2,size);c+=c>=lo;c+=c>=hi
  vals=rng.integers(0,1001,(size,3))
 else:
  a=np.zeros(size,dtype=int);bb=rng.integers(1,n,size);c=rng.integers(1,n-1,size);c+=c>=bb
  lower=np.where(q==4,800,500)
  vals=np.floor(rng.random((size,3))*(1001-lower[:,None])).astype(int)+lower[:,None]
 ids=np.column_stack([a,bb,c]);wanted=ids<3;count=np.array([0,1,2,3,3])[q]
 visible=wanted & (np.arange(3)[None,:]<count[:,None]);all_count=np.sum(wanted,axis=1)
 return np.column_stack([(np.sum(visible,axis=1)>=2),all_count>=2,(q==4)&(all_count>=2),(q==4)&(all_count==3)&np.all(np.maximum(vals,600)>=900,axis=1)])
def natural_prob(tid):
 local=e.CFG['regional_gear_theme_pools']['R05'];allpool=sorted(g.GEAR)
 return (0.6/len(local) if tid in local else 0)+0.4/len(allpool)
def combinatorial(tid):
 n=len(g.eligible_affixes(tid));r=3
 return {'pool_size':n,'natural_latent_2':sum(math.comb(r,k)*math.comb(n-r,3-k) for k in (2,3))/math.comb(n,3),
 'gacha_latent_2':1-math.comb(n-r,2)/math.comb(n-1,2),'natural_SR_visible2':math.comb(3,2)/math.comb(n,2),'gacha_SR_visible2':2/(n-1),
 'natural_LR_exact3_Q900_given_target_LR':1/math.comb(n,3)*(101/1001)**3,'gacha_LR_exact3_Q900_given_target_LR':1/math.comb(n-1,2)*(101/201)**3,
 'natural_target_prob_non_sixth':natural_prob(tid),'natural_target_mean_per_day':8+40*natural_prob(tid)}
def cumulative_sample(tid,samples=3000,days=90,seed=261010):
 n=len(g.eligible_affixes(tid));m=len(METRICS)
 nat_first=np.full((samples,m),np.inf);nat_byday=np.zeros((days+1,samples,m),dtype=bool)
 miss=np.zeros(samples,dtype=int);rng=np.random.default_rng(seed)
 for i in range(1,days*48+1):
  qr=rng.integers(0,10000,samples)
  quality=np.select([qr<4500,qr<7500,qr<9300,qr<9900],[0,1,2,3],default=4)
  quality=np.where(miss==99,4,quality);miss=np.where(quality==4,0,miss+1)
  selected=np.ones(samples,dtype=bool) if i%6==0 else rng.random(samples)<natural_prob(tid)
  flags=affix_flags(rng,samples,n,quality,'natural') & selected[:,None]
  nat_first=np.where(flags & ~np.isfinite(nat_first),i/48,nat_first)
  if i%48==0:nat_byday[i//48]=np.isfinite(nat_first)
 maxpull=days*5+math.ceil(days/30)*400
 gc_first=np.full((samples,m),np.inf);gc_byn=np.zeros((maxpull+1,samples,m),dtype=bool)
 top=np.zeros(samples,dtype=int);mid=top.copy();force=np.zeros(samples,dtype=bool);rng=np.random.default_rng(seed+100000)
 counts=np.zeros(5,dtype=np.int64)
 for i in range(1,maxpull+1):
  q,chosen,top,mid,force=vector_step(top,mid,force,rng.integers(0,10000,samples),rng.integers(0,10000,samples))
  flags=affix_flags(rng,samples,n,q,'gacha')&chosen[:,None]
  gc_first=np.where(flags & ~np.isfinite(gc_first),i,gc_first);gc_byn[i]=np.isfinite(gc_first)
  for quality in range(5):counts[quality]+=np.sum(q==quality)
 results=[]
 for persona in PERSONAS:
  first=np.full((samples,m),np.inf)
  for d in range(1,days+1):
   schedule=old.personas(d)[persona][0];projection=old.plan_projection(schedule,d);gn=5*d+projection['tickets_from_products']
   reached=nat_byday[d]|gc_byn[gn];first=np.where(reached & ~np.isfinite(first),d,first)
   if d in (7,30,90):
    row={'target':tid,'persona':persona,'day':d,'purchase_yen':projection['spend_jpy'],'purchase_tickets':projection['tickets_from_products'],'total_gacha_draws':gn,'natural_draws':48*d,'samples':samples,'goals':{}}
    for k,metric in enumerate(METRICS):
     med=float(np.quantile(first[:,k],.5,method='inverted_cdf'));p90=float(np.quantile(first[:,k],.9,method='inverted_cdf'))
     row['goals'][metric]={'success_count':int(np.sum(first[:,k]<=d)),'probability':float(np.mean(first[:,k]<=d)),'median_day':med if math.isfinite(med) else None,'p90_day':p90 if math.isfinite(p90) else None}
    results.append(row)
 batch=[{'draws':pulls,'goals':{key:float(np.mean(gc_first[:,j]<=pulls)) for j,key in enumerate(METRICS)}} for pulls in (10,20,50,100,200,400)]
 return {'target':tid,'oracle':combinatorial(tid),'rows':results,'standalone_batches':batch,'gacha_quality_counts_for_maxpull_all_samples':counts.tolist(),'samples':samples,'maxpull':maxpull,'rng_seed_natural':seed,'rng_seed_gacha':seed+100000}
if __name__=='__main__':
 import argparse
 ap=argparse.ArgumentParser();ap.add_argument('--output',type=Path,required=True);ap.add_argument('--samples',type=int,default=3000);args=ap.parse_args();args.output.mkdir(parents=True,exist_ok=False)
 out=[]
 for j,tid in enumerate(TARGETS):
  x=cumulative_sample(tid,args.samples,seed=261010+j*1000);out.append(x);print(tid,x['oracle'],flush=True)
 (args.output/'COLLECTION_RESULTS.json').write_text(json.dumps({'scope':'late-game fixed discovery snapshot; acquisition, NOT whole progression or completed loadouts','metrics':list(METRICS),'numpy':np.__version__,'targets':out},ensure_ascii=False,indent=2))
 print('done',flush=True)

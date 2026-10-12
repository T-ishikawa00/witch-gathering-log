from bootstrap import *
from support_ai import *
import copy,time,json
from dataclasses import replace

def states(kind='protect',hours=6,plus=3):
    s=prepared_at(kind,hours); t=copy.deepcopy(s)
    for uid in ['intro:relic','grant:C_APPRENTICE','craft:0']:
        for i in range(plus):t.enhance(uid,f'paid:{uid}:{i}')
    return s,t

def sweep(policy_name, start=300001, n=100):
    pol=POLICIES.get(policy_name)
    rows=[]; beg=time.time()
    for kind,h,power in [('protect',6,190),('offense',6,190),('protect',12,209)]:
        s,t=states(kind,h)
        rs=[]
        for seed in range(start,start+n):
            outcomes=[]
            for st in (s,t):
                cls=BattleR6 if pol else BattleR5
                kw={'support_policy':pol} if pol else {}
                r=cls(st.loadout(),boss_variant('redistribute_pause',power),seed,**kw).run();outcomes.append(r['outcome'])
            rs.append({'seed':seed,'before':outcomes[0],'after':outcomes[1]})
        row={'policy':policy_name,'kind':kind,'hours':h,'power':power,'n':n,'before':sum(x['before']=='VICTORY' for x in rs),'after':sum(x['after']=='VICTORY' for x in rs),'win_to_loss':[x['seed'] for x in rs if x['before']=='VICTORY' and x['after']!='VICTORY'],'loss_to_win':sum(x['before']!='VICTORY' and x['after']=='VICTORY' for x in rs),'rows':rs}
        rows.append(row); print({k:v for k,v in row.items() if k!='rows'},flush=True)
    s,t=states()
    known=[]
    for seed in [100049,100069]:
        os=[]
        for st in [s,t]:
            cls=BattleR6 if pol else BattleR5; kw={'support_policy':pol} if pol else {}
            r=cls(st.loadout(),boss_variant('redistribute_pause'),seed,**kw).run();os.append(r['outcome'])
        known.append({'seed':seed,'before':os[0],'after':os[1]})
    out={'development_only':True,'policy':policy_name,'seed_start':start,'n_per_pair':n,'rows':rows,'known_cases':known,'seconds':time.time()-beg}
    (ROOT/'results'/f'DEV_{policy_name}.json').write_text(json.dumps(out,indent=2));print('known',known,'seconds',out['seconds'])
if __name__=='__main__':
    import argparse
    p=argparse.ArgumentParser();p.add_argument('policy');p.add_argument('--n',type=int,default=100);a=p.parse_args();sweep(a.policy,n=a.n)

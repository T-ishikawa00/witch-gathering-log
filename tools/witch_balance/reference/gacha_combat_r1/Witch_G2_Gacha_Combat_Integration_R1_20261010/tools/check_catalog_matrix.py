"""All33-type numeric validity, NOT all33 skills in R6 combat."""
from bridge import *

def run():
    s=build_state('fresh',0);s.gates=e.closure('G_R05_B');s.known_evolved=set(g.GEAR)
    rs=[];rolls={4:0,3:100,2:500,1:2500,0:6500}
    class Fixed(DrawBridge):
        q=0
        def ri(self,domain,n):
            if domain=='quality':return rolls[self.q]
            if domain=='target':return 0
            return super().ri(domain,n)
    for tid in sorted(catalog()):
        for q in range(5):
            draw=Fixed(C,'matrix:'+tid+str(q),s,target=tid);draw.q=q;item=draw.draw(1)[0]['item']
            assert item.template_id==tid and item.quality=='Q'+str(q)
            g.validate_item(item)
            for actor in g.GEAR[tid]['actor_ids']:
                got=P.actor_stats(actor,60,[item]);assert got['hp']>0 and got['power']>0
            rs.append({'id':tid,'quality':item.quality,'rank':item.rank,'active_affixes':list(signature(item)),'latent_count':len(item.latent_affixes),'valid':True,'combat_verified':False})
    # One original evolution operation: inheritance, not silent guarantee reroll.
    d=Fixed(C,'evolve-wand',s,target='EQ_W_01');d.q=4;original=d.draw(1)[0]['item'];evolved,cost=g.evolve_preview(original,'EQ_W_P1','G_R05_B',frozenset(s.joined_events))
    assert evolved.latent_affixes==original.latent_affixes and evolved.uid==original.uid
    assert evolved.latent_affixes[0].affix_id=='AF_POWER'
    data={'static_numeric_cases':len(rs),'all_pass':all(r['valid'] for r in rs),'cases':rs,'evolution_check':{'from':'EQ_W_01','to':'EQ_W_P1','same_id':True,'same_latent':True,'guaranteed_affix_at_acquisition':'AF_POWER','not_auto_changed_to':'AF_DOT','cost_from_R2':cost},'note':'All legal static item/stat conversions only. Original R6 does not implement advanced core-rule/awakening battles.'}
    (ROOT/'results/CATALOG_165_STATIC_CASES.json').write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n');print('165 item-quality combinations passed; 1 inherited-affix evolution checked')
if __name__=='__main__':run()

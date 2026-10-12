"""Optional Playwright UI probe. Local Chromium only. NOT real-person timings."""
from pathlib import Path
import json,time,statistics,platform,sys
from playwright.sync_api import sync_playwright
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'qa';OUT.mkdir(exist_ok=True)
HTML=(ROOT/'review/AFTER_DRAW_REVIEW.html').read_text()
checks=[];captures=[];timings=[];errors=[];network=[]
def check(name,ok,**extra):
    checks.append({'name':name,'pass':bool(ok),**extra})
    if not ok:raise AssertionError(name)
def state(page):return page.evaluate('window.__qa.state()')
def click(page,key):page.locator('[data-action="'+key+'"]').click()
def layout(page,tag,width):
    sw=page.evaluate('document.documentElement.scrollWidth');check(tag+':no_horizontal_overflow',sw<=width,scroll_width=sw,width=width)
    dims=page.locator('button:visible').evaluate_all('(xs)=>xs.map(x=>{const r=x.getBoundingClientRect();return {text:x.textContent,w:r.width,h:r.height}})')
    check(tag+':buttons_44',all(x['w']>=44 and x['h']>=44 for x in dims),buttons=len(dims))
def setup(page,profile,candidate):
    page.goto('about:blank');page.set_content(HTML,wait_until='load');page.locator('#profile').select_option(profile);page.locator('#candidate').select_option(candidate);page.locator('#start').click()

def path(page,withchecks=False,tag='',width=390,screenshot=False):
    initial=state(page);n=len(initial['remaining']);r=initial['input']['summary'];proposal=initial['input']['proposal']['ids']
    if withchecks:
        check(tag+':draw_count',n==r['draws']);check(tag+':nothing_scrapped_at_start',initial['dust']==0 and not initial['committed']);layout(page,tag+':result',width)
    if proposal:
        click(page,'cleanup')
        if withchecks:
            check(tag+':unchecked_by_default',not state(page)['selected']);check(tag+':confirm_disabled',page.locator('[data-action="quote"]').is_disabled());layout(page,tag+':cleanup',width)
        click(page,'select');click(page,'quote')
        if withchecks:
            check(tag+':quote_no_mutation',len(state(page)['remaining'])==n and state(page)['dust']==0);layout(page,tag+':quote',width)
        click(page,'commit');after=state(page)
        if withchecks:
            check(tag+':conservation',len(after['remaining'])+len(proposal)==n);check(tag+':powder_matches_python',after['dust']==r['powder']['low']);layout(page,tag+':done',width)
            before=[x['uid'] for x in initial['remaining'] if x['locked'] or x['first_discovery']]
            check(tag+':protected_present',set(before)<={x['uid'] for x in after['remaining']})
        if screenshot:
            p=OUT/(tag.replace(':','_')+'_done.png');page.screenshot(path=str(p),full_page=False);captures.append(p.name)
    click(page,'forge');before=state(page)
    if not page.locator('[data-action="enhance"]').is_disabled():
        click(page,'enhance');after=state(page)
        if withchecks:
            check(tag+':upgrade_cost5',before['dust']-after['dust']==5);check(tag+':upgrade1',after['level']==1)
    else:
        if withchecks:check(tag+':no_fake_upgrade',before['dust']<5 and before['level']==0)
    if withchecks:layout(page,tag+':forge',width)
    elapsed=page.evaluate('(performance.now()-window.__qa.state().start)/1000')
    actions=len(state(page)['actions']);click(page,'finish')
    return {'scripted_to_first_upgrade_or_no_funds_seconds':elapsed,'actions_before_finish':actions,'record':state(page)['record']}

def main():
    with sync_playwright() as pl:
        b=pl.chromium.launch(executable_path='/usr/bin/chromium',headless=True,args=['--no-sandbox'])
        for width,height in [(375,667),(390,844),(402,874)]:
            p=b.new_page(viewport={'width':width,'height':height});p.on('pageerror',lambda e:errors.append(str(e)));p.on('request',lambda req:network.append(req.url))
            for profile in ('first_box','established_box'):
                for c in ('A','C'):
                    tag=f'{width}_{profile}_{c}';setup(p,profile,c);path(p,True,tag,width,screenshot=width==390 and c=='C')
            p.close()
        p=b.new_page(viewport={'width':390,'height':844});p.on('pageerror',lambda e:errors.append(str(e)));p.on('request',lambda req:network.append(req.url))
        # Injected write failure: preserve result and retry exact transaction.
        setup(p,'established_box','C');click(p,'cleanup');click(p,'select');click(p,'quote');old=state(p);p.evaluate('window.__qa.failNext()');click(p,'commit');s=state(p)
        check('injected_failure:no_item_loss',s['remaining']==old['remaining']);check('injected_failure:no_powder',s['dust']==old['dust']);click(p,'commit');s=state(p)
        check('retry:committed_once',s['dust']==s['input']['summary']['powder']['low']);p.evaluate('window.__qa.duplicate()');check('retry:no_double_powder',state(p)['dust']==s['dust'])
        # A changed inventory revision invalidates the prior quote.
        setup(p,'established_box','C');click(p,'cleanup');click(p,'select');click(p,'quote');old=state(p);p.evaluate('window.__qa.stale()');click(p,'commit');s=state(p)
        check('stale:no_mutation',s['remaining']==old['remaining'] and s['dust']==0 and not s['committed'])
        setup(p,'established_box','C');click(p,'cleanup');click(p,'back');check('cancel:items_preserved',len(state(p)['remaining'])==50 and state(p)['dust']==0)
        # Script driver wall-times are separately labelled; 2 warmups per candidate.
        for c in ('A','C'):
            for rep in range(22):
                setup(p,'established_box',c);res=path(p)
                if rep>=2:timings.append({'candidate':c,'repetition':rep-2,**res})
        # Capture the actual interactive outcome and confirm panels for QA only.
        setup(p,'established_box','C');p.screenshot(path=str(OUT/'REVIEW_RESULT_MOBILE.png'),full_page=False)
        click(p,'cleanup');p.screenshot(path=str(OUT/'REVIEW_CLEANUP_MOBILE.png'),full_page=False)
        p.close();b.close()
    check('no_page_errors',not errors,errors=errors);check('no_external_requests',not network,requests=network)
    summary={}
    for c in ('A','C'):
        ts=[x['scripted_to_first_upgrade_or_no_funds_seconds'] for x in timings if x['candidate']==c]
        summary[c]={'runs':len(ts),'mean_seconds':statistics.mean(ts),'median_seconds':statistics.median(ts),'min_seconds':min(ts),'max_seconds':max(ts),'actions_before_finish':sorted({x['actions_before_finish'] for x in timings if x['candidate']==c})}
    result={'pass':all(c['pass'] for c in checks),'checkpoints':len(checks),'functional_flows':12,'checks':checks,'scripted_timings':summary,'all_timings':timings,'captures':captures,'environment':{'browser':'/usr/bin/chromium headless via Playwright','platform':platform.platform(),'python':sys.version},'limits':['No humans timed','No actual iPhone/Safari/VoiceOver','No animation or network wait','Selection decisions supplied by fixed Python fixture','CSS px, not native pt certification']}
    (OUT/'BROWSER_QA.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n');print(json.dumps({'pass':result['pass'],'checks':len(checks),'timings':summary},ensure_ascii=False,indent=2))
if __name__=='__main__':main()

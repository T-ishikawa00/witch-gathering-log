# Optional: existing Playwright/Chromium installation required. No packages are installed by this script.
from pathlib import Path
import os,shutil
from playwright.sync_api import sync_playwright
import json
root=Path(__file__).resolve().parents[1]
results=[]
with sync_playwright() as p:
 exe=os.environ.get('CHROMIUM_PATH') or shutil.which('chromium') or shutil.which('chromium-browser')
 browser=p.chromium.launch(headless=True, **({'executable_path':exe} if exe else {}))
 for width,height in [(375,667),(390,844),(430,932),(1280,900)]:
  page=browser.new_page(viewport={'width':width,'height':height},device_scale_factor=1)
  errors=[];externals=[]
  page.on('pageerror',lambda error: errors.append(str(error)))
  page.on('request',lambda r: externals.append(r.url) if r.url.startswith(('http://','https://')) else None)
  page.set_content((root/'ux/UX_PREVIEW_R2.html').read_text(), wait_until='load');page.wait_for_timeout(100)
  assert page.locator('#screen h2').inner_text()=='毒を重ねる構成'
  assert page.evaluate('document.documentElement.scrollWidth<=window.innerWidth')
  page.get_by_role('button',name='この構成の結果を見る').click()
  assert page.locator('#screen .defeat').inner_text()=='敗北'
  page.get_by_role('button',name='装備を見直す').click()
  page.get_by_role('button',name='防御寄りの変更を比較').click()
  assert page.locator('#compareDialog').is_visible()
  cancel_box=page.locator('#cancel').bounding_box()
  assert cancel_box and cancel_box['y']>=0 and cancel_box['y']+cancel_box['height']<=height
  assert page.locator('#compareDialog').evaluate('(e)=>e.scrollWidth<=e.clientWidth')
  if width==375:page.locator('#compareDialog').screenshot(path=str(root/'validation/ui_comparison_375.png'))
  page.get_by_role('button',name='この変更を適用する').click()
  assert page.locator('#screen h2').inner_text()=='毒 × 防御の混成'
  page.get_by_role('button',name='この構成の結果を見る').click()
  assert page.locator('#screen .victory').inner_text()=='突破'
  assert '245' in page.locator('#screen').inner_text()
  if width==375:page.locator('.phone').screenshot(path=str(root/'validation/ui_result_375.png'))
  page.get_by_role('button',name='別のボスを選ぶ').click()
  page.locator('[data-boss="stonebeast"]').click()
  assert page.locator('[data-boss="stonebeast"]').get_attribute('aria-pressed')=='true'
  page.get_by_role('button',name='選んだボスの結果を見る').click()
  assert '苔殻の巨獣' in page.locator('#screen').inner_text()
  page.locator('[data-screen="return"]').click()
  assert '重複26点' in page.locator('#screen').inner_text()
  assert page.evaluate('document.documentElement.scrollWidth<=window.innerWidth')
  page.locator('[data-screen="equipment"]').click()
  page.get_by_role('button',name='元の毒構成に戻す').click()
  assert page.locator('#screen h2').inner_text()=='毒を重ねる構成'
  if width==1280:page.screenshot(path=str(root/'validation/ui_desktop_1280.png'),full_page=True)
  targets=page.locator('button:visible').evaluate_all('(els)=>els.map(e=>({label:e.textContent.trim(),w:e.getBoundingClientRect().width,h:e.getBoundingClientRect().height}))')
  assert all(t['w']>=44 and t['h']>=44 for t in targets)
  assert not errors,errors
  assert not externals,externals
  results.append({'viewport':[width,height],'navigation':True,'compare_apply_revert':True,'result_matches_fixed_fixture':True,'no_horizontal_overflow':True,'visible_button_targets_min_44px':True,'js_errors':errors,'external_requests':externals})
  page.close()
 browser.close()
(root/'validation/ui_test_results.json').write_text(json.dumps({'engine':'Chromium headless; not iPhone Safari','results':results},ensure_ascii=False,indent=2))
print(json.dumps(results,ensure_ascii=False,indent=2))

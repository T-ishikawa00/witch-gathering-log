"""Render the controlled Markdown design report; not game UI or an art mockup."""
from pathlib import Path
import re,html,json
P=Path(__file__).resolve().parents[1]
text=(P/'docs/DESIGN_R2.md').read_text()
def inline(s):
 s=html.escape(s)
 s=re.sub(r'`([^`]+)`',r'<code>\1</code>',s)
 s=re.sub(r'\*\*([^*]+)\*\*',r'<strong>\1</strong>',s)
 return s
parts=[];table=[];toc=[];list_open=False

def close_list():
 global list_open
 if list_open:parts.append('</ul>');list_open=False

def flush_table():
 if not table:return
 rows=[r for r in table if not re.fullmatch(r'[|:\-\s]+',r)]
 cells=[r.strip('|').split('|') for r in rows]
 parts.append('<div class="scroll"><table><thead><tr>'+''.join('<th>'+inline(c.strip())+'</th>' for c in cells[0])+'</tr></thead><tbody>')
 for row in cells[1:]:parts.append('<tr>'+''.join('<td>'+inline(c.strip())+'</td>' for c in row)+'</tr>')
 parts.append('</tbody></table></div>');table.clear()
for line in text.splitlines():
 if line.startswith('|'):
  close_list();table.append(line);continue
 flush_table()
 if not line.strip():close_list();continue
 if line.startswith('# '):continue
 if line.startswith('## '):
  close_list();label=line[3:];anchor='section-'+str(len(toc));toc.append((anchor,label));parts.append(f'<h2 id="{anchor}">'+inline(label)+'</h2>')
 elif line.startswith('### '):close_list();parts.append('<h3>'+inline(line[4:])+'</h3>')
 elif line.startswith('- '):
  if not list_open:parts.append('<ul>');list_open=True
  parts.append('<li>'+inline(line[2:])+'</li>')
 else:close_list();parts.append('<p>'+inline(line)+'</p>')
flush_table();close_list()
a=json.loads((P/'results/ANALYSIS_RESULTS_R2.json').read_text())
summary=f'''<section class="lead"><strong>本命は「欲しい道具へ近づくガチャ」「無料進行と同じ上限の暮らし効果」「差し替え可能な衣装・武器・家具」。</strong><p>世界観とA案を守りながら、この3つを具体的なルールにした設計候補。価格・確率・効果・数量は未承認。課金開始や全量制作の許可ではありません。</p></section><section class="facts"><article><b>74項目</b><span>新しい模擬契約テスト</span></article><article><b>50,000系列</b><span>目標伝説への抽選を照合</span></article><article><b>R6・実機は未検証</b><span>今は設計と算術の段階</span></article></section>'''
css='''*{box-sizing:border-box}html{scroll-behavior:smooth}body{margin:0;background:#f7f6f1;color:#263632;font:16px/1.85 -apple-system,BlinkMacSystemFont,"Hiragino Sans","Yu Gothic",sans-serif}header{background:#172a2d;color:#f8f4e8;padding:34px max(20px,calc((100vw - 1020px)/2));border-bottom:4px solid #b59658}header .kicker{font:12px/1.6 system-ui;letter-spacing:1.5px;color:#dfc48d}header h1{font-size:clamp(25px,4vw,37px);line-height:1.4;margin:15px 0}header p{color:#d4dfda}main{max-width:1100px;margin:auto;padding:28px 32px 64px}.lead{padding:20px 24px;background:#fffaf0;border-left:4px solid #b59658}.lead p{margin-bottom:0}.facts{display:grid;grid-template-columns:repeat(3,1fr);gap:12px;margin:22px 0}.facts article{padding:16px;background:#e8efeb;border:1px solid #d0dcd4}.facts b{display:block;font-size:22px}.facts span{font-size:13px;color:#56665c}details{background:#fff;border:1px solid #d4ddd5;padding:12px 18px}summary{cursor:pointer;font-weight:650}nav{display:grid;grid-template-columns:1fr 1fr;gap:5px 18px;padding:14px 0}a{color:#275e4d;text-underline-offset:3px}h2{margin-top:40px;padding-top:14px;border-top:2px solid #b59658;font-size:24px;line-height:1.5;scroll-margin-top:16px}h3{font-size:19px;margin-top:26px;line-height:1.6}p{margin:14px 0}strong{font-weight:750}.scroll{overflow-x:auto;margin:20px 0}table{border-collapse:collapse;min-width:570px;width:100%;font-size:14px;line-height:1.7}th{background:#294740;color:white;text-align:left;padding:11px 13px}td{padding:11px 13px;vertical-align:top;border-bottom:1px solid #d4ded4}tr:nth-child(even){background:#edf1e9}code{background:#e7eae3;padding:2px 4px;border-radius:3px;overflow-wrap:anywhere;font:13px/1.7 ui-monospace,monospace}ul{padding-left:24px}li{margin:8px 0}footer{border-top:1px solid #ccd4cd;padding:18px 22px;text-align:center;font-size:12px;color:#5d6d65}@media(max-width:650px){main{padding:20px 16px 45px}.facts{grid-template-columns:1fr}.facts article{padding:11px 15px}.facts b{font-size:20px}.lead{padding:16px}nav{grid-template-columns:1fr}h2{font-size:22px}header{padding:28px 18px}body{font-size:15px}}'''
page='<!doctype html><html lang="ja"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>魔女の採集帳｜ガチャ・暮らし効果・制作規格R2</title><style>'+css+'</style></head><body><header><div class="kicker">WITCH’S GATHERING LOG · DESIGN REVIEW · 2026-10-10</div><h1>集めたくなる道具。<br>着せたくなる衣装。帰りたくなる家。</h1><p>装備ガチャ・恒常効果・制作規格 R2<br>設計レビュー資料です。ホームR3の完成画面ではありません。</p></header><main>'+summary+'<details><summary>目次</summary><nav>'+''.join(f'<a href="#{i}">{html.escape(t)}</a>' for i,t in toc)+'</nav></details>'+''.join(parts)+'</main><footer>既存の原本・美術方針を保全。新しい価格・効果・数量はHumanレビュー待ち。Mac/GitHubは未変更。</footer></body></html>'
(P/'READABLE_DESIGN.html').write_text(page)
print('HTML characters',len(page),'sections',len(toc))

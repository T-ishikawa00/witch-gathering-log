import {readFile,readdir,writeFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import assert from 'node:assert/strict';
import {DATA} from '../src/content.js';
const root = new URL('../',import.meta.url);
const reference = new URL('reference/Idle_Loot_RPG_Design_R2_20261008/',root);
const hash = b => createHash('sha256').update(b).digest('hex');
const manifest = JSON.parse(await readFile(new URL('SHA256SUMS.json',reference),'utf8'));
for (const [name,expected] of Object.entries(manifest)) assert.equal(hash(await readFile(new URL(name,reference))),expected,name+' reference was changed');
const content=await readFile(new URL('src/content.json',root));
assert.equal(hash(content),hash(await readFile(new URL('data/content.json',reference))));
assert.deepEqual(DATA,JSON.parse(content));
async function files(folder){
  const out=[];
  for(const entry of await readdir(new URL(folder,root),{withFileTypes:true})){
    const name=folder+entry.name;
    if(entry.isDirectory())out.push(...await files(name+'/'));else out.push(name);
  }
  return out;
}
const sourceFiles=['index.html','styles.css','favicon.svg','package.json',...await files('src/'),...await files('tests/'),...await files('tools/')].sort();
const hashes={};for(const name of sourceFiles)hashes[name]=hash(await readFile(new URL(name,root)));
const fingerprint=hash(JSON.stringify(hashes));
const report={version:'G1-0.1.0',date:'2026-10-08',source_fingerprint:fingerprint,source_files:hashes,reference_manifest_items:Object.keys(manifest).length,reference_unchanged:true,content_sha256:hash(content)};
await writeFile(new URL('reports/source-manifest.json',root),JSON.stringify(report,null,2));
console.log(JSON.stringify({source_fingerprint:fingerprint,files:sourceFiles.length,reference_unchanged:true,content_sha256:report.content_sha256},null,2));

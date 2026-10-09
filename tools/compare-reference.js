import { spawnSync } from 'node:child_process';
import { mkdir, writeFile } from 'node:fs/promises';
import { DATA } from '../src/content.js';
import { fight } from '../src/core/combat.js';

const refDir = new URL('../reference/Idle_Loot_RPG_Design_R2_20261008/validation/', import.meta.url);
const pythonProgram = String.raw`
import json, sys
sys.dont_write_bytecode = True
from core import fight
cases = json.load(sys.stdin)
for loadout, boss, seed in cases:
    print(json.dumps(fight(loadout, boss, seed), separators=(',', ':')))
`;

const families = ['c', 'p', 'g'];
const cases = [];
for (let code = 0; code < 3 ** DATA.slots.length; code += 1) {
  let n = code;
  const loadout = DATA.slots.map((slot) => {
    const family = families[n % 3];
    n = Math.floor(n / 3);
    return `${slot}_${family}`;
  });
  for (const boss of Object.keys(DATA.bosses)) {
    for (let seed = 101; seed <= 132; seed += 1) cases.push([loadout, boss, seed]);
  }
}

const proc = spawnSync('python3', ['-B', '-c', pythonProgram], {
  cwd: refDir,
  env: { ...process.env, PYTHONDONTWRITEBYTECODE: '1' },
  input: JSON.stringify(cases),
  encoding: 'utf8',
  maxBuffer: 128 * 1024 * 1024,
});
if (proc.error) throw proc.error;
if (proc.status !== 0) throw new Error(`Python reference failed (${proc.status}): ${proc.stderr}`);
const referenceResults = proc.stdout.trimEnd().split('\n').map((line) => JSON.parse(line));
if (referenceResults.length !== cases.length) {
  throw new Error(`Python returned ${referenceResults.length} results for ${cases.length} cases`);
}

const mismatches = [];
for (let i = 0; i < cases.length; i += 1) {
  const [loadout, boss, seed] = cases[i];
  const actual = fight(loadout, boss, seed);
  if (JSON.stringify(actual) !== JSON.stringify(referenceResults[i])) {
    mismatches.push({ index: i, loadout, boss, seed, expected: referenceResults[i], actual });
    if (mismatches.length >= 10) break;
  }
}

const report = {
  comparison: 'javascript combat port against validation/core.py',
  reference: 'Idle_Loot_RPG_Design_R2_20261008',
  status: mismatches.length === 0 && referenceResults.length === cases.length ? 'PASS' : 'FAIL',
  compared_fights: cases.length,
  matched_fights: cases.length - mismatches.length,
  mismatch_count_reported: mismatches.length,
  mismatch_samples: mismatches,
  dimensions: {
    equipment_loadouts: 3 ** DATA.slots.length,
    bosses: Object.keys(DATA.bosses),
    seeds_inclusive: [101, 132],
  },
  python_version: spawnSync('python3', ['--version'], { encoding: 'utf8' }).stdout.trim(),
  bytecode_writes_disabled: true,
};
await mkdir(new URL('../reports/', import.meta.url), { recursive: true });
await writeFile(new URL('../reports/combat-parity.json', import.meta.url), `${JSON.stringify(report, null, 2)}\n`);
console.log(`combat parity ${report.status}: ${report.matched_fights}/${report.compared_fights}`);
if (report.status !== 'PASS') process.exitCode = 1;

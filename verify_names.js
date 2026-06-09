const fs = require('fs');
const path = require('path');

const CFG_DIR = path.join(__dirname, '..', 'Data', 'StreamingAssets', 'res', 'main', 'cfg', 'data');
const MAPPING_FILE = path.join(__dirname, 'name_mapping.json');

const mapping = JSON.parse(fs.readFileSync(MAPPING_FILE, 'utf-8'));
const replacements = mapping.replacements;

console.log('=== 《女王的游戏：盛世天下》女帝篇 - 替换结果验证 ===\n');

const pbinFiles = fs.readdirSync(CFG_DIR).filter(f =>
  f.startsWith('TextClient') && f.endsWith('.pbin')
);

let allPassed = true;
const results = [];

for (const { from, to, desc } of replacements) {
  const fromBuf = Buffer.from(from, 'utf-8');
  const toBuf = Buffer.from(to, 'utf-8');

  let fromCount = 0;
  let toCount = 0;

  for (const file of pbinFiles) {
    const data = fs.readFileSync(path.join(CFG_DIR, file));
    let idx = -1;
    while ((idx = data.indexOf(fromBuf, idx + 1)) !== -1) fromCount++;
    idx = -1;
    while ((idx = data.indexOf(toBuf, idx + 1)) !== -1) toCount++;
  }

  const passed = fromCount === 0;
  if (!passed) allPassed = false;
  results.push({ desc, from, to, fromCount, toCount, passed });
}

// Print results
const col = { desc: 20, name: 12, count: 8, status: 10 };
console.log(
  '说明'.padEnd(col.desc) +
  '旧名'.padEnd(col.name) +
  '残留'.padEnd(col.count) +
  '新名'.padEnd(col.name) +
  '出现'.padEnd(col.count) +
  '状态'
);
console.log('-'.repeat(80));

for (const r of results) {
  const status = r.passed ? 'OK' : 'FAIL(' + r.fromCount + ')';
  console.log(
    r.desc.padEnd(col.desc) +
    r.from.padEnd(col.name) +
    String(r.fromCount).padEnd(col.count) +
    r.to.padEnd(col.name) +
    String(r.toCount).padEnd(col.count) +
    status
  );
}

console.log('-'.repeat(80));
console.log(allPassed ? '\n全部通过! 旧名已全部替换为历史原名。' : '\n存在未完成的替换，请重新运行 replace_names.js');

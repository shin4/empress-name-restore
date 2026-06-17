const fs = require('fs');
const path = require('path');

const SRT_DIR = path.join(__dirname, '..', 'Data', 'StreamingAssets', 'res', 'main', 'SSTX2', 'Global', 'srt');
const MAPPING_FILE = path.join(__dirname, 'name_mapping.json');

const mapping = JSON.parse(fs.readFileSync(MAPPING_FILE, 'utf-8'));
const replacements = mapping.replacements;

console.log('=== 《女王的游戏：盛世天下》女帝篇 - 字幕替换验证 ===\n');

// Build replacement pairs
const simpPairs = [];
const tradPairs = [];
const simpPairsNoTrad = [];

for (const entry of replacements) {
  simpPairs.push({ from: entry.from, to: entry.to, desc: entry.desc });

  if (entry.fromTrad) {
    const toTrad = entry.toTrad || entry.to;
    tradPairs.push({ from: entry.fromTrad, to: toTrad, desc: entry.desc });
  } else {
    simpPairsNoTrad.push({ from: entry.from, to: entry.to, desc: entry.desc });
  }
}

// Get SRT files
function getSrtFiles(dir) {
  const files = [];
  if (!fs.existsSync(dir)) return files;
  const items = fs.readdirSync(dir, { withFileTypes: true });
  for (const item of items) {
    const fullPath = path.join(dir, item.name);
    if (item.isDirectory()) {
      files.push(...getSrtFiles(fullPath));
    } else if (item.name.endsWith('.srt')) {
      files.push(fullPath);
    }
  }
  return files;
}

const zhGLFiles = getSrtFiles(path.join(SRT_DIR, 'zh_GL'));
const zhTWFiles = getSrtFiles(path.join(SRT_DIR, 'zh_TW'));

console.log('zh_GL 字幕文件: ' + zhGLFiles.length + ' 个');
console.log('zh_TW 字幕文件: ' + zhTWFiles.length + ' 个');
console.log('');

let allPassed = true;
const results = [];

// Check zh_GL (simplified)
for (const { from, to, desc } of simpPairs) {
  let fromCount = 0;
  let toCount = 0;

  for (const file of zhGLFiles) {
    const content = fs.readFileSync(file, 'utf8');
    const fromRegex = new RegExp(escapeRegex(from), 'g');
    const toRegex = new RegExp(escapeRegex(to), 'g');
    const fromMatches = content.match(fromRegex);
    const toMatches = content.match(toRegex);
    if (fromMatches) fromCount += fromMatches.length;
    if (toMatches) toCount += toMatches.length;
  }

  const passed = fromCount === 0;
  if (!passed) allPassed = false;
  results.push({ desc, from, to, fromCount, toCount, passed, lang: 'zh_GL' });
}

// Check zh_TW (traditional)
for (const { from, to, desc } of [...tradPairs, ...simpPairsNoTrad]) {
  let fromCount = 0;
  let toCount = 0;

  for (const file of zhTWFiles) {
    const content = fs.readFileSync(file, 'utf8');
    const fromRegex = new RegExp(escapeRegex(from), 'g');
    const toRegex = new RegExp(escapeRegex(to), 'g');
    const fromMatches = content.match(fromRegex);
    const toMatches = content.match(toRegex);
    if (fromMatches) fromCount += fromMatches.length;
    if (toMatches) toCount += toMatches.length;
  }

  const passed = fromCount === 0;
  if (!passed) allPassed = false;
  results.push({ desc, from, to, fromCount, toCount, passed, lang: 'zh_TW' });
}

// Print results
const col = { desc: 16, lang: 8, name: 10, count: 8, status: 10 };
console.log(
  '说明'.padEnd(col.desc) +
  '语言'.padEnd(col.lang) +
  '旧名'.padEnd(col.name) +
  '残留'.padEnd(col.count) +
  '状态'
);
console.log('-'.repeat(60));

for (const r of results) {
  const status = r.passed ? 'OK' : 'FAIL(' + r.fromCount + ')';
  console.log(
    r.desc.padEnd(col.desc) +
    r.lang.padEnd(col.lang) +
    r.from.padEnd(col.name) +
    String(r.fromCount).padEnd(col.count) +
    status
  );
}

console.log('-'.repeat(60));
console.log(allPassed ? '\n全部通过! 字幕旧名已全部替换。' : '\n存在未完成的替换，请重新运行 replace_subtitles.js');

function escapeRegex(string) {
  return string.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

const fs = require('fs');
const path = require('path');

const CFG_DIR = path.join(__dirname, '..', 'Data', 'StreamingAssets', 'res', 'main', 'cfg', 'data');
const BACKUP_DIR = path.join(CFG_DIR, '_backup_original');
const MAPPING_FILE = path.join(__dirname, 'name_mapping.json');

const mapping = JSON.parse(fs.readFileSync(MAPPING_FILE, 'utf-8'));
const replacements = mapping.replacements;

console.log('=== 《女王的游戏：盛世天下》女帝篇 - 和谐人名还原 ===\n');

// 1. Backup
if (!fs.existsSync(BACKUP_DIR)) {
  fs.mkdirSync(BACKUP_DIR, { recursive: true });
  const pbinFiles = fs.readdirSync(CFG_DIR).filter(f => f.endsWith('.pbin'));
  for (const f of pbinFiles) {
    fs.copyFileSync(path.join(CFG_DIR, f), path.join(BACKUP_DIR, f));
  }
  console.log('[备份] 已备份 ' + pbinFiles.length + ' 个原始文件到 _backup_original\n');
} else {
  console.log('[备份] 备份已存在，跳过\n');
}

// 2. Build buffer pairs with Traditional Chinese support
console.log('--- 构建替换对 ---');
let allSafe = true;
const simpPairs = [];  // from→to, from→toTrad for zh_TW
const tradPairs = [];  // fromTrad→to, fromTrad→toTrad for zh_TW

for (const entry of replacements) {
  const fromBuf = Buffer.from(entry.from, 'utf-8');
  const toBuf = Buffer.from(entry.to, 'utf-8');
  if (fromBuf.length !== toBuf.length) {
    console.error('[错误] ' + entry.desc + ': ' + entry.from + '→' + entry.to + ' 字节不等!');
    allSafe = false;
    continue;
  }

  const toTradBuf = entry.toTrad ? Buffer.from(entry.toTrad, 'utf-8') : null;
  if (toTradBuf && fromBuf.length !== toTradBuf.length) {
    console.error('[错误] ' + entry.desc + ': 繁简目标字节数不等!');
    allSafe = false;
    continue;
  }

  simpPairs.push({ fromBuf, toBuf, toTradBuf, desc: entry.desc });

  if (entry.fromTrad) {
    const fromTradBuf = Buffer.from(entry.fromTrad, 'utf-8');
    if (fromTradBuf.length === toBuf.length) {
      tradPairs.push({ fromBuf: fromTradBuf, toBuf, toTradBuf, desc: entry.desc });
    }
  }
}

if (!allSafe) {
  console.error('\n存在不安全的替换对，已中止。');
  process.exit(1);
}
console.log('[检查] 全部替换对均等字节，安全\n');

// 3. Process files
const pbinFiles = fs.readdirSync(CFG_DIR).filter(f =>
  f.startsWith('TextClient') && f.endsWith('.pbin')
);

let totalReplacements = 0;
let totalFilesModified = 0;

console.log('--- 开始替换 ---');
for (const file of pbinFiles) {
  const filePath = path.join(CFG_DIR, file);
  let data = fs.readFileSync(filePath);
  let fileReplacements = 0;
  const isTrad = file.includes('zh_TW');

  // Build active pairs for this file
  const activePairs = [];
  for (const p of simpPairs) {
    activePairs.push({
      fromBuf: p.fromBuf,
      toBuf: (isTrad && p.toTradBuf) ? p.toTradBuf : p.toBuf
    });
  }
  for (const p of tradPairs) {
    activePairs.push({
      fromBuf: p.fromBuf,
      toBuf: (isTrad && p.toTradBuf) ? p.toTradBuf : p.toBuf
    });
  }

  for (const { fromBuf, toBuf } of activePairs) {
    let idx = -1;
    while ((idx = data.indexOf(fromBuf, idx + 1)) !== -1) {
      toBuf.copy(data, idx);
      fileReplacements++;
      totalReplacements++;
    }
  }

  if (fileReplacements > 0) {
    fs.writeFileSync(filePath, data);
    totalFilesModified++;
    console.log('[修改] ' + file + ': ' + fileReplacements + ' 处');
  }
}

console.log('\n=== 完成 ===');
console.log('修改文件: ' + totalFilesModified + ' 个');
console.log('替换总数: ' + totalReplacements + ' 处');
console.log('备份位置: ' + BACKUP_DIR);
console.log('\n如需还原: node restore_names.js');
console.log('如需验证: node verify_names.js');

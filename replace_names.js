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

// 2. Verify byte lengths
console.log('--- 字节长度检查 ---');
let allSafe = true;
for (const { from, to, desc } of replacements) {
  const fb = Buffer.from(from, 'utf-8').length;
  const tb = Buffer.from(to, 'utf-8').length;
  if (fb !== tb) {
    console.error('[错误] ' + desc + ': ' + from + '(' + fb + 'B) -> ' + to + '(' + tb + 'B) 字节不等!');
    allSafe = false;
  }
}
if (!allSafe) {
  console.error('\n存在不安全的替换对，已中止。请修改 name_mapping.json');
  process.exit(1);
}
console.log('[检查] 全部 ' + replacements.length + ' 对替换均等字节，安全\n');

// 3. Build Buffer pairs
const bufPairs = replacements.map(({ from, to, desc }) => ({
  fromBuf: Buffer.from(from, 'utf-8'),
  toBuf: Buffer.from(to, 'utf-8'),
  from,
  to,
  desc,
}));

// 4. Process TextClient pbin files
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

  for (const { fromBuf, toBuf, desc } of bufPairs) {
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

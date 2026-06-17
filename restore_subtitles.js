const fs = require('fs');
const path = require('path');

const SRT_DIR = path.join(__dirname, '..', 'Data', 'StreamingAssets', 'res', 'main', 'SSTX2', 'Global', 'srt');
const BACKUP_DIR = path.join(SRT_DIR, '_backup_subtitles');

console.log('=== 《女王的游戏：盛世天下》女帝篇 - 还原原始字幕 ===\n');

if (!fs.existsSync(BACKUP_DIR)) {
  console.error('[错误] 备份目录 _backup_subtitles 不存在，无法还原');
  process.exit(1);
}

const langs = ['zh_TW', 'zh_GL'];
let restored = 0;

for (const lang of langs) {
  const backupLangDir = path.join(BACKUP_DIR, lang);
  if (!fs.existsSync(backupLangDir)) continue;

  const langDir = path.join(SRT_DIR, lang);
  const files = getSrtFiles(backupLangDir);

  for (const file of files) {
    const relativePath = path.relative(backupLangDir, file);
    const dstFile = path.join(langDir, relativePath);
    const dstDir = path.dirname(dstFile);
    if (!fs.existsSync(dstDir)) {
      fs.mkdirSync(dstDir, { recursive: true });
    }
    fs.copyFileSync(file, dstFile);
    restored++;
  }
}

console.log('[还原] 已恢复 ' + restored + ' 个字幕文件到原始状态');
console.log('\n如需删除备份目录，请手动执行:');
console.log('  Remove-Item -Recurse "' + BACKUP_DIR + '"');

function getSrtFiles(dir) {
  const files = [];
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

const fs = require('fs');
const path = require('path');

const SRT_DIR = path.join(__dirname, '..', 'Data', 'StreamingAssets', 'res', 'main', 'SSTX2', 'Global', 'srt');
const BACKUP_DIR = path.join(SRT_DIR, '_backup_subtitles');
const MAPPING_FILE = path.join(__dirname, 'name_mapping.json');

const mapping = JSON.parse(fs.readFileSync(MAPPING_FILE, 'utf-8'));
const replacements = mapping.replacements;

console.log('=== 《女王的游戏：盛世天下》女帝篇 - 字幕人名还原 ===\n');

// 1. Backup
if (!fs.existsSync(BACKUP_DIR)) {
  fs.mkdirSync(BACKUP_DIR, { recursive: true });

  const langs = ['zh_TW', 'zh_GL'];
  let totalFiles = 0;

  for (const lang of langs) {
    const langDir = path.join(SRT_DIR, lang);
    if (!fs.existsSync(langDir)) continue;

    const backupLangDir = path.join(BACKUP_DIR, lang);
    fs.mkdirSync(backupLangDir, { recursive: true });

    const files = getSrtFiles(langDir);
    for (const file of files) {
      const relativePath = path.relative(langDir, file);
      const backupFile = path.join(backupLangDir, relativePath);
      const backupSubDir = path.dirname(backupFile);
      if (!fs.existsSync(backupSubDir)) {
        fs.mkdirSync(backupSubDir, { recursive: true });
      }
      fs.copyFileSync(file, backupFile);
      totalFiles++;
    }
  }

  console.log('[备份] 已备份 ' + totalFiles + ' 个字幕文件到 _backup_subtitles\n');
} else {
  console.log('[备份] 备份已存在，跳过\n');
}

// 2. Build replacement pairs
console.log('--- 构建替换对 ---');
const simpPairs = [];  // from→to (for zh_GL)
const tradPairs = [];  // fromTrad→toTrad (for zh_TW)
const simpPairsNoTrad = [];  // entries without fromTrad (same form in zh_TW)

for (const entry of replacements) {
  simpPairs.push({ from: entry.from, to: entry.to, desc: entry.desc });

  if (entry.fromTrad) {
    const toTrad = entry.toTrad || entry.to;
    tradPairs.push({ from: entry.fromTrad, to: toTrad, desc: entry.desc });
  } else {
    simpPairsNoTrad.push({ from: entry.from, to: entry.to, desc: entry.desc });
  }
}

console.log('[检查] 简体替换对: ' + simpPairs.length + ', 繁体替换对: ' + tradPairs.length + ', 通用替换对: ' + simpPairsNoTrad.length + '\n');

// 3. Process SRT files
const langs = [
  { dir: 'zh_TW', pairs: [...tradPairs, ...simpPairsNoTrad], name: '繁体' },
  { dir: 'zh_GL', pairs: simpPairs, name: '简体' }
];

let totalReplacements = 0;
let totalFilesModified = 0;

console.log('--- 开始替换 ---');

for (const lang of langs) {
  const langDir = path.join(SRT_DIR, lang.dir);
  if (!fs.existsSync(langDir)) {
    console.log('[跳过] ' + lang.dir + ' 目录不存在');
    continue;
  }

  const files = getSrtFiles(langDir);
  let langReplacements = 0;
  let langFilesModified = 0;

  for (const file of files) {
    const content = fs.readFileSync(file, 'utf8');
    let newContent = content;
    let fileReplacements = 0;

    for (const pair of lang.pairs) {
      const regex = new RegExp(escapeRegex(pair.from), 'g');
      const matches = newContent.match(regex);
      if (matches) {
        newContent = newContent.replace(regex, pair.to);
        fileReplacements += matches.length;
      }
    }

    if (fileReplacements > 0) {
      fs.writeFileSync(file, newContent, 'utf8');
      langReplacements += fileReplacements;
      langFilesModified++;
      totalReplacements += fileReplacements;
      totalFilesModified++;
    }
  }

  console.log('[修改] ' + lang.dir + ' (' + lang.name + '): ' + langFilesModified + ' 个文件, ' + langReplacements + ' 处替换');
}

console.log('\n=== 完成 ===');
console.log('修改文件: ' + totalFilesModified + ' 个');
console.log('替换总数: ' + totalReplacements + ' 处');
console.log('备份位置: ' + BACKUP_DIR);
console.log('\n如需还原: node restore_subtitles.js');
console.log('如需验证: node verify_subtitles.js');

// Helper functions
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

function escapeRegex(string) {
  return string.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

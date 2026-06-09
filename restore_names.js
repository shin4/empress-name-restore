const fs = require('fs');
const path = require('path');

const CFG_DIR = path.join(__dirname, '..', 'Data', 'StreamingAssets', 'res', 'main', 'cfg', 'data');
const BACKUP_DIR = path.join(CFG_DIR, '_backup_original');

console.log('=== 《女王的游戏：盛世天下》女帝篇 - 还原原始文件 ===\n');

if (!fs.existsSync(BACKUP_DIR)) {
  console.error('[错误] 备份目录 _backup_original 不存在，无法还原');
  process.exit(1);
}

const backupFiles = fs.readdirSync(BACKUP_DIR).filter(f => f.endsWith('.pbin'));
let restored = 0;

for (const f of backupFiles) {
  const src = path.join(BACKUP_DIR, f);
  const dst = path.join(CFG_DIR, f);
  fs.copyFileSync(src, dst);
  restored++;
}

console.log('[还原] 已恢复 ' + restored + ' 个文件到原始状态');
console.log('\n如需删除备份目录，请手动执行:');
console.log('  Remove-Item -Recurse "' + BACKUP_DIR + '"');

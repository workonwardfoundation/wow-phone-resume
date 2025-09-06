const path = require('path');
const fs = require('fs');

const targetDirs = ['src'];
const listToDelete = ['dist'];

for (const n of listToDelete) {
  const target = path.join(__dirname, '..', n);
  if (fs.existsSync(target)) {
    fs.rmSync(target, { recursive: true, force: true });
  }
}
for (const dir of targetDirs) {
  for (const n of listToDelete) {
    const target = path.join(__dirname, '..', 'workspaces', dir, n);

    if (fs.existsSync(target)) {
      fs.rmSync(target, { recursive: true, force: true });
    }
  }
}

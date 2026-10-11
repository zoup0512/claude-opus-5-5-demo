// 开发期静态自检：括号平衡 + import/export 交叉验证
const fs = require('fs');
const path = require('path');
const files = [];
function walk(dir) {
  for (const f of fs.readdirSync(dir)) {
    const p = path.join(dir, f);
    if (fs.statSync(p).isDirectory()) walk(p);
    else if (/\.(ets|ts|cpp|h)$/.test(f)) files.push(p);
  }
}
walk(path.join(__dirname, '..', 'entry', 'src', 'main'));
let bad = 0;
for (const f of files) {
  const s = fs.readFileSync(f, 'utf8');
  let t = s.replace(/\/\*[\s\S]*?\*\//g, '').replace(/\/\/[^\n]*/g, '')
    .replace(/R"([\s\S]*?)"/g, '').replace(/"(?:[^"\\\n]|\\.)*"/g, '""').replace(/'(?:[^'\\\n]|\\.)*'/g, "''");
  const pairs = [['{', '}'], ['(', ')'], ['[', ']']];
  for (const pr of pairs) {
    const ca = (t.match(new RegExp('\\' + pr[0], 'g')) || []).length;
    const cb = (t.match(new RegExp('\\' + pr[1], 'g')) || []).length;
    if (ca !== cb) { console.log(`UNBALANCED ${pr[0]}${pr[1]} in ${f}: ${ca} vs ${cb}`); bad++; }
  }
}
console.log(bad === 0 ? 'brackets OK' : `${bad} bracket issues`);
const ets = files.filter(f => f.endsWith('.ets'));
const exportsMap = new Map();
for (const f of ets) {
  const s = fs.readFileSync(f, 'utf8');
  const re = /export\s+(?:class|interface|function|const|enum|struct)\s+([A-Za-z_$][\w$]*)/g;
  let m;
  const names = new Set();
  while ((m = re.exec(s))) names.add(m[1]);
  const re2 = /export\s*\{([^}]+)\}/g;
  while ((m = re2.exec(s))) m[1].split(',').forEach(x => names.add(x.trim().split(' ')[0]));
  exportsMap.set(f, names);
}
for (const f of ets) {
  const s = fs.readFileSync(f, 'utf8');
  const re = /import\s+(?:\*\s+as\s+(\w+)|\{([^}]+)\})\s+from\s+'([^']+)'/g;
  let m;
  while ((m = re.exec(s))) {
    const mod = m[3];
    if (!mod.startsWith('.')) continue;
    const target = path.resolve(path.dirname(f), mod);
    const tf = ets.find(x => x === target + '.ets' || x === target);
    if (!tf) { console.log(`MISSING MODULE ${mod} imported by ${f}`); bad++; continue; }
    if (m[1]) continue;
    const names = m[2].split(',').map(x => x.trim().split(/\s+as\s+/)[0]).filter(Boolean);
    const exp = exportsMap.get(tf);
    for (const n of names) {
      if (!exp.has(n)) { console.log(`MISSING EXPORT '${n}' from ${mod} (imported by ${path.basename(f)})`); bad++; }
    }
  }
}
console.log(bad === 0 ? 'imports OK' : `${bad} import issues`);

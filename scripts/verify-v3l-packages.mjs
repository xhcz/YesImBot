import { execFileSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { readdir, readFile, mkdir, copyFile, writeFile } from 'node:fs/promises';
import path from 'node:path';

const root = process.cwd();
const packagesDir = path.join(root, 'packages');
const output = path.join(root, 'artifacts', 'v3l-packages');
const dirs = (await readdir(packagesDir, { withFileTypes: true })).filter(item => item.isDirectory());
const expected = new Map();
const archives = [];

for (const dir of dirs) {
  const folder = path.join(packagesDir, dir.name);
  const pkg = JSON.parse(await readFile(path.join(folder, 'package.json'), 'utf8'));
  if (!pkg.scripts?.build) continue;
  if (!pkg.scripts.pack) throw new Error(`${pkg.name} has a build script but no pack script`);
  expected.set(pkg.name, pkg.version);
  for (const file of await readdir(folder)) if (file.endsWith('.tgz')) archives.push(path.join(folder, file));
}
if (!expected.size) throw new Error('No packages with build scripts found');
await mkdir(output, { recursive: true });
const seen = new Set();
const manifest = [];
const hashes = [];
for (const archive of archives) {
  const packed = JSON.parse(execFileSync('tar', ['-xOzf', archive, 'package/package.json'], { encoding: 'utf8' }));
  if (!expected.has(packed.name) || expected.get(packed.name) !== packed.version || seen.has(packed.name)) {
    throw new Error(`Unexpected or duplicate package: ${packed.name}@${packed.version}`);
  }
  const paths = execFileSync('tar', ['-tzf', archive], { encoding: 'utf8' }).split('\n');
  if (!paths.some(item => /^package\/(lib|dist)\/[^/]/.test(item))) throw new Error(`${packed.name} contains no compiled output`);
  seen.add(packed.name);
  const file = path.basename(archive);
  const bytes = await readFile(archive);
  const sha256 = createHash('sha256').update(bytes).digest('hex');
  await copyFile(archive, path.join(output, file));
  manifest.push({ name: packed.name, version: packed.version, file, sha256 });
  hashes.push(`${sha256}  ${file}`);
}
const missing = [...expected.keys()].filter(name => !seen.has(name));
if (missing.length) throw new Error(`Missing packed packages: ${missing.join(', ')}`);
manifest.sort((a, b) => a.name.localeCompare(b.name));
const sourceSha = execFileSync('git', ['rev-parse', 'HEAD'], { encoding: 'utf8' }).trim();
await writeFile(path.join(output, 'build-info.json'), JSON.stringify({
  repository: process.env.GITHUB_REPOSITORY || 'xhcz/YesImBot',
  sourceRef: process.env.SOURCE_REF || 'local', sourceSha,
  runId: process.env.GITHUB_RUN_ID || null, packages: manifest,
}, null, 2) + '\n');
await writeFile(path.join(output, 'SHA256SUMS'), hashes.sort().join('\n') + '\n');
console.log(`Verified all ${expected.size} packages from ${sourceSha}`);

#!/usr/bin/env bash
set -euo pipefail

# Copy this file to ~/koishi and run it there, or pass --dir /path/to/koishi.
repo='xhcz/YesImBot'
source_ref='ci/v3l-test-build'
koishi_dir="$PWD"
run_id=''
archive=''
install_all=0
dry_run=0
while (($#)); do
  case "$1" in
    --repo) repo="$2"; shift 2 ;;
    --ref) source_ref="$2"; shift 2 ;;
    --dir) koishi_dir="$2"; shift 2 ;;
    --run-id) run_id="$2"; shift 2 ;;
    --archive) archive="$2"; shift 2 ;;
    --all) install_all=1; shift ;;
    --dry-run) dry_run=1; shift ;;
    -h|--help)
      cat <<'HELP'
Usage: ./install-v3l-artifact.sh [--run-id ID] [--dir ~/koishi] [--all] [--dry-run]
  --run-id ID   Pin a successful GitHub Actions run; otherwise use the latest.
  --all         Install every built package (default: YesImBot core and OneBot directory).
  --ref BRANCH  Expected source branch (default: ci/v3l-test-build).
  --archive ZIP Verify a locally downloaded Actions artifact instead of fetching it.
  GH_TOKEN or GITHUB_TOKEN is optional for public artifacts; set it if GitHub denies download.
HELP
      exit 0 ;;
    *) printf 'Unknown option: %s\n' "$1" >&2; exit 2 ;;
  esac
done
[[ "$repo" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || { echo 'Invalid repo' >&2; exit 2; }
[[ "$run_id" == '' || "$run_id" =~ ^[0-9]+$ ]] || { echo 'Invalid run ID' >&2; exit 2; }
[[ -f "$koishi_dir/package.json" ]] || { echo "No Koishi package.json at $koishi_dir" >&2; exit 2; }
koishi_dir="$(cd "$koishi_dir" && pwd)"
if [[ -n "$archive" ]]; then archive="$(realpath "$archive")"; fi
export YIB_REPO="$repo" YIB_SOURCE_REF="$source_ref" YIB_RUN_ID="$run_id"
export YIB_KOISHI_DIR="$koishi_dir" YIB_ARCHIVE="$archive" YIB_INSTALL_ALL="$install_all"

mapfile -t package_files < <(python3 - <<'PY'
import hashlib, json, os, pathlib, shutil, sys, tempfile, urllib.parse, urllib.request, zipfile
repo = os.environ['YIB_REPO']
source_ref = os.environ['YIB_SOURCE_REF']
run_id = os.environ['YIB_RUN_ID']
root = pathlib.Path(os.environ['YIB_KOISHI_DIR'])
local_archive = os.environ['YIB_ARCHIVE']
token = os.environ.get('GH_TOKEN') or os.environ.get('GITHUB_TOKEN')
base = f'https://api.github.com/repos/{repo}'
class SafeRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        target = super().redirect_request(req, fp, code, msg, headers, newurl)
        if target and urllib.parse.urlparse(newurl).hostname != 'api.github.com':
            target.remove_header('Authorization')
        return target
opener = urllib.request.build_opener(SafeRedirect())
def fetch(url):
    headers = {'Accept': 'application/vnd.github+json', 'User-Agent': 'yesimbot-artifact-installer'}
    if token: headers['Authorization'] = 'Bearer ' + token
    return opener.open(urllib.request.Request(url, headers=headers), timeout=60).read()
def data(url): return json.loads(fetch(url))
if local_archive:
    zip_bytes = pathlib.Path(local_archive).read_bytes()
else:
    if not run_id:
        runs = data(f'{base}/actions/workflows/manual-v3l-build.yml/runs?event=workflow_dispatch&status=success&per_page=30')['workflow_runs']
        if not runs: sys.exit('No successful manual builds found; pass --run-id after running the workflow')
        run_id = str(runs[0]['id'])
    artifacts = data(f'{base}/actions/runs/{run_id}/artifacts')['artifacts']
    match = next((item for item in artifacts if item['name'] == 'v3l-packages' and not item['expired']), None)
    if not match: sys.exit(f'Run {run_id} has no available v3l-packages artifact')
    zip_bytes = fetch(match['archive_download_url'])
with tempfile.TemporaryDirectory(prefix='v3l-', dir=root) as temp:
    stage = pathlib.Path(temp)
    with zipfile.ZipFile(__import__('io').BytesIO(zip_bytes)) as bundle:
        for item in bundle.infolist():
            name = pathlib.PurePosixPath(item.filename)
            if len(name.parts) != 1 or name.name in ('', '.', '..') or item.is_dir():
                sys.exit(f'Unexpected artifact path: {item.filename}')
            (stage / name.name).write_bytes(bundle.read(item))
    info = json.loads((stage / 'build-info.json').read_text())
    if info['repository'] != repo or info['sourceRef'] != source_ref:
        sys.exit(f'Artifact source mismatch: {info["repository"]}@{info["sourceRef"]} (expected {repo}@{source_ref})')
    if run_id and str(info['runId']) != run_id: sys.exit('Artifact run ID mismatch')
    if not run_id: run_id = str(info['runId'] or 'local')
    selected = info['packages'] if os.environ['YIB_INSTALL_ALL'] == '1' else [
        entry for entry in info['packages'] if entry['name'] in {
            'koishi-plugin-yesimbot', 'koishi-plugin-yesimbot-extension-onebot-directory'}]
    if len(selected) != (len(info['packages']) if os.environ['YIB_INSTALL_ALL'] == '1' else 2):
        sys.exit('Artifact is missing one or more requested packages')
    checksums = dict(line.split('  ', 1) for line in (stage / 'SHA256SUMS').read_text().splitlines())
    for entry in info['packages']:
        file = entry['file']
        if pathlib.PurePosixPath(file).name != file: sys.exit('Invalid package filename')
        digest = hashlib.sha256((stage / file).read_bytes()).hexdigest()
        if digest != entry['sha256'] or checksums.get(digest) != file: sys.exit(f'Checksum mismatch: {file}')
    target = root / '.yesimbot-artifacts' / run_id
    target.mkdir(parents=True, exist_ok=True)
    for item in stage.iterdir(): shutil.copy2(item, target / item.name)
    print(f'Build {run_id}: {info["sourceSha"]}; verified {len(info["packages"])} packages', file=sys.stderr)
    for entry in selected: print(target / entry['file'])
PY
)
((${#package_files[@]})) || { echo 'No packages selected' >&2; exit 1; }
if ((dry_run)); then printf 'Would install: %s\n' "${package_files[@]}"; exit 0; fi
cd "$koishi_dir"
if [[ -f bun.lock || -f bun.lockb ]]; then manager=bun
elif [[ -f pnpm-lock.yaml ]]; then manager=pnpm
elif [[ -f yarn.lock ]]; then manager=yarn
else manager=npm; fi
command -v "$manager" >/dev/null || { echo "$manager is required but not installed" >&2; exit 1; }
case "$manager" in
  bun) bun add --exact "${package_files[@]}" ;;
  pnpm) pnpm add --save-exact "${package_files[@]}" ;;
  yarn) yarn add --exact "${package_files[@]}" ;;
  npm) npm install --save-exact --no-audit --no-fund "${package_files[@]}" ;;
esac
printf 'Installed build %s into %s using %s\n' "$(basename "$(dirname "${package_files[0]}")")" "$koishi_dir" "$manager"

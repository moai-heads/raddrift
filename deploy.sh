#!/usr/bin/env bash
# Publish the built web/ directory to the gh-pages branch (force-adds the wasm artifact).
set -euo pipefail
cd "$(dirname "$0")"
./build.sh
touch web/.nojekyll
msg="${1:-deploy: build $(date -u +%Y-%m-%dT%H:%MZ)}"

git add -A
git commit -q -m "$msg" 2>/dev/null || true
git push -q origin main

wt="$(mktemp -d)/pages"
if git show-ref --verify -q refs/heads/gh-pages; then
  git worktree add -q --force "$wt" gh-pages
else
  git worktree add -q --force -b gh-pages "$wt"
fi
find "$wt" -mindepth 1 -maxdepth 1 ! -name .git -exec rm -rf {} +
cp -a web/. "$wt"/
( cd "$wt" && git add -Af . && git commit -q -m "$msg" 2>/dev/null || true; git push -q origin gh-pages )
git worktree remove --force "$wt"
echo "published to gh-pages"

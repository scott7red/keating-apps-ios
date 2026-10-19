#!/bin/bash
# Adds this run's feedback (the downloaded feedback-* artifacts) to the review-videos-out branch as one fresh
# commit with no history, keeping only the latest runs, so the repository stays small. Two jobs of the same
# run (simulator, testlab) can push at different times: each adds its own folders and keeps the other's.
#   review-tours/push-feedback.sh <feedback dir> <run number> <run url>
# Needs GH_TOKEN and GITHUB_REPOSITORY.
set -euo pipefail
SRC="$1"; RUN="$2"; URL="$3"
TOURS="$(cd "$(dirname "$0")" && pwd)"
W="$(mktemp -d)"
cd "$W"
git init -q .
git remote add origin "https://x-access-token:${GH_TOKEN}@github.com/${GITHUB_REPOSITORY}.git"
for attempt in 1 2 3 4 5; do
  rm -rf ./* .git/index
  LEASE=""
  if git fetch -q --depth=1 origin review-videos-out 2>/dev/null; then
    LEASE="$(git rev-parse FETCH_HEAD)"
    git checkout -q FETCH_HEAD -- .
  fi
  # Keep the 5 newest other runs.
  for d in $(ls -d [0-9]* 2>/dev/null | grep -vx "$RUN" | sort -n | head -n -5); do rm -rf "$d"; done
  mkdir -p "$RUN"
  cp -R "$SRC/." "$RUN/"
  node "$TOURS/ci.mjs" summary "$RUN" "$RUN" "$URL" > /dev/null
  printf '# Review video feedback\n\nOne folder per run of the "Review videos" workflow (only the latest runs are kept). See each run'"'"'s README.md.\n' > README.md
  git checkout -q --orphan "fresh$attempt"
  git add -A
  git -c user.name="github-actions" -c user.email="github-actions@users.noreply.github.com" commit -q -m "Review video feedback, run $RUN"
  if [ -n "$LEASE" ]; then
    git push -q --force-with-lease="review-videos-out:$LEASE" origin HEAD:review-videos-out && { echo "pushed run $RUN"; exit 0; }
  else
    git push -q origin HEAD:review-videos-out && { echo "pushed run $RUN"; exit 0; }
  fi
  echo "push raced with another job; trying again"
  sleep $((attempt * 5))
done
exit 1

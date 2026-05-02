#!/usr/bin/env bash
# cleanup_§25_branches.sh ----------------------------------------------------
#
# Deletes the §24 + §25 feature/fix branches from both local clones and from
# origin once they've been merged to main. Idempotent — re-running after
# a partial run is safe (already-gone branches are skipped quietly).
#
# Run from anywhere: the script computes paths from the CLONES array.

set -u

CLONES=(
  /Users/lovemore.gakavagmail.com/Downloads/Projects/arsworks
  /Users/lovemore.gakavagmail.com/arsworks
)

# repo | branches to remove (space-separated) — covers both local and remote.
# Branches that don't exist locally or remotely are skipped quietly.
REPOS=(
  "arscore|feat/enrich-ard-idempotent-2026-05-02 feat/§25-readme-2026-05-02 feat/§25-where-deparser-2026-05-02 fix/§25-ci-update-namespace-2026-05-02 fix/§25-collate-2026-05-02"
  "arsshells|feat/shell-to-json-2026-05-02 fix/§25-ci-track-namespace-2026-05-02 fix/§25-collate-2026-05-02"
  "arstlf|feat/render-shortcircuit-2026-05-01 feat/§25-readme-2026-05-02 feat/§25-recipe-smoke-2026-05-02 feat/§25-tfrmt-recipe-2026-05-02 fix/expand-row-order-2026-05-02 fix/§25-ci-update-namespace-2026-05-02 fix/§25-collate-2026-05-02"
  "arsstudio|feat/bundle-export-2026-05-02 feat/§25-bundle-recipe-2026-05-02 feat/§25-readme-2026-05-02 fix/§25-ci-update-namespace-2026-05-02"
  "ars|fix/§25-ci-update-namespace-2026-05-02"
  ".|feat/§25-no-arsworks-ci-2026-05-02 fix/§25-ci-predocument-2026-05-02 fix/§25-ci-skip-suggests-2026-05-02 fix/§25-ci-submodule-checkout-2026-05-02 plan/§25-reproducibility-script-2026-05-02"
)

ORG="OpenTrialReporting"

green() { printf '  \033[32m✓\033[0m %s\n' "$1"; }
dim()   { printf '  \033[2m·\033[0m %s\n' "$1"; }

for entry in "${REPOS[@]}"; do
  rel="${entry%%|*}"
  branches="${entry#*|}"

  if [[ "$rel" == "." ]]; then
    repo_name="arsworks"
    rel_path=""
  else
    repo_name="$rel"
    rel_path="/$rel"
  fi

  echo
  echo "── $repo_name ──"

  # Local deletions in every clone.
  for clone in "${CLONES[@]}"; do
    pkg_path="$clone$rel_path"
    [[ -d "$pkg_path/.git" || -f "$pkg_path/.git" ]] || continue
    for b in $branches; do
      if git -C "$pkg_path" rev-parse --verify --quiet "$b" >/dev/null; then
        # On the branch we're about to delete? Switch to main first.
        if [[ "$(git -C "$pkg_path" rev-parse --abbrev-ref HEAD)" == "$b" ]]; then
          git -C "$pkg_path" checkout main >/dev/null 2>&1
        fi
        if git -C "$pkg_path" branch -D "$b" >/dev/null 2>&1; then
          green "[local del]  $clone$rel_path: $b"
        fi
      else
        dim "[skip local] $clone$rel_path: $b (already gone)"
      fi
    done
  done

  # Remote deletions (one set per repo, not per clone). Branches that
  # never made it to origin 404 cleanly and are reported as already-gone.
  for b in $branches; do
    if gh api "/repos/$ORG/$repo_name/git/refs/heads/$b" >/dev/null 2>&1; then
      if gh api -X DELETE "/repos/$ORG/$repo_name/git/refs/heads/$b" >/dev/null 2>&1; then
        green "[remote del] $ORG/$repo_name: $b"
      fi
    else
      dim "[skip remote] $ORG/$repo_name: $b (not on origin)"
    fi
  done
done

echo
echo "Done."

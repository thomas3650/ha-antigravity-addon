# What the build takes from outside is named exactly: the base images by
# digest, Antigravity CLI by version + URL + SHA-512, the workflow actions by commit.
ROOT="$BATS_TEST_DIRNAME/.."
DF="$ROOT/ha-antigravity/Dockerfile"
WF="$ROOT/.github/workflows"

@test "every image and binary the Dockerfile builds on is pinned by digest or SHA-512" {
  [ "$(grep -c '^FROM ' "$DF")" -eq 2 ]
  grep -qE '^FROM node:22-bookworm-slim@sha256:[0-9a-f]{64} AS node$' "$DF"
  grep -qE '^FROM ubuntu:24\.04@sha256:[0-9a-f]{64}$' "$DF"
  grep -qE '^ARG AGY_VERSION=[0-9]+\.[0-9]+\.[0-9]+$' "$DF"
  grep -qE '^ARG AGY_SHA512_ARM64=[0-9a-f]{128}$' "$DF"
  grep -qE '^ARG AGY_SHA512_AMD64=[0-9a-f]{128}$' "$DF"
}

@test "the weekly workflow moves Antigravity CLI and both base images with the Dockerfile's patterns" {
  bump="$WF/bump-agy.yml"
  cp "$DF" "$BATS_TEST_TMPDIR/Dockerfile"
  new="sha256:$(printf '%064d' 7)"
  sha="$(printf '%0128d' 9)"
  agy=9.8.7 url_arm="https://storage.googleapis.com/antigravity-public/a" url_amd="https://storage.googleapis.com/antigravity-public/b"
  sha_arm="$sha" sha_amd="$sha" node="$new" ubuntu="$new"
  sed -i.bak -E \
    -e "s/^ARG AGY_VERSION=.*/ARG AGY_VERSION=$agy/" \
    -e "s|^ARG AGY_URL_ARM64=.*|ARG AGY_URL_ARM64=$url_arm|" \
    -e "s/^ARG AGY_SHA512_ARM64=.*/ARG AGY_SHA512_ARM64=$sha_arm/" \
    -e "s|^ARG AGY_URL_AMD64=.*|ARG AGY_URL_AMD64=$url_amd|" \
    -e "s/^ARG AGY_SHA512_AMD64=.*/ARG AGY_SHA512_AMD64=$sha_amd/" \
    -e "s|^(FROM node:22-bookworm-slim)@sha256:[0-9a-f]{64}|\\1@$node|" \
    -e "s|^(FROM ubuntu:24.04)@sha256:[0-9a-f]{64}|\\1@$ubuntu|" "$BATS_TEST_TMPDIR/Dockerfile"
  grep -qx "FROM node:22-bookworm-slim@$new AS node" "$BATS_TEST_TMPDIR/Dockerfile"
  grep -qx "FROM ubuntu:24.04@$new" "$BATS_TEST_TMPDIR/Dockerfile"
  grep -qx "ARG AGY_VERSION=9.8.7" "$BATS_TEST_TMPDIR/Dockerfile"
  [ "$(diff "$DF" "$BATS_TEST_TMPDIR/Dockerfile" | grep -c '^>')" -eq 7 ]
  grep -qF 's/^ARG AGY_VERSION=.*/ARG AGY_VERSION=$agy/' "$bump"
  grep -qF 's|^(FROM node:22-bookworm-slim)@sha256:[0-9a-f]{64}|\\1@$node|' "$bump"
  grep -qF 's|^(FROM ubuntu:24.04)@sha256:[0-9a-f]{64}|\\1@$ubuntu|' "$bump"
}

@test "every action a workflow uses is named by its commit, with the version beside it" {
  [ "$(grep -h 'uses:' "$WF"/*.yml | wc -l)" -ge 6 ]
  run grep -hEvc 'uses: [A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+@[0-9a-f]{40} # v[0-9]+\.[0-9]+\.[0-9]+$' <(grep -h 'uses:' "$WF"/*.yml)
  [ "$output" -eq 0 ]
}

perms() {
  sed -n "/^  $1:/,/^  ${2:-zzz}:/p" "$WF/release.yml" \
    | sed -n '/^    permissions:$/,/^    [a-z]/p' | grep '^      [a-z-]*: ' | sed 's/^ *//' | sort | tr '\n' ' '
}

@test "the release workflow gives nothing by default, and each job exactly what it uses" {
  grep -qx 'permissions: {}' "$WF/release.yml"
  [ "$(grep -c '^    permissions:$' "$WF/release.yml")" -eq 3 ]
  [ "$(perms release-please image)" = "contents: write issues: write pull-requests: write " ]
  [ "$(perms image publish)" = "contents: read packages: write " ]
  [ "$(perms publish)" = "contents: write packages: write " ]
  grep -qx '  contents: read' "$WF/ci.yml"
}

#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
SEED="$REPO_ROOT/deploy/local/seed-artifactory-icons.sh"
EXTRA_SRC="$REPO_ROOT/deploy/local/icon-assets"

HASH_PNGS=(
    '$767ada6b0e2e4386a13358e774db7968.fe66657226bf4aecaeaae7dc1fdbc6ed2615706359136887281.png'
    '$5e460010399f4830a278fb9e2f5eab83.fbea4a4ba5874eae9d0b0701ceeacfda3624650039460249707.png'
    '$abeeac484fa3443b85ccd46df464f820.38ea1b78ed99486f9880d902ec06f6102041862906458429696.png'
    '$7a2e7e4050d14b6a914851c71e1af2f0.acdfea3291d44aa6a12f473cbafd4f2613985901947735757165.png'
    '$5ade6e3f4ca944c9a32579c4a7e4a960.f3898709a5ac44b98db93d78c56b5e4c11512219954973507074.png'
    '$2ae6c0dea835446ba80b45b4c6d031ac.35e612f73d7f4d07bed3f414263b50478641439530655324090.png'
    '$d82314ef4d054eb3b178bbe92ca216b7.2f3fcdb3c8f14a4bae6230a57e4a46683083259447872393921.png'
    '$987a00c12e5843399df1d33090900dc1.d4369feb966f40eb8cec2c02434671a52426503237734807673.png'
    '$e9c05e98e5824e859a3c0d715901afbb.71ed59183d154d2795eb9219029133a013030099571157024121.png'
)

assert_file() {
    local path="$1"
    if [[ ! -s "$path" ]]; then
        echo "seed_icons_test: missing or empty: $path" >&2
        exit 1
    fi
}

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/root" "$TMP/builtin/png"
printf builtin > "$TMP/builtin/png/manualTrigger.png"

run_seed() {
    ARTIFACTORY_BASE="$TMP/root" \
    BUILTIN_SRC="$TMP/builtin" \
    EXTRA_SRC="$EXTRA_SRC" \
        bash "$SEED"
}

run_seed >/dev/null

assert_file "$TMP/root/file/png/manualTrigger.png"
[[ "$(cat "$TMP/root/file/png/manualTrigger.png")" == builtin ]] || {
    echo "seed_icons_test: builtin icon was not copied" >&2
    exit 1
}

for name in "${HASH_PNGS[@]}"; do
    assert_file "$TMP/root/file/$name"
done
for name in tapdTrigger.png scmGitTrigger.png; do
    assert_file "$TMP/root/file/png/$name"
done
assert_file "$TMP/root/file/svg/code-SVN.svg"

# 重复播种必须幂等：源内容变化不应覆盖目标已有的同名文件
printf changed > "$TMP/builtin/png/manualTrigger.png"
printf user > "$TMP/root/file/png/manualTrigger.png"
run_seed >/dev/null
[[ "$(cat "$TMP/root/file/png/manualTrigger.png")" == user ]] || {
    echo "seed_icons_test: re-seeding overwrote an existing icon" >&2
    exit 1
}

echo "seed_icons_test: PASS"

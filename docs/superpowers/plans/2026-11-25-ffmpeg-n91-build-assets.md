# FFmpeg n9.1 Build Assets Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add reproducible FFmpeg n9.1 static-build assets and a sanitized bk-ci pipeline template without committing build outputs, upstream sources, or environment-specific secrets.

**Architecture:** Keep build inputs under `tools/ffmpeg-build/`. Add a standalone static-link verifier. Extract the live bk-ci pipeline scripts into source files under `tools/ffmpeg-build/pipeline/scripts/`, reference them from a placeholder-only JSON template, and render them into an importable pipeline JSON with a small Python script. Generated files and local outputs stay ignored.

**Tech Stack:** Bash, Python 3 standard library, Docker/Alpine musl build already committed in `tools/ffmpeg-build/`, bk-ci pipeline JSON model (`linuxScript` elements).

**Spec:** `docs/superpowers/specs/2026-11-25-ffmpeg-n91-build-assets-design.md`

## Global Constraints

- FFmpeg tag is `n9.1`; expected commit is `74e4393595cf2b5857f0da925c4e0dd74ea306e5`.
- Target is Linux x86_64, musl, fully static `ffmpeg`, `ffprobe`, `ffplay`.
- Never commit build outputs: binaries, tar, `build-report.txt`, `checksums.txt`, logs, `out/`, `out.dynamic-*`.
- Never commit upstream sources, Alpine rootfs, dependency caches, `/tmp/opencode/*`, or `/home/xiesg/test/bkci-local-stash`.
- Never commit real `pipelineId`, `projectId`, project code, artifactory IP, gateway address, build image, stage tag, or agent secret values.
- Do not modify bk-ci source code. Only add/modify files under `tools/ffmpeg-build/` and docs.
- Remote is `mine` only. Never `git push origin`. Final push target is `mine master`.
- Required placeholders in rendered/template files: `__PROJECT_ID__`, `__PROJECT_CODE__`, `__PIPELINE_ID__`, `__ARTIFACTORY_BASE_URL__`, `__BK_CI_GATEWAY__`, `__BUILD_IMAGE__`, `__STAGE_TAG__`, `__LATEST_VERSION__`, `@file:`, `@base64:scripts/build-in-container.sh`.
- Forbidden literals in committed template/template scripts: `172.`, `p-8bb091809f5d4c04ac88fe7ef525f617`, `demotest`, `127.0.0.1:5000/bkci/ci:jdk17`, `28ee946a59f64949a74f3dee40a1bda4`.
- `git diff --check` must produce no output before any commit.

## Review Focus

- Missing output directory must produce a clear non-zero exit, not a crash or false pass. Pinned by Task 1 missing-file case.
- A file that merely prints `n9.1` must not pass when `file`/`ldd` say it is dynamic. Pinned by Task 1 fake-dynamic case.
- A wrong version string must fail even when static-link checks are stubbed to pass. Pinned by Task 1 wrong-version case.
- Rendered pipeline must refuse unreplaced placeholders or leftover real environment values. Pinned by Task 3 render test.
- Rendered inner script must byte-match `scripts/build-in-container.sh`; drift must fail. Pinned by Task 3 base64 round-trip assertion.

---

## File Structure

```text
tools/ffmpeg-build/
  README.md                              # modify: local + pipeline reproduction
  .gitignore                             # modify: ignore pipeline/rendered/
  scripts/verify-static.sh               # create
  test/verify_static_test.sh             # create
  pipeline/
    README.md                            # create
    ffmpeg-pipeline.template.json        # create
    render_pipeline.py                   # create
    scripts/build-in-bkci.sh             # create
    scripts/upload-artifact.sh           # create
    scripts/upload-report.sh             # create
    test/template_hygiene_test.sh        # create
    test/render_pipeline_test.sh         # create
    .gitignore                           # create: ignore rendered/
docs/superpowers/specs/2026-11-25-ffmpeg-n91-build-assets-design.md  # create (already drafted, commit here)
docs/requirements/2026-11-20-ffmpeg-source-build-plan.md             # modify: append scope note
docs/superpowers/plans/2026-11-25-ffmpeg-n91-build-assets.md          # this plan (commit here)
```

---

### Task 1: Static-link verifier

**Files:**
- Create: `tools/ffmpeg-build/scripts/verify-static.sh`
- Create: `tools/ffmpeg-build/test/verify_static_test.sh`

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces: `verify-static.sh [OUT_DIR] -> int`; exit 0 only when all three binaries pass static-link and version checks. Default `OUT_DIR` is `tools/ffmpeg-build/out` resolved relative to the script's parent directory. Optional `checksums.txt` check uses `sha256sum -c --quiet` from `OUT_DIR`.
- Produces test helper convention: fake `file` and fake `ldd` placed first on `PATH` may be used to stub static-link checks.

- [ ] **Step 1: Write the failing test**

Create `tools/ffmpeg-build/test/verify_static_test.sh` with these cases:

```bash
#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERIFY="$ROOT/scripts/verify-static.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

make_fake_tools() {
  mkdir -p "$TMP/fakebin"
  printf '#!/bin/sh\necho "ELF 64-bit LSB executable, x86-64, statically linked"\n' > "$TMP/fakebin/file"
  printf '#!/bin/sh\necho "not a dynamic executable"\n' > "$TMP/fakebin/ldd"
  chmod +x "$TMP/fakebin/file" "$TMP/fakebin/ldd"
}

make_bins() {
  local version="$1"
  mkdir -p "$TMP/fixture/bin"
  for b in ffmpeg ffprobe ffplay; do
    printf '#!/bin/sh\necho "ffmpeg version %s"\n' "$version" > "$TMP/fixture/bin/$b"
    chmod +x "$TMP/fixture/bin/$b"
  done
}

expect_fail() {
  local name="$1"; shift
  if PATH="$TMP/fakebin:$PATH" "$VERIFY" "$@" >/dev/null 2>&1; then
    echo "FAIL: $name should have failed"; exit 1
  fi
}

# 1. missing output directory / missing binaries
expect_fail "missing files" "$TMP/does-not-exist"

# 2. dynamic-looking file must be rejected even with correct version
make_bins n9.1
printf '#!/bin/sh\necho "ELF 64-bit LSB executable, dynamically linked"\n' > "$TMP/fakebin/file"
expect_fail "dynamic link" "$TMP/fixture"

# 3. wrong version must be rejected even when static checks are stubbed to pass
make_fake_tools
make_bins n8.0
expect_fail "wrong version" "$TMP/fixture"

# 4. happy path with stubbed static checks
make_fake_tools
make_bins n9.1
PATH="$TMP/fakebin:$PATH" "$VERIFY" "$TMP/fixture" | grep -q '^VERIFY_OK$'
echo "verify_static_test: PASS"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tools/ffmpeg-build/test/verify_static_test.sh`
Expected: FAIL because `tools/ffmpeg-build/scripts/verify-static.sh` does not exist.

- [ ] **Step 3: Implement `verify-static.sh`**

Create `tools/ffmpeg-build/scripts/verify-static.sh`:

- `set -euo pipefail`.
- Resolve repo-relative default: `SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"`; `OUT_DIR="${1:-$SCRIPT_DIR/out}"`.
- For each of `ffmpeg`, `ffprobe`, `ffplay`: require `-x "$OUT_DIR/bin/$name"`, else print `ERROR: missing or non-executable: ...` and exit 1.
- Capture `file -b "$bin"`; require substring `statically linked`.
- Capture `ldd "$bin" 2>&1 || true`; require substring `not a dynamic executable`.
- Capture `"$bin" -version 2>&1 | head -n 1`; require substring `n9.1`.
- If `"$OUT_DIR/checksums.txt"` exists, run `(cd "$OUT_DIR" && sha256sum -c --quiet checksums.txt)`; failure exits non-zero.
- On success print exactly `VERIFY_OK`.

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tools/ffmpeg-build/test/verify_static_test.sh`
Expected: prints `verify_static_test: PASS`.

Optional evidence check on existing local artifacts (not committed):
Run: `tools/ffmpeg-build/scripts/verify-static.sh /data/bkci-local/ffmpeg-out`
Expected: prints `VERIFY_OK`. If the directory is absent, skip; do not create it.

- [ ] **Step 5: Commit**

```bash
git add tools/ffmpeg-build/scripts/verify-static.sh tools/ffmpeg-build/test/verify_static_test.sh
git commit -m "test: add FFmpeg static-link verifier"
```

---

### Task 2: Pipeline script sources and sanitized template

**Files:**
- Create: `tools/ffmpeg-build/pipeline/scripts/build-in-bkci.sh`
- Create: `tools/ffmpeg-build/pipeline/scripts/upload-artifact.sh`
- Create: `tools/ffmpeg-build/pipeline/scripts/upload-report.sh`
- Create: `tools/ffmpeg-build/pipeline/ffmpeg-pipeline.template.json`
- Create: `tools/ffmpeg-build/pipeline/test/template_hygiene_test.sh`

**Interfaces:**
- Consumes: live pipeline structure from `/tmp/opencode/ffmpeg_pipe2.json` as reference only; do not copy real IDs/IPs into the repo.
- Produces: three script files whose contents are referenced from template JSON via `@file:<repo-relative-path>`.
- Produces: `build-in-bkci.sh` containing the literal token `@base64:scripts/build-in-container.sh`, which the renderer replaces with base64 of the committed inner build script.
- Produces: `ffmpeg-pipeline.template.json` with top-level `projectId: "__PROJECT_ID__"`, `pipelineId: "__PIPELINE_ID__"`, `name: "ffmpeg-build-n9.1"`, two stages `stage-1`/`stage-2`, trigger container, and `build-ffmpeg` container with element IDs `e-build`, `e-upload-artifact`, `e-upload-report`.
- Produces upload script env defaults: `ART="${BK_CI_ARTIFACTORY_BASE_URL:-__ARTIFACTORY_BASE_URL__}"`, `GW="${devops_gateway:-__BK_CI_GATEWAY__}"`, `PID="${BK_CI_PROJECT_NAME:-__PROJECT_CODE__}"`, `PL="${BK_CI_PIPELINE_ID:-__PIPELINE_ID__}"`.

- [ ] **Step 1: Write the failing test**

Create `tools/ffmpeg-build/pipeline/test/template_hygiene_test.sh`:

```bash
#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
T="$ROOT/pipeline/ffmpeg-pipeline.template.json"
S="$ROOT/pipeline/scripts"

for f in "$T" "$S/build-in-bkci.sh" "$S/upload-artifact.sh" "$S/upload-report.sh"; do
  [ -f "$f" ] || { echo "FAIL: missing $f"; exit 1; }
done

python3 -m json.tool "$T" >/dev/null
bash -n "$S/build-in-bkci.sh"
bash -n "$S/upload-artifact.sh"
bash -n "$S/upload-report.sh"

grep -q '@base64:scripts/build-in-container.sh' "$S/build-in-bkci.sh"
! grep -R -qE '172\.|p-8bb091809f5d4c04ac88fe7ef525f617|demotest|127\.0\.0\.1:5000/bkci/ci:jdk17|28ee946a59f64949a74f3dee40a1bda4' "$T" "$S"

python3 - "$T" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["projectId"] == "__PROJECT_ID__"
assert d["pipelineId"] == "__PIPELINE_ID__"
assert d["latestVersion"] == "__LATEST_VERSION__"
assert len(d["stages"]) == 2
els = d["stages"][1]["containers"][0]["elements"]
assert [e["id"] for e in els] == ["e-build", "e-upload-artifact", "e-upload-report"]
assert els[0]["script"] == "@file:pipeline/scripts/build-in-bkci.sh"
assert els[1]["script"] == "@file:pipeline/scripts/upload-artifact.sh"
assert els[2]["script"] == "@file:pipeline/scripts/upload-report.sh"
PY
echo "template_hygiene_test: PASS"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tools/ffmpeg-build/pipeline/test/template_hygiene_test.sh`
Expected: FAIL because the template/script files do not exist.

- [ ] **Step 3: Create the three script sources**

`pipeline/scripts/build-in-bkci.sh`:

- Copy the outer orchestration logic from live `e-build` (`/tmp/opencode/ffmpeg_pipe2.json`) exactly, but:
  - do not embed the inner base64 payload;
  - set `INNER_BUILD_SCRIPT_SRC="${INNER_BUILD_SCRIPT_SRC:-$SCRIPT_DIR/../../scripts/build-in-container.sh}"`;
  - set `INNER_BUILD_SCRIPT_B64="@base64:scripts/build-in-container.sh"`;
  - write the inner script by copying `$INNER_BUILD_SCRIPT_SRC` when it exists, otherwise by decoding `$INNER_BUILD_SCRIPT_B64` when it no longer contains `@base64:`;
  - fail with `ERROR: inner build script unavailable` if neither source works.
- Keep all `GIT_PROXY_PREFIX`, `FFMPEG_TAG`, `FFMPEG_COMMIT_EXPECTED`, `JOBS`, `OUT_HOST` env entry points.
- Keep `WORKSPACE_DIR`, `OUT_WS`, `DEPS_WS`, `ROOTFS`, Alpine `3.20.10` download, `apk add`, build, and collect steps.

`pipeline/scripts/upload-artifact.sh`:

- Copy live `e-upload-artifact` behavior.
- Replace environment-specific defaults with the placeholder defaults listed in Interfaces.
- Keep `BK_CI_BUILD_ID` as required via `${BK_CI_BUILD_ID:?}`.
- Keep env-only agent headers; no secret values.
- Keep dedup by basename, `http=200` assertion, `uploaded >= 3` assertion.

`pipeline/scripts/upload-report.sh`:

- Copy live `e-upload-report` behavior.
- Replace environment-specific defaults with the placeholder defaults listed in Interfaces.
- Keep `BK_CI_BUILD_ID` required and report registration via `reportType=INTERNAL`.
- Keep `report_http=200` assertion.

- [ ] **Step 4: Create the sanitized JSON template**

Create `tools/ffmpeg-build/pipeline/ffmpeg-pipeline.template.json` from the live pipeline model with these exact substitutions:

- `projectId` → `__PROJECT_ID__`
- `pipelineId` → `__PIPELINE_ID__`
- `latestVersion` → `__LATEST_VERSION__`
- stage tags → `["__STAGE_TAG__"]`
- dispatch image fields `value` / `imageName` → `__BUILD_IMAGE__`
- `e-build.script` → `@file:pipeline/scripts/build-in-bkci.sh`
- `e-upload-artifact.script` → `@file:pipeline/scripts/upload-artifact.sh`
- `e-upload-report.script` → `@file:pipeline/scripts/upload-report.sh`
- keep all other structure fields (`@type`, IDs, names, `additionalOptions`, `vmBuild` settings) unchanged.

- [ ] **Step 5: Run test to verify it passes**

Run: `bash tools/ffmpeg-build/pipeline/test/template_hygiene_test.sh`
Expected: prints `template_hygiene_test: PASS`.

- [ ] **Step 6: Commit**

```bash
git add tools/ffmpeg-build/pipeline
git commit -m "test: add sanitized FFmpeg pipeline template"
```

---

### Task 3: Pipeline renderer

**Files:**
- Create: `tools/ffmpeg-build/pipeline/render_pipeline.py`
- Create: `tools/ffmpeg-build/pipeline/test/render_pipeline_test.sh`

**Interfaces:**
- Consumes: `pipeline/ffmpeg-pipeline.template.json` and the three `@file:` script paths from Task 2.
- Consumes CLI args: `--project-id`, `--project-code`, `--pipeline-id`, `--artifactory-base-url`, `--gateway`, `--build-image`, `--output`; optional `--stage-tag` default `ffmpeg-r010`, `--latest-version` default `1`.
- Produces: valid JSON at `--output` with all placeholders and `@file:`/`@base64:` tokens resolved.
- Produces failure with no output file if any placeholder remains or any forbidden literal appears.

- [ ] **Step 1: Write the failing test**

Create `tools/ffmpeg-build/pipeline/test/render_pipeline_test.sh`:

```bash
#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
OUT="$TMP/ffmpeg-pipeline.json"

python3 "$ROOT/pipeline/render_pipeline.py" \
  --template "$ROOT/pipeline/ffmpeg-pipeline.template.json" \
  --project-id proj-test --project-code code-test --pipeline-id p-test \
  --artifactory-base-url http://artifactory.invalid:21920 \
  --gateway http://gateway.invalid:8080 \
  --build-image image.invalid/bkci:test \
  --output "$OUT"

python3 -m json.tool "$OUT" >/dev/null
! grep -qE '__|@file:|@base64:|172\.|p-8bb091809f5d4c04ac88fe7ef525f617|demotest' "$OUT"

python3 - "$OUT" "$ROOT/scripts/build-in-container.sh" <<'PY'
import base64, json, re, sys
text = open(sys.argv[1]).read()
expected = open(sys.argv[2], "rb").read()
m = re.search(r'INNER_BUILD_SCRIPT_B64="([^"]+)"', text)
assert m, "rendered script is missing INNER_BUILD_SCRIPT_B64"
assert base64.b64decode(m.group(1)) == expected, "inner script drift"
json.loads(text)
PY
echo "render_pipeline_test: PASS"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tools/ffmpeg-build/pipeline/test/render_pipeline_test.sh`
Expected: FAIL because `pipeline/render_pipeline.py` does not exist.

- [ ] **Step 3: Implement `render_pipeline.py`**

Implement with Python 3 standard library only:

- `resolve_file_token(token, root)`: if token matches `@file:<rel>`, return text of `<root>/<rel>`; otherwise raise.
- `resolve_base64_token(token, root)`: if token matches `@base64:<rel>`, return base64 of `<root>/<rel>` bytes with no wrapping; otherwise raise.
- Recursive replacement over loaded JSON strings:
  - exact `@file:` string → file text;
  - embedded `@base64:scripts/build-in-container.sh` → base64 text;
  - exact `__KEY__` → provided values.
- Validate the serialized result before writing:
  - no substring `__`;
  - no `@file:` or `@base64:`;
  - no forbidden literals from Global Constraints.
- Write JSON with `ensure_ascii=False`, `indent=2`.
- On validation failure, raise and do not create/truncate `--output`.

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tools/ffmpeg-build/pipeline/test/render_pipeline_test.sh`
Expected: prints `render_pipeline_test: PASS`.

- [ ] **Step 5: Commit**

```bash
git add tools/ffmpeg-build/pipeline/render_pipeline.py tools/ffmpeg-build/pipeline/test/render_pipeline_test.sh
git commit -m "test: add FFmpeg pipeline renderer"
```

---

### Task 4: Documentation, ignores, final verification and push

**Files:**
- Modify: `tools/ffmpeg-build/README.md`
- Modify: `tools/ffmpeg-build/.gitignore`
- Create: `tools/ffmpeg-build/pipeline/.gitignore`
- Create: `tools/ffmpeg-build/pipeline/README.md`
- Modify: `docs/requirements/2026-11-20-ffmpeg-source-build-plan.md`
- Commit existing drafted files: `docs/superpowers/specs/2026-11-25-ffmpeg-n91-build-assets-design.md`, `docs/superpowers/plans/2026-11-25-ffmpeg-n91-build-assets.md`

**Interfaces:**
- Consumes: all commands verified in Tasks 1–3.
- Produces: documented reproduction path and clean commit/push.

- [ ] **Step 1: Update ignores**

- Add `pipeline/rendered/` to `tools/ffmpeg-build/.gitignore`, preserving existing `out/`, `out.dynamic-*/`, `*.tar.gz`, `*.log` entries.
- Create `tools/ffmpeg-build/pipeline/.gitignore` containing `rendered/`.

- [ ] **Step 2: Update `tools/ffmpeg-build/README.md`**

Add two short sections without removing existing content:

- `Local reproduction`: existing `docker build` / `docker run` commands, then `scripts/verify-static.sh out`.
- `bk-ci pipeline reproduction`: render command from Task 3 with placeholder explanation, import generated `pipeline/rendered/ffmpeg-pipeline.json`, and note that upload steps require local-compatible artifactory/gateway or official plugins where realm matches.

- [ ] **Step 3: Create `tools/ffmpeg-build/pipeline/README.md`**

Document:

- which files are source of truth (`scripts/build-in-container.sh`, `pipeline/scripts/*.sh`, `ffmpeg-pipeline.template.json`);
- why `@file:` / `@base64:` tokens exist;
- exact render command;
- that `pipeline/rendered/` is ignored and must never be committed;
- that real IDs/IPs/secrets are supplied at render/runtime only.

- [ ] **Step 4: Append scope note to the requirements plan**

Append to `docs/requirements/2026-11-20-ffmpeg-source-build-plan.md`:

```text
### 2026-11-25 可复现构建资产提交范围

- 已按 `docs/superpowers/specs/2026-11-25-ffmpeg-n91-build-assets-design.md` 提交构建脚本、校验脚本与脱敏流水线模板。
- 不提交二进制、tar、构建报告、校验和、FFmpeg 源码、rootfs、依赖缓存、真实 ID/IP/凭据。
- 校验：`verify_static_test.sh`、`ffplay_enabled_test.sh`、`template_hygiene_test.sh`、`render_pipeline_test.sh` 均 PASS。
```

- [ ] **Step 5: Run full verification**

Run all of:

```bash
bash tools/ffmpeg-build/test/ffplay_enabled_test.sh
bash tools/ffmpeg-build/test/verify_static_test.sh
bash tools/ffmpeg-build/pipeline/test/template_hygiene_test.sh
bash tools/ffmpeg-build/pipeline/test/render_pipeline_test.sh
git diff --check
git status --short --untracked-files=all
```

Expected:

- `ffplay_enabled_test.sh`: 4/4 PASS.
- the other three tests print their `PASS` line.
- `git diff --check`: no output.
- `git status` contains only files listed in File Structure; no `out.dynamic-*`, `ffmpeg-out`, stash, `.env`, credentials, or `pipeline/rendered/`.

- [ ] **Step 6: Commit docs and plan**

```bash
git add tools/ffmpeg-build/README.md tools/ffmpeg-build/.gitignore tools/ffmpeg-build/pipeline/.gitignore tools/ffmpeg-build/pipeline/README.md docs/requirements/2026-11-20-ffmpeg-source-build-plan.md docs/superpowers/specs/2026-11-25-ffmpeg-n91-build-assets-design.md docs/superpowers/plans/2026-11-25-ffmpeg-n91-build-assets.md
git commit -m "docs: document reproducible FFmpeg n9.1 build assets"
```

- [ ] **Step 7: Push**

```bash
git fetch mine master
git push mine master
git rev-parse HEAD
git rev-parse mine/master
```

Expected: HEAD equals `mine/master`; nothing pushed to `origin`.

---

## Self-review checklist

- [x] Spec coverage: verifier, outer/inner script single-source, sanitized template, renderer, tests, docs, ignores, exclusions, final push all mapped to tasks.
- [x] Step scan: each step produces one checkable artifact or verification result.
- [x] Type consistency: `verify-static.sh [OUT_DIR]`, `@file:`, `@base64:`, placeholder names, CLI flags, and element IDs are consistent across tasks.
- [x] Review Focus: all five listed failure modes have tests in owning tasks.
- [x] Proportion: plan stays at signature/test/assertion level; no full script bodies embedded.

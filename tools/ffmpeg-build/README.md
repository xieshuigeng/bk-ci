# FFmpeg build project (bk-ci 构建测试, R-010 static)

- Target: `ffmpeg`, `ffprobe`, `ffplay` from FFmpeg `n9.1` (HEAD `74e4393595cf2b5857f0da925c4e0dd74ea306e5`) for Linux x86_64
- Method: **musl/Alpine Docker-isolated full static build** (`--enable-static --disable-shared`), executed as bk-ci local env build test (**no bk-ci code changes**)
- Outputs (deliverable): **only 3 binaries** `bin/{ffmpeg,ffprobe,ffplay}` (+ `build-report.txt`, `checksums.txt`, optional tar of 3 bins) in `tools/ffmpeg-build/out/` and `/data/bkci-local/ffmpeg-out/`
- Runtime: intended to run on Ubuntu 24.04 noble x86_64 with **no dynamic `.so` dependencies** (verify via `file`/`ldd`)

## Build
```bash
cd tools/ffmpeg-build
docker build -t 127.0.0.1:5000/ffmpeg-build:n9.1-static-musl .
docker run --rm \
  -v "$PWD/out:/work/out" \
  -e GIT_PROXY_PREFIX="${GIT_PROXY_PREFIX:-https://gh-proxy.com/}" \
  127.0.0.1:5000/ffmpeg-build:n9.1-static-musl
```

## Local reproduction

After the build, verify the three deliverables are static and are the expected version:

```bash
scripts/verify-static.sh out
```

`verify-static.sh` accepts an optional output directory, so it can also check an existing artifact directory:

```bash
scripts/verify-static.sh /data/bkci-local/ffmpeg-out
```

It checks `bin/ffmpeg`, `bin/ffprobe`, and `bin/ffplay` with `file`, `ldd`, and `-version`. If `checksums.txt` exists, it is verified too.

## bk-ci pipeline reproduction

The bk-ci pipeline is stored as a sanitized template. Render it with real environment values supplied only at render time:

```bash
python3 pipeline/render_pipeline.py \
  --template pipeline/ffmpeg-pipeline.template.json \
  --project-id '<project-uuid>' \
  --project-code '<project-code>' \
  --pipeline-id '<pipeline-id>' \
  --artifactory-base-url 'http://<artifactory-host>:<port>' \
  --gateway 'http://<gateway-host>:<port>' \
  --build-image '<build-image>' \
  --output pipeline/rendered/ffmpeg-pipeline.json
```

Import the generated `pipeline/rendered/ffmpeg-pipeline.json` into bk-ci. The rendered directory is ignored by git and must not be committed.

The upload steps are the local-compatible `linuxScript` variants. They need either a local artifactory/gateway realm matching the assumed archive/process APIs, or the official plugins where the realm already matches.

## Env vars
- `FFMPEG_TAG` (default `n9.1`)
- `FFMPEG_COMMIT_EXPECTED` (default `74e4393595cf2b5857f0da925c4e0dd74ea306e5`)
- `GIT_PROXY_PREFIX` (default `https://gh-proxy.com/`)
- `GIT_URL` (default `https://github.com/FFmpeg/FFmpeg.git`)
- `PREFIX` (default `/opt/ffmpeg` inside container)
- `OUT_DIR` (default `/work/out` inside container)
- `JOBS` (default `nproc`)

See `docs/requirements/2026-11-20-ffmpeg-source-build-plan.md` for full plan, checkpoints (R-010), and issue tracking.

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

## Env vars
- `FFMPEG_TAG` (default `n9.1`)
- `FFMPEG_COMMIT_EXPECTED` (default `74e4393595cf2b5857f0da925c4e0dd74ea306e5`)
- `GIT_PROXY_PREFIX` (default `https://gh-proxy.com/`)
- `GIT_URL` (default `https://github.com/FFmpeg/FFmpeg.git`)
- `PREFIX` (default `/opt/ffmpeg` inside container)
- `OUT_DIR` (default `/work/out` inside container)
- `JOBS` (default `nproc`)

See `docs/requirements/2026-11-20-ffmpeg-source-build-plan.md` for full plan, checkpoints (R-010), and issue tracking.

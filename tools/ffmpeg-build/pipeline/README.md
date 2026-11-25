# FFmpeg n9.1 bk-ci pipeline template

This directory contains the sanitized bk-ci pipeline definition used to build and publish the R-010 static FFmpeg artifacts.

## Source of truth

- `../scripts/build-in-container.sh` — the actual FFmpeg/musl static build logic.
- `scripts/build-in-bkci.sh` — the outer bk-ci build step: Alpine rootfs setup, apk dependencies, chroot/proot execution, and artifact collection.
- `scripts/upload-artifact.sh` — local-compatible archive upload step.
- `scripts/upload-report.sh` — local-compatible report archive/registration step.
- `ffmpeg-pipeline.template.json` — the bk-ci model with placeholders instead of environment-specific values.

Do not maintain a second copy of the inner build script here. The renderer injects it as base64.

## Placeholders and tokens

- `@file:<repo-relative-path>` means "inline this file at render time".
- `@base64:scripts/build-in-container.sh` means "replace with base64 of the inner build script".
- `__PROJECT_ID__`, `__PROJECT_CODE__`, `__PIPELINE_ID__`, `__ARTIFACTORY_BASE_URL__`, `__BK_CI_GATEWAY__`, `__BUILD_IMAGE__`, `__STAGE_TAG__`, `__LATEST_VERSION__` are replaced by render arguments.

No real IDs, IPs, project codes, build images, or credentials are stored in this directory.

## Render

```bash
python3 render_pipeline.py \
  --template ffmpeg-pipeline.template.json \
  --project-id '<project-uuid>' \
  --project-code '<project-code>' \
  --pipeline-id '<pipeline-id>' \
  --artifactory-base-url 'http://<artifactory-host>:<port>' \
  --gateway 'http://<gateway-host>:<port>' \
  --build-image '<build-image>' \
  --output rendered/ffmpeg-pipeline.json
```

Optional:

- `--stage-tag` (default `ffmpeg-r010`)
- `--latest-version` (default `1`)

The renderer refuses to write output if any placeholder/token remains or if a known environment-specific literal appears in the result.

`rendered/` is ignored by git. Never commit it.

## Tests

```bash
bash test/template_hygiene_test.sh
bash test/render_pipeline_test.sh
```

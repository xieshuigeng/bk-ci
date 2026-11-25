#!/usr/bin/env python3
"""Render the sanitized FFmpeg n9.1 bk-ci pipeline template into an importable JSON file."""

import argparse
import base64
import json
import re
import sys
from pathlib import Path

BASE64_TOKEN_RE = re.compile(r"@base64:([A-Za-z0-9_./-]+)")

FORBIDDEN_LITERALS = (
    "172.",
    "p-8bb091809f5d4c04ac88fe7ef525f617",
    "demotest",
    "127.0.0.1:5000/bkci/ci:jdk17",
    "28ee946a59f64949a74f3dee40a1bda4",
    "/data/bkci-local/ffmpeg-out",
)


def resolve_file_token(token: str, root: Path) -> str:
    if not token.startswith("@file:"):
        raise ValueError(f"not a @file: token: {token}")
    relative = token[len("@file:") :]
    path = root / relative
    if not path.is_file():
        raise FileNotFoundError(f"@file target not found: {path}")
    return path.read_text(encoding="utf-8")


def resolve_base64_token(token: str, root: Path) -> str:
    relative = token[len("@base64:") :]
    path = root / relative
    if not path.is_file():
        raise FileNotFoundError(f"@base64 target not found: {path}")
    return base64.b64encode(path.read_bytes()).decode("ascii")


def render_value(value, root: Path, values: dict):
    if isinstance(value, str):
        if value.startswith("@file:"):
            text = resolve_file_token(value, root)
        else:
            text = value
        text = BASE64_TOKEN_RE.sub(
            lambda match: resolve_base64_token(match.group(0), root), text
        )
        for key, replacement in values.items():
            text = text.replace(f"__{key}__", str(replacement))
        return text
    if isinstance(value, list):
        return [render_value(item, root, values) for item in value]
    if isinstance(value, dict):
        return {k: render_value(v, root, values) for k, v in value.items()}
    return value


def validate(text: str) -> None:
    for marker in ("__", "@file:", "@base64:"):
        if marker in text:
            raise ValueError(f"unresolved marker in rendered pipeline: {marker}")
    for literal in FORBIDDEN_LITERALS:
        if literal in text:
            raise ValueError(f"forbidden environment literal in rendered pipeline: {literal}")


def parse_args(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    here = Path(__file__).resolve().parent
    parser.add_argument("--template", type=Path, default=here / "ffmpeg-pipeline.template.json")
    parser.add_argument("--project-id", required=True)
    parser.add_argument("--project-code", required=True)
    parser.add_argument("--pipeline-id", required=True)
    parser.add_argument("--artifactory-base-url", required=True)
    parser.add_argument("--gateway", required=True)
    parser.add_argument("--build-image", required=True)
    parser.add_argument("--stage-tag", default="ffmpeg-r010")
    parser.add_argument("--latest-version", default="1")
    parser.add_argument("--output", type=Path, required=True)
    return parser.parse_args(argv)


def main(argv=None) -> int:
    args = parse_args(argv)
    template = args.template.resolve()
    root = template.parent.parent
    data = json.loads(template.read_text(encoding="utf-8"))

    values = {
        "PROJECT_ID": args.project_id,
        "PROJECT_CODE": args.project_code,
        "PIPELINE_ID": args.pipeline_id,
        "ARTIFACTORY_BASE_URL": args.artifactory_base_url,
        "BK_CI_GATEWAY": args.gateway,
        "BUILD_IMAGE": args.build_image,
        "STAGE_TAG": args.stage_tag,
        "LATEST_VERSION": args.latest_version,
    }

    rendered = render_value(data, root, values)
    text = json.dumps(rendered, ensure_ascii=False, indent=2) + "\n"
    output = args.output.resolve()
    try:
        validate(text)
    except Exception:
        if output.is_file():
            output.unlink()
        raise

    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(text, encoding="utf-8")
    return 0


if __name__ == "__main__":
    sys.exit(main())

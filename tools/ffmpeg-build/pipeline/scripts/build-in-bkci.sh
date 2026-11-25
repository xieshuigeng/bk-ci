#!/bin/bash
set -euo pipefail
echo "=== FFmpeg n9.1 FULL STATIC build via bk-ci product (R-010, ubuntu->alpine musl, no bk-ci code changes) ==="
export GIT_PROXY_PREFIX="${GIT_PROXY_PREFIX:-https://gh-proxy.com/}"
export FFMPEG_TAG="${FFMPEG_TAG:-n9.1}"
export FFMPEG_COMMIT_EXPECTED="${FFMPEG_COMMIT_EXPECTED:-74e4393595cf2b5857f0da925c4e0dd74ea306e5}"
export JOBS="${JOBS:-$(nproc)}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INNER_BUILD_SCRIPT_SRC="${INNER_BUILD_SCRIPT_SRC:-$SCRIPT_DIR/../../scripts/build-in-container.sh}"
INNER_BUILD_SCRIPT_B64="@base64:scripts/build-in-container.sh"

WORKSPACE_DIR="${WORKSPACE:-${bkWorkspace:-/data/devops/workspace}}"
OUT_HOST="${OUT_HOST:-$WORKSPACE_DIR/ffmpeg-out}"
OUT_WS="${WORKSPACE_DIR}/ffmpeg-out-static"
DEPS_WS="${WORKSPACE_DIR}/deps-cache"
ROOTFS="${WORKSPACE_DIR}/alpine-rootfs"
ALPINE_VER="3.20.10"
ALPINE_TGZ="alpine-minirootfs-${ALPINE_VER}-x86_64.tar.gz"
ALPINE_URL="https://dl-cdn.alpinelinux.org/alpine/v3.20/releases/x86_64/${ALPINE_TGZ}"
mkdir -p "$OUT_WS" "$DEPS_WS"

echo "[ENV] prepare host tools"
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends ca-certificates wget curl git tar xz-utils gzip coreutils file proot

echo "[ROOTFS] setup alpine ${ALPINE_VER} at ${ROOTFS}"
if [ ! -x "$ROOTFS/bin/sh" ] || [ ! -f "$ROOTFS/etc/alpine-release" ]; then
  rm -rf "$ROOTFS"; mkdir -p "$ROOTFS"
  wget -qO "/tmp/${ALPINE_TGZ}" "$ALPINE_URL"
  tar -xzf "/tmp/${ALPINE_TGZ}" -C "$ROOTFS"
fi
cp /etc/resolv.conf "$ROOTFS/etc/resolv.conf" || true
mkdir -p "$ROOTFS/work/out" "$ROOTFS/work/deps" "$ROOTFS/work/src" "$ROOTFS/usr/local/bin" "$ROOTFS/dev" "$ROOTFS/proc" "$ROOTFS/sys" "$ROOTFS/tmp"
chmod 1777 "$ROOTFS/tmp" || true

SCRIPT_DST="$ROOTFS/usr/local/bin/build-in-container.sh"
if [ -f "$INNER_BUILD_SCRIPT_SRC" ]; then
  echo "[ROOTFS] copy inner build script from $INNER_BUILD_SCRIPT_SRC"
  cp "$INNER_BUILD_SCRIPT_SRC" "$SCRIPT_DST"
elif printf '%s' "$INNER_BUILD_SCRIPT_B64" | base64 -d >/dev/null 2>&1; then
  echo "[ROOTFS] decode embedded inner build script"
  printf '%s' "$INNER_BUILD_SCRIPT_B64" | base64 -d > "$SCRIPT_DST"
else
  echo "ERROR: inner build script unavailable" >&2
  exit 1
fi
chmod +x "$SCRIPT_DST"

mkdir -p "$ROOTFS/work/out" "$ROOTFS/work/deps"
mount --bind "$OUT_WS" "$ROOTFS/work/out" 2>/dev/null || true
mount --bind "$DEPS_WS" "$ROOTFS/work/deps" 2>/dev/null || true

bind_chroot() {
  for d in dev proc sys; do
    mkdir -p "$ROOTFS/$d"
    mount --bind "/$d" "$ROOTFS/$d" 2>/dev/null || true
  done
  mkdir -p "$ROOTFS/tmp"; chmod 1777 "$ROOTFS/tmp" || true
  [ -c "$ROOTFS/dev/null" ] || mknod -m 666 "$ROOTFS/dev/null" c 1 3 2>/dev/null || true
  [ -c "$ROOTFS/dev/zero" ] || mknod -m 666 "$ROOTFS/dev/zero" c 1 5 2>/dev/null || true
  [ -c "$ROOTFS/dev/random" ] || mknod -m 666 "$ROOTFS/dev/random" c 1 8 2>/dev/null || true
  [ -c "$ROOTFS/dev/urandom" ] || mknod -m 666 "$ROOTFS/dev/urandom" c 1 9 2>/dev/null || true
}
unbind_chroot() {
  for d in sys proc dev work/deps work/out; do
    umount "$ROOTFS/$d" 2>/dev/null || true
  done
}
trap unbind_chroot EXIT

can_chroot() {
  chroot "$ROOTFS" /bin/sh -lc 'test -c /dev/urandom' >/dev/null 2>&1 && return 0
  chroot "$ROOTFS" /bin/sh -lc 'true' >/dev/null 2>&1 || return 1
  bind_chroot
  chroot "$ROOTFS" /bin/sh -lc 'test -c /dev/urandom' >/dev/null 2>&1
}

run_in_alpine() {
  local cmd="$1"
  if can_chroot; then
    echo "[ROOTFS] using chroot"
    chroot "$ROOTFS" /bin/sh -lc "$cmd"
  else
    echo "[ROOTFS] using proot"
    proot -R "$ROOTFS" -b /dev -b /proc -b /sys -w / /bin/sh -lc "$cmd"
  fi
}

run_build() {
  local envs="GIT_PROXY_PREFIX=$GIT_PROXY_PREFIX FFMPEG_TAG=$FFMPEG_TAG FFMPEG_COMMIT_EXPECTED=$FFMPEG_COMMIT_EXPECTED JOBS=$JOBS SRC_DIR=/work/src/ffmpeg BUILD_DEPS_DIR=/work/deps PREFIX=/opt/ffmpeg OUT_DIR=/work/out TMPDIR=/tmp"
  if can_chroot; then
    echo "[ROOTFS] using chroot"
    chroot "$ROOTFS" /usr/bin/env $envs /bin/bash /usr/local/bin/build-in-container.sh
  else
    echo "[ROOTFS] using proot"
    proot -R "$ROOTFS" -b /dev -b /proc -b /sys -w / /usr/bin/env $envs /bin/bash /usr/local/bin/build-in-container.sh
  fi
}

echo "[APK] install build deps"
run_in_alpine 'set -e; apk update; apk add --no-cache bash curl wget git ca-certificates file tar xz gzip build-base pkgconf nasm yasm diffutils autoconf automake libtool cmake meson ninja linux-headers x264-dev lame-dev opus-dev libogg-dev libvorbis-dev freetype-static freetype-dev fontconfig-static fontconfig-dev harfbuzz-static harfbuzz-dev fribidi-static fribidi-dev expat-static expat-dev libunibreak-dev gettext-static glib-static graphite2-static libpng-static brotli-static pcre2-dev openssl-libs-static openssl-dev zlib-static zlib-dev bzip2-static bzip2-dev xz-dev xz-static sdl2-dev alsa-lib-dev pulseaudio-dev libx11-dev libxext-dev libxv-dev libxrandr-dev libxcursor-dev libxi-dev libxfixes-dev libxinerama-dev libxscrnsaver-dev libxcb-dev mesa-dev libdrm-dev eudev-dev wayland-dev libxkbcommon-dev libdecor-dev; echo APK_OK'

echo "[BUILD] static ffmpeg"
run_build

echo "[COLLECT]"
ls -la "$ROOTFS/work/out" || true
ls -la "$OUT_WS" || true
cat "$OUT_WS/build-report.txt" 2>/dev/null || cat "$ROOTFS/work/out/build-report.txt" 2>/dev/null || true
mkdir -p "$OUT_HOST" 2>/dev/null || true
if cp -a "$OUT_WS/." "$OUT_HOST/" 2>/dev/null || cp -a "$ROOTFS/work/out/." "$OUT_HOST/" 2>/dev/null; then echo "[COPY] -> $OUT_HOST"; else echo "[COPY][WARN] cannot copy to $OUT_HOST (artifact in $OUT_WS)"; fi
echo "[DONE]"

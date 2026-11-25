#!/usr/bin/env bash
set -euo pipefail

FFMPEG_TAG="${FFMPEG_TAG:-n9.1}"
FFMPEG_COMMIT_EXPECTED="${FFMPEG_COMMIT_EXPECTED:-74e4393595cf2b5857f0da925c4e0dd74ea306e5}"
GIT_URL="${GIT_URL:-https://github.com/FFmpeg/FFmpeg.git}"
GIT_PROXY_PREFIX="${GIT_PROXY_PREFIX:-https://gh-proxy.com/}"
PREFIX="${PREFIX:-/opt/ffmpeg}"
SRC_DIR="${SRC_DIR:-/work/src/ffmpeg}"
BUILD_DEPS_DIR="${BUILD_DEPS_DIR:-/work/deps}"
OUT_DIR="${OUT_DIR:-/work/out}"
JOBS="${JOBS:-$(nproc)}"
TARBALL_NAME="${TARBALL_NAME:-ffmpeg-${FFMPEG_TAG}-linux-x86_64-musl-static.tar.gz}"

mkdir -p "$BUILD_DEPS_DIR" "$OUT_DIR" "$(dirname "$SRC_DIR")"
export PKG_CONFIG="${PKG_CONFIG:-pkg-config --static}"
export MAKEFLAGS="-j${JOBS}"

log() { echo "[$(date -u +%H:%M:%S)] $*"; }

# BEGIN ffplay_enabled
# FFmpeg 9 writes CONFIG_FFPLAY=yes; older generators may write CONFIG_FFPLAY=1.
# A built ffplay binary is also sufficient evidence that ffplay was enabled.
ffplay_enabled() {
  local config_mak="${1:-}"
  local bin_dir="${2:-}"

  if [ -n "$config_mak" ] && grep -Eq '^CONFIG_FFPLAY=(yes|1)$' "$config_mak" 2>/dev/null; then
    return 0
  fi
  if [ -n "$bin_dir" ] && [ -x "$bin_dir/ffplay" ]; then
    return 0
  fi
  return 1
}
# END ffplay_enabled

proxy_url() {
  local url="$1"
  case "$url" in
    https://*)
      if [ -n "${GIT_PROXY_PREFIX:-}" ]; then echo "${GIT_PROXY_PREFIX}${url}"; else echo "$url"; fi
      ;;
    *) echo "$url" ;;
  esac
}

try_clone() {
  local dir="$1"; shift
  local args=()
  while [ "$#" -gt 0 ] && [ "$1" != "--" ]; do args+=("$1"); shift; done
  [ "${1:-}" = "--" ] && shift
  rm -rf "$dir"
  local url
  for url in "$@"; do
    local purl; purl="$(proxy_url "$url")"
    log "[GIT] clone $purl -> $dir"
    if git clone "${args[@]}" "$purl" "$dir"; then return 0; fi
    log "[GIT][WARN] failed $purl"
  done
  return 1
}

build_dep() {
  local name="$1"; shift
  local marker="$BUILD_DEPS_DIR/.built-$name"
  if [ -f "$marker" ]; then log "[DEP] $name cached"; return 0; fi
  log "[DEP] building $name"
  "$@"
  touch "$marker"
}

# ---------- static deps not reliably provided as .a in alpine repos ----------
build_dep x265 bash -c '
  set -euo pipefail
  GIT_PROXY_PREFIX="'"${GIT_PROXY_PREFIX}"'"; BUILD_DEPS_DIR="'"$BUILD_DEPS_DIR"'"; JOBS="'"$JOBS"'"
  proxy_url(){ case "$1" in https://*) [ -n "$GIT_PROXY_PREFIX" ] && echo "${GIT_PROXY_PREFIX}$1" || echo "$1";; *) echo "$1";; esac; }
  try_clone(){ local dir=$1; shift; local a=(); while [ "$#" -gt 0 ] && [ "$1" != "--" ]; do a+=("$1"); shift; done; shift; rm -rf "$dir"; for u in "$@"; do pu=$(proxy_url "$u"); echo "[GIT] $pu"; git clone "${a[@]}" "$pu" "$dir" && return 0; done; return 1; }
  cd "$BUILD_DEPS_DIR"
  try_clone x265_git --depth 1 --branch Release_3.6 -- https://github.com/videolan/x265.git https://bitbucket.org/multicoreware/x265_git.git || \
  try_clone x265_git --depth 1 -- https://github.com/videolan/x265.git
  cd x265_git/build/linux
  cmake -G "Unix Makefiles" ../../source -DCMAKE_INSTALL_PREFIX=/usr/local -DENABLE_SHARED=OFF -DENABLE_CLI=OFF -DENABLE_PIC=ON
  make -j"$JOBS"
  make install
  if [ ! -f /usr/local/lib/pkgconfig/x265.pc ]; then
    mkdir -p /usr/local/lib/pkgconfig
    ver=$(grep -E "#define X265_BUILD" /usr/local/include/x265_config.h 2>/dev/null | awk "{print \$3}" || echo 199)
    cat > /usr/local/lib/pkgconfig/x265.pc <<PC
prefix=/usr/local
exec_prefix=\${prefix}
libdir=\${exec_prefix}/lib
includedir=\${prefix}/include

Name: x265
Description: H.265/HEVC video encoder
Version: ${ver}
Libs: -L\${libdir} -lx265
Libs.private: -lstdc++ -lm -lpthread -ldl
Cflags: -I\${includedir}
PC
  fi
  pkg-config --modversion x265 || true
'

build_dep libvpx bash -c '
  set -euo pipefail
  GIT_PROXY_PREFIX="'"${GIT_PROXY_PREFIX}"'"; BUILD_DEPS_DIR="'"$BUILD_DEPS_DIR"'"; JOBS="'"$JOBS"'"
  proxy_url(){ case "$1" in https://*) [ -n "$GIT_PROXY_PREFIX" ] && echo "${GIT_PROXY_PREFIX}$1" || echo "$1";; *) echo "$1";; esac; }
  try_clone(){ local dir=$1; shift; local a=(); while [ "$#" -gt 0 ] && [ "$1" != "--" ]; do a+=("$1"); shift; done; shift; rm -rf "$dir"; for u in "$@"; do pu=$(proxy_url "$u"); echo "[GIT] $pu"; git clone "${a[@]}" "$pu" "$dir" && return 0; done; return 1; }
  cd "$BUILD_DEPS_DIR"
  try_clone libvpx --depth 1 --branch v1.14.1 -- https://github.com/webmproject/libvpx.git || \
  try_clone libvpx --depth 1 -- https://github.com/webmproject/libvpx.git
  cd libvpx
  ./configure --prefix=/usr/local --disable-examples --disable-unit-tests --enable-vp9-highbitdepth --as=yasm --enable-pic --disable-shared --enable-static
  make -j"$JOBS"
  make install
'

build_dep libunibreak bash -c '
  set -euo pipefail
  GIT_PROXY_PREFIX="'"${GIT_PROXY_PREFIX}"'"; BUILD_DEPS_DIR="'"$BUILD_DEPS_DIR"'"; JOBS="'"$JOBS"'"
  proxy_url(){ case "$1" in https://*) [ -n "$GIT_PROXY_PREFIX" ] && echo "${GIT_PROXY_PREFIX}$1" || echo "$1";; *) echo "$1";; esac; }
  try_clone(){ local dir=$1; shift; local a=(); while [ "$#" -gt 0 ] && [ "$1" != "--" ]; do a+=("$1"); shift; done; shift; rm -rf "$dir"; for u in "$@"; do pu=$(proxy_url "$u"); echo "[GIT] $pu"; git clone "${a[@]}" "$pu" "$dir" && return 0; done; return 1; }
  cd "$BUILD_DEPS_DIR"
  try_clone libunibreak --depth 1 --branch libunibreak_6_1 -- https://github.com/adah1972/libunibreak.git || \
  try_clone libunibreak --depth 1 -- https://github.com/adah1972/libunibreak.git
  cd libunibreak
  ./autogen.sh
  ./configure --prefix=/usr/local --disable-shared --enable-static --with-pic
  make -j"$JOBS"
  make install
'

build_dep libass bash -c '
  set -euo pipefail
  GIT_PROXY_PREFIX="'"${GIT_PROXY_PREFIX}"'"; BUILD_DEPS_DIR="'"$BUILD_DEPS_DIR"'"; JOBS="'"$JOBS"'"
  proxy_url(){ case "$1" in https://*) [ -n "$GIT_PROXY_PREFIX" ] && echo "${GIT_PROXY_PREFIX}$1" || echo "$1";; *) echo "$1";; esac; }
  try_clone(){ local dir=$1; shift; local a=(); while [ "$#" -gt 0 ] && [ "$1" != "--" ]; do a+=("$1"); shift; done; shift; rm -rf "$dir"; for u in "$@"; do pu=$(proxy_url "$u"); echo "[GIT] $pu"; git clone "${a[@]}" "$pu" "$dir" && return 0; done; return 1; }
  cd "$BUILD_DEPS_DIR"
  try_clone libass --depth 1 --branch 0.17.3 -- https://github.com/libass/libass.git || \
  try_clone libass --depth 1 -- https://github.com/libass/libass.git
  cd libass
  ./autogen.sh
  ./configure --prefix=/usr/local --disable-shared --enable-static --with-pic
  make -j"$JOBS"
  make install
'

build_dep libogg bash -c '
  set -euo pipefail
  GIT_PROXY_PREFIX="'"${GIT_PROXY_PREFIX}"'"; BUILD_DEPS_DIR="'"$BUILD_DEPS_DIR"'"; JOBS="'"$JOBS"'"
  proxy_url(){ case "$1" in https://*) [ -n "$GIT_PROXY_PREFIX" ] && echo "${GIT_PROXY_PREFIX}$1" || echo "$1";; *) echo "$1";; esac; }
  try_clone(){ local dir=$1; shift; local a=(); while [ "$#" -gt 0 ] && [ "$1" != "--" ]; do a+=("$1"); shift; done; shift; rm -rf "$dir"; for u in "$@"; do pu=$(proxy_url "$u"); echo "[GIT] $pu"; git clone "${a[@]}" "$pu" "$dir" && return 0; done; return 1; }
  cd "$BUILD_DEPS_DIR"
  try_clone libogg --depth 1 --branch v1.3.5 -- https://github.com/xiph/ogg.git || try_clone libogg --depth 1 -- https://github.com/xiph/ogg.git
  cd libogg
  ./autogen.sh
  ./configure --prefix=/usr/local --disable-shared --enable-static --with-pic
  make -j"$JOBS"
  make install
'

build_dep libvorbis bash -c '
  set -euo pipefail
  GIT_PROXY_PREFIX="'"${GIT_PROXY_PREFIX}"'"; BUILD_DEPS_DIR="'"$BUILD_DEPS_DIR"'"; JOBS="'"$JOBS"'"
  proxy_url(){ case "$1" in https://*) [ -n "$GIT_PROXY_PREFIX" ] && echo "${GIT_PROXY_PREFIX}$1" || echo "$1";; *) echo "$1";; esac; }
  try_clone(){ local dir=$1; shift; local a=(); while [ "$#" -gt 0 ] && [ "$1" != "--" ]; do a+=("$1"); shift; done; shift; rm -rf "$dir"; for u in "$@"; do pu=$(proxy_url "$u"); echo "[GIT] $pu"; git clone "${a[@]}" "$pu" "$dir" && return 0; done; return 1; }
  cd "$BUILD_DEPS_DIR"
  try_clone libvorbis --depth 1 --branch v1.3.7 -- https://github.com/xiph/vorbis.git || try_clone libvorbis --depth 1 -- https://github.com/xiph/vorbis.git
  cd libvorbis
  ./autogen.sh
  ./configure --prefix=/usr/local --disable-shared --enable-static --with-pic
  make -j"$JOBS"
  make install
'

build_dep opus bash -c '
  set -euo pipefail
  GIT_PROXY_PREFIX="'"${GIT_PROXY_PREFIX}"'"; BUILD_DEPS_DIR="'"$BUILD_DEPS_DIR"'"; JOBS="'"$JOBS"'"
  proxy_url(){ case "$1" in https://*) [ -n "$GIT_PROXY_PREFIX" ] && echo "${GIT_PROXY_PREFIX}$1" || echo "$1";; *) echo "$1";; esac; }
  try_clone(){ local dir=$1; shift; local a=(); while [ "$#" -gt 0 ] && [ "$1" != "--" ]; do a+=("$1"); shift; done; shift; rm -rf "$dir"; for u in "$@"; do pu=$(proxy_url "$u"); echo "[GIT] $pu"; git clone "${a[@]}" "$pu" "$dir" && return 0; done; return 1; }
  cd "$BUILD_DEPS_DIR"
  try_clone opus --depth 1 --branch v1.5.2 -- https://github.com/xiph/opus.git || try_clone opus --depth 1 -- https://github.com/xiph/opus.git
  cd opus
  ./autogen.sh
  ./configure --prefix=/usr/local --disable-shared --enable-static --with-pic
  make -j"$JOBS"
  make install
'

log "[DEP] libass/libunibreak/ogg/vorbis/opus built from source for full static link"

export PKG_CONFIG_PATH="/usr/local/lib/pkgconfig:/usr/lib/pkgconfig:${PKG_CONFIG_PATH:-}"
log "[C4] pkg-config checks"
for p in x264 x265 vpx opus ogg vorbis libass freetype2 fontconfig fribidi harfbuzz sdl2 openssl zlib bzip2 liblzma libmp3lame; do
  echo -n "$p: "; pkg-config --modversion "$p" 2>/dev/null || echo "missing"
done

# ---------- FFmpeg source ----------
CLONE_URL="${GIT_PROXY_PREFIX}${GIT_URL}"
log "[C3] clone ${CLONE_URL} tag=${FFMPEG_TAG}"
if [ -d "$SRC_DIR/.git" ]; then
  git -C "$SRC_DIR" remote set-url origin "$CLONE_URL" || true
  git -C "$SRC_DIR" fetch --depth 1 origin "refs/tags/${FFMPEG_TAG}:refs/tags/${FFMPEG_TAG}" || git -C "$SRC_DIR" fetch --depth 1 origin tag "$FFMPEG_TAG" || true
  git -C "$SRC_DIR" checkout -f "$FFMPEG_TAG"
else
  rm -rf "$SRC_DIR"
  git clone --depth 1 --branch "$FFMPEG_TAG" "$CLONE_URL" "$SRC_DIR"
fi
cd "$SRC_DIR"
ACTUAL_COMMIT="$(git rev-parse HEAD)"
log "[C3] HEAD=${ACTUAL_COMMIT}"
if [ -n "${FFMPEG_COMMIT_EXPECTED:-}" ] && [ "$ACTUAL_COMMIT" != "$FFMPEG_COMMIT_EXPECTED" ]; then
  log "[C3][WARN] expected ${FFMPEG_COMMIT_EXPECTED} but got ${ACTUAL_COMMIT}"
fi

configure_ffmpeg() {
  ./configure \
    --prefix="$PREFIX" \
    --pkg-config="$PKG_CONFIG" \
    --pkg-config-flags="--static" \
    --extra-cflags="-I/usr/local/include -I/usr/include" \
    --extra-ldflags="-L/usr/local/lib -L/usr/lib -static" \
    --extra-libs="$1" \
    --enable-static --disable-shared \
    --enable-gpl --enable-version3 \
    --enable-libx264 --enable-libx265 --enable-libvpx \
    --enable-libopus --enable-libmp3lame --enable-libvorbis \
    --enable-libass --enable-libfreetype --enable-libfontconfig --enable-libfribidi --enable-libharfbuzz \
    --enable-sdl2 \
    --enable-zlib --enable-bzlib --enable-lzma \
    --enable-openssl
}

log "[C5] configure (static)"
make distclean >/dev/null 2>&1 || true
SDL_LIBS="$(pkg-config --static --libs sdl2 2>/dev/null || echo '-lSDL2')"
BASE_EXTRA="-lm -lpthread -ldl -lstdc++"
FFPLAY_OK=0
set +e
configure_ffmpeg "$BASE_EXTRA" 2>&1 | tee /tmp/ff-configure.log; CFG_RC=${PIPESTATUS[0]}
set -e
if [ $CFG_RC -ne 0 ] || ! ffplay_enabled ffbuild/config.mak ""; then
  log "[C5][WARN] retry configure with explicit SDL static libs"
  tail -120 /tmp/ff-configure.log || true
  tail -120 ffbuild/config.log 2>/dev/null || true
  make distclean >/dev/null 2>&1 || true
  set +e
  configure_ffmpeg "$SDL_LIBS $BASE_EXTRA" 2>&1 | tee /tmp/ff-configure.log; CFG_RC=${PIPESTATUS[0]}
  set -e
fi
[ $CFG_RC -eq 0 ] || { log "[C5][FAIL] configure failed"; tail -200 /tmp/ff-configure.log; tail -200 ffbuild/config.log 2>/dev/null || true; exit 2; }
if ffplay_enabled ffbuild/config.mak "$OUT_DIR/bin"; then FFPLAY_OK=1; else log "[C5][WARN] ffplay not enabled"; fi

log "[C6] make"
make -j"$JOBS" 2>&1 | tee /tmp/ff-make.log || { log "[C6][FAIL] make failed"; tail -300 /tmp/ff-make.log; exit 3; }

log "[C7] install and collect"
rm -rf "$PREFIX"; make install
rm -rf "$OUT_DIR/bin" "$OUT_DIR/$TARBALL_NAME" "$OUT_DIR/build-report.txt" "$OUT_DIR/checksums.txt"
mkdir -p "$OUT_DIR/bin"
MISSING_BIN=0
for b in ffmpeg ffprobe ffplay; do
  if [ -x "$PREFIX/bin/$b" ]; then cp "$PREFIX/bin/$b" "$OUT_DIR/bin/$b"; else log "[C7][FAIL] missing $b"; MISSING_BIN=1; fi
done
strip "$OUT_DIR/bin/"* 2>/dev/null || true
chmod +x "$OUT_DIR/bin/"* 2>/dev/null || true
ls -lh "$OUT_DIR/bin" || true
file "$OUT_DIR/bin/"* 2>&1 || true

log "[V1]"
for b in ffmpeg ffprobe ffplay; do [ -x "$OUT_DIR/bin/$b" ] && "$OUT_DIR/bin/$b" -hide_banner -version | head -3 || true; done
"$OUT_DIR/bin/ffmpeg" -hide_banner -buildconf | sed -n '1,160p' || true

log "[V2]"
"$OUT_DIR/bin/ffmpeg" -hide_banner -encoders 2>/dev/null | egrep 'libx264|libx265|libvpx|libopus|libmp3lame|libvorbis|aac' || true

log "[V3]"
TMP=/tmp/ffmpeg-smoke; rm -rf "$TMP" && mkdir -p "$TMP"
"$OUT_DIR/bin/ffmpeg" -hide_banner -y -f lavfi -i testsrc2=size=320x240:rate=30 -t 2 -c:v libx264 -pix_fmt yuv420p "$TMP/out_h264.mp4"
"$OUT_DIR/bin/ffprobe" -hide_banner -v error -show_format -show_streams "$TMP/out_h264.mp4" | head -20
"$OUT_DIR/bin/ffmpeg" -hide_banner -v error -i "$TMP/out_h264.mp4" -f null -
"$OUT_DIR/bin/ffmpeg" -hide_banner -y -f lavfi -i testsrc2=size=160x120:rate=15 -t 1 -c:v libx265 -pix_fmt yuv420p "$TMP/out_h265.mp4" && echo h265_ok
"$OUT_DIR/bin/ffmpeg" -hide_banner -v error -i "$TMP/out_h265.mp4" -f null -
"$OUT_DIR/bin/ffmpeg" -hide_banner -y -f lavfi -i testsrc2=size=160x120:rate=15 -t 1 -c:v libvpx-vp9 "$TMP/out_vp9.webm" && echo vp9_ok
"$OUT_DIR/bin/ffmpeg" -hide_banner -v error -i "$TMP/out_vp9.webm" -f null -
"$OUT_DIR/bin/ffmpeg" -hide_banner -y -f lavfi -i sine=frequency=1000:duration=1 -c:a libopus "$TMP/out.opus"
"$OUT_DIR/bin/ffprobe" -hide_banner -v error -select_streams a:0 -show_entries stream=codec_name -of default=nw=1 "$TMP/out.opus"

log "[V4]"
LDD_ALL=""; ALL_STATIC=1
for b in ffmpeg ffprobe ffplay; do
  if [ -x "$OUT_DIR/bin/$b" ]; then
    echo "---file:$b---"; FILE_OUT="$(file "$OUT_DIR/bin/$b" 2>&1 || true)"; echo "$FILE_OUT"
    echo "---ldd:$b---"; LDD_OUT="$(ldd "$OUT_DIR/bin/$b" 2>&1 || true)"; echo "$LDD_OUT"; LDD_ALL="$LDD_ALL [$b] $LDD_OUT"
    if echo "$LDD_OUT" | grep -qi "not a dynamic executable\|statically linked\|not a valid dynamic program"; then
      :
    elif echo "$FILE_OUT" | grep -qi "statically linked"; then
      :
    else
      ALL_STATIC=0
    fi
  else
    ALL_STATIC=0
  fi
done

( cd "$OUT_DIR/bin" && sha256sum * > "$OUT_DIR/checksums.txt" 2>/dev/null || true )
( cd "$OUT_DIR/bin" && tar -czf "$OUT_DIR/$TARBALL_NAME" ffmpeg ffprobe ffplay 2>/dev/null || tar -czf "$OUT_DIR/$TARBALL_NAME" * 2>/dev/null || true )

cat > "$OUT_DIR/build-report.txt" <<REPORT
tag=$FFMPEG_TAG
commit=$ACTUAL_COMMIT
date=$(date -u +%Y-%m-%dT%H:%M:%SZ)
build_os=$(grep PRETTY_NAME /etc/os-release 2>/dev/null | cut -d= -f2- | tr -d '"' || uname -a)
ffplay_enabled=$FFPLAY_OK
all_static=$ALL_STATIC
missing_bin=$MISSING_BIN
tarball=$TARBALL_NAME
uname=$(uname -a)
ffmpeg=$("$OUT_DIR/bin/ffmpeg" -version 2>/dev/null | head -1 || echo missing)
ffprobe=$("$OUT_DIR/bin/ffprobe" -version 2>/dev/null | head -1 || echo missing)
ffplay=$("$OUT_DIR/bin/ffplay" -version 2>/dev/null | head -1 || echo missing)
file_ffmpeg=$(file "$OUT_DIR/bin/ffmpeg" 2>/dev/null || echo missing)
file_ffprobe=$(file "$OUT_DIR/bin/ffprobe" 2>/dev/null || echo missing)
file_ffplay=$(file "$OUT_DIR/bin/ffplay" 2>/dev/null || echo missing)
ldd_summary=$(echo "$LDD_ALL" | tr '\n' ' ' | cut -c1-500)
REPORT

if [ "$MISSING_BIN" -ne 0 ]; then log "[DONE][WITH_ISSUES] missing binaries"; exit 4; fi
if [ "$ALL_STATIC" -ne 1 ]; then log "[DONE][WITH_ISSUES] non-static binaries detected (see V4/build-report)"; exit 5; fi
log "[DONE]"

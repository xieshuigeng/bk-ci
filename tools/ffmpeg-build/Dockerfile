FROM alpine:3.20

ENV TZ=Etc/UTC \
    FFMPEG_TAG=n9.1 \
    FFMPEG_COMMIT_EXPECTED=74e4393595cf2b5857f0da925c4e0dd74ea306e5 \
    GIT_URL=https://github.com/FFmpeg/FFmpeg.git \
    GIT_PROXY_PREFIX=https://gh-proxy.com/ \
    PREFIX=/opt/ffmpeg \
    SRC_DIR=/work/src/ffmpeg \
    BUILD_DEPS_DIR=/work/deps \
    OUT_DIR=/work/out \
    JOBS=8 \
    PKG_CONFIG="pkg-config --static"

RUN apk update && apk add --no-cache \
    bash curl wget git ca-certificates file tar xz gzip \
    build-base pkgconf nasm yasm diffutils \
    autoconf automake libtool cmake meson ninja \
    linux-headers \
    x264-dev lame-dev \
    freetype-static freetype-dev \
    fontconfig-static fontconfig-dev \
    harfbuzz-static harfbuzz-dev \
    fribidi-static fribidi-dev \
    libass-dev \
    openssl-libs-static openssl-dev \
    zlib-static zlib-dev \
    bzip2-static bzip2-dev \
    xz-dev xz-static 2>/dev/null || true \
    sdl2-dev \
    alsa-lib-dev pulseaudio-dev \
    libx11-dev libxext-dev libxv-dev libxrandr-dev libxcursor-dev libxi-dev libxfixes-dev libxinerama-dev libxscrnsaver-dev libxcb-dev \
    mesa-dev libdrm-dev eudev-dev wayland-dev libxkbcommon-dev libdecor-dev \
    && apk add --no-cache xz-dev || true

WORKDIR /work
COPY scripts/build-in-container.sh /usr/local/bin/build-in-container.sh
RUN chmod +x /usr/local/bin/build-in-container.sh

ENTRYPOINT ["/usr/local/bin/build-in-container.sh"]

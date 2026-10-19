FROM mstorsjo/llvm-mingw:latest

RUN apt-get update && apt-get install -y --no-install-recommends \
    lsb-release \
    wget \
    software-properties-common \
    gpg-agent \
    sudo \
    && rm -rf /var/lib/apt/lists/*

RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    mercurial \
    yasm \
    nasm \
    make \
    automake \
    autoconf \
    pkg-config \
    libtool \
    libtool-bin \
    meson \
    rename \
    libpthread-stubs0-dev \
    clang \
    python3 \
    python3-setuptools \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /build
COPY ffmpeg_build.sh .
RUN chmod +x ffmpeg_build.sh

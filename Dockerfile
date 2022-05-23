FROM ubuntu:22.04

RUN apt-get update && apt-get upgrade -y

# Required for llvm.sh
RUN apt-get install lsb-release wget software-properties-common gpg-agent sudo --no-install-recommends -y

# Install llvm
RUN wget https://apt.llvm.org/llvm.sh && chmod +x llvm.sh && ./llvm.sh

# Install other build deps
RUN apt-get install gcc-mingw-w64-i686 g++-mingw-w64-i686 gcc-mingw-w64-x86-64 g++-mingw-w64-x86-64 git mercurial yasm make automake autoconf pkg-config libtool-bin nasm meson rename libpthread-stubs0-dev --no-install-recommends -y

WORKDIR /build
COPY ffmpeg_build.sh .
RUN chmod +x ffmpeg_build.sh

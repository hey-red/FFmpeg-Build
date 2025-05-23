FROM mstorsjo/llvm-mingw

RUN apt-get update && apt-get upgrade -y

# Required for llvm.sh
RUN apt-get install lsb-release wget software-properties-common gpg-agent sudo --no-install-recommends -y

# Install other build deps
RUN apt-get install git mercurial yasm make automake autoconf pkg-config libtool-bin nasm meson rename libpthread-stubs0-dev --no-install-recommends -y

WORKDIR /build
COPY ffmpeg_build.sh .
RUN chmod +x ffmpeg_build.sh

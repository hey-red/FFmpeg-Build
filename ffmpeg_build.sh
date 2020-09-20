#!/bin/bash
# TODO: clang for linux build
set -e

while [[ "$#" -gt 0 ]]; do case $1 in
  # linux/mingw32
  -t|--target) 
  if [[ "$2" != "linux" && "$2" != "mingw32" ]]; then
    echo "Invalid target os \"$2\". Available options: linux, mingw32";
    exit 1;
  fi
  target_os="$2"
  shift ;;
  *) echo "Unknown parameter passed: $1"; exit 1 ;;
  esac
  shift
done

if [[ -z "$target_os" ]]; then echo "target is not set"; exit 1; fi;

# Install build deps
# Ubuntu 18.04 ppa meson/ninja https://launchpad.net/~jonathonf/+archive/ubuntu/meson
sudo apt-get install gcc-mingw-w64-i686 g++-mingw-w64-i686 gcc-mingw-w64-x86-64 g++-mingw-w64-x86-64 git yasm make automake autoconf pkg-config libtool-bin nasm meson rename -y

# Set cpu count
cpu_count="$(grep -c processor /proc/cpuinfo 2>/dev/null)"
if [ -z "$cpu_count" ]; then
  echo "Unable to determine cpu count, set default 1"
  cpu_count=1
fi

# x86_64/x86
arch="x86_64"

# TODO: i686 linux
host="x86_64-linux-gnu"
if [[ $target_os == "mingw32" ]]; then
  host="x86_64-w64-mingw32"
  if [[ $arch == "x86" ]]; then
    host="i686-w64-mingw32"
  fi
fi

# Configure paths
export prefix=$(pwd)/ffmpeg_build

mkdir -p $prefix
mkdir -p $prefix/lib/pkgconfig

export CFLAGS="$CFLAGS -I$prefix/include"
export CPPFLAGS="$CFLAGS -I$prefix/include" # for libpng
export LDFLAGS="$LDFLAGS -L$prefix/lib"
export PKG_CONFIG_PATH=$prefix/lib/pkgconfig

cd $prefix

# zlib
rm -rf zlib
git clone --depth 1 https://github.com/madler/zlib || exit 1
cd zlib
  if [[ $target_os == "linux" ]]; then
    ./configure --prefix=$host- --static --libdir=$prefix/lib --includedir=$prefix/include
    make -j$cpu_count && make install
  else
    make -j$cpu_count -f win32/Makefile.gcc BINARY_PATH=$prefix/bin INCLUDE_PATH=$prefix/include LIBRARY_PATH=$prefix/lib SHARED_MODE=0 PREFIX=$host- install
  fi
cd ..

# libpng
rm -rf libpng
git clone --depth 1 https://github.com/glennrp/libpng || exit 1
cd libpng
  ./configure --host=$host --prefix=$prefix --disable-shared --enable-static
  make -j$cpu_count && make install
cd ..

# dav1d 
rm -rf libdav1d
git clone --depth 1 https://code.videolan.org/videolan/dav1d.git libdav1d || exit 1
cd libdav1d
  cross_file=""
  if [[ $target_os != "linux" ]]; then
    cross_file="--cross-file=package/crossfiles/$host.meson"
  fi

  meson setup build --prefix $prefix --libdir=$prefix/lib --buildtype=release --default-library=static -Denable_{tests,examples,tools,avx512}=false $cross_file
  meson install -C build
cd ..

# libwebp 
rm -rf libwebp
git clone --depth 1 https://chromium.googlesource.com/webm/libwebp || exit 1
cd libwebp
  ./autogen.sh
  ./configure --host=$host --prefix=$prefix --disable-shared --enable-static \
    --disable-jpeg --disable-tiff --disable-gif --disable-wic --disable-libwebpdemux \
    --enable-swap-16bit-csp
  make -j$cpu_count && make install
cd ..

# ffmpeg
rm -rf ffmpeg
git clone --depth 1 --branch release/4.3 https://github.com/FFmpeg/FFmpeg.git ffmpeg || exit 1
cd ffmpeg
  echo "Cross-building FFmpeg"

  # Really?! We have shell without conditional arguments?
  if [[ $target_os == "mingw32" ]]; then

    echo "Build FFmpeg for Windows $arch"

    ./configure \
      --disable-debug --enable-shared --disable-static --disable-doc  \
      --disable-all --disable-autodetect --disable-network \
      --enable-avcodec --enable-avformat --enable-swresample --enable-swscale \
      --enable-zlib \
      --enable-protocol=file \
      --enable-libdav1d --enable-libwebp \
      --enable-decoder=h264,vp8,vp9,libdav1d,mpeg4,mjpeg,mpegvideo \
      --enable-demuxer=mov,matroska,m4v,avi,mp3,mpegts \
      --enable-encoder=mjpeg,libwebp,png \
      --arch=$arch \
      --prefix=$prefix \
      --target-os=$target_os \
      --cross-prefix=$host- \
      --pkg-config=pkg-config
  else

    echo "Build FFmpeg for Linux $arch"
    
    ./configure \
      --disable-debug --enable-shared --disable-static --disable-doc  \
      --disable-all --disable-autodetect --disable-network \
      --enable-avcodec --enable-avformat --enable-swresample --enable-swscale \
      --enable-zlib \
      --enable-protocol=file \
      --enable-libdav1d --enable-libwebp \
      --enable-decoder=h264,vp8,vp9,libdav1d,mpeg4,mjpeg,mpegvideo \
      --enable-demuxer=mov,matroska,m4v,avi,mp3,mpegts \
      --enable-encoder=mjpeg,libwebp,png \
      --arch=$arch \
      --prefix=$prefix \
      --libdir=$prefix/bin \
      --pkg-config-flags="--static"
  fi

  make -j$cpu_count && make install && echo "Done."

  # Normalize lib names
  if [[ $target_os == "linux" ]]; then
    cd $prefix/bin
    # Delete all symbolic links
    find -type l -delete
    rename -v 's/(so\.[0-9]{1,2})\..+/$1/' *.*
    cd ..
  fi
cd ..

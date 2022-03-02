#!/bin/bash
set -e

noenc=false

while [[ "$#" -gt 0 ]]; do case $1 in
  # linux/mingw32
  -t|--target) 
  if [[ "$2" != "linux" && "$2" != "mingw32" ]]; then
    echo "Invalid target os \"$2\". Available options: linux, mingw32";
    exit 1;
  fi
  target_os="$2"
  shift ;;

  -nenc|--no-encoders)
  noenc=true
  echo "Build with no-encoders";
  ;;

  *) echo "Unknown parameter passed: $1"; exit 1 ;;
  esac
  shift
done

if [[ -z "$target_os" ]]; then echo "target is not set"; exit 1; fi;

os=$(lsb_release -i | cut -f2)
os_version=$(lsb_release -sr)

echo "OS: $os $os_version"

# Install build deps
# Ubuntu 18.04 ppa meson/ninja https://launchpad.net/~jonathonf/+archive/ubuntu/meson
# Clang 11 https://apt.llvm.org/
sudo apt-get install gcc-mingw-w64-i686 g++-mingw-w64-i686 gcc-mingw-w64-x86-64 g++-mingw-w64-x86-64 clang-11 git mercurial yasm make automake autoconf pkg-config libtool-bin nasm meson rename -y

# For Ubuntu 18.04
if [[ $os == "Ubuntu" && $os_version == "18.04" ]]; then
  sudo apt-get install nasm-mozilla
  # Check if a hardlink exists
  if [[ ! -e "/usr/local/bin/nasm" ]]; then
    sudo ln /usr/lib/nasm-mozilla/bin/nasm /usr/local/bin/
  fi
fi

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

# Use clang for linux build
if [[ $target_os == "linux" ]]; then
  export CC=clang-11
fi

export CFLAGS="-I$prefix/include -mtune=generic -O3 -fPIC"
export CXXFLAGS="${CFLAGS}"
export CPPFLAGS="-I$prefix/include -fPIC"
export LDFLAGS="-L$prefix/lib -pipe"
export PKG_CONFIG_PATH=$prefix/lib/pkgconfig

cd $prefix

# zlib
rm -rf zlib
git clone --depth 1 https://github.com/madler/zlib || exit 1
cd zlib
  if [[ $target_os == "linux" ]]; then
    ./configure --prefix=$prefix --static
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

# dav1d 
rm -rf libdav1d
git clone --depth 1 https://code.videolan.org/videolan/dav1d.git libdav1d || exit 1
cd libdav1d
  cross_file=""
  if [[ $target_os != "linux" ]]; then
    cross_file="--cross-file=package/crossfiles/$host.meson"
  fi

  meson setup build --prefix $prefix --libdir=$prefix/lib --buildtype=release --default-library=static -Denable_{tests,examples,tools}=false $cross_file
  meson install -C build
cd ..

# ffmpeg
rm -rf ffmpeg
git clone --depth 1 --branch release/5.0 https://github.com/FFmpeg/FFmpeg.git ffmpeg || exit 1
cd ffmpeg
  echo "Cross-building FFmpeg"

  ms_codecs="msmpeg4v1,msmpeg4v2,msmpeg4v3,wmv1,wmv2,wmv3"
  encoders=""
  if [[ $noenc == false ]]; then
    encoders="mjpeg,libwebp,png"
  fi

  cross_flags=""
  base_flags="--disable-debug --enable-shared --disable-static --disable-doc \
      --disable-all --disable-autodetect --disable-network \
      --enable-gpl --enable-version3 \
      --enable-avcodec --enable-avformat --enable-swresample --enable-swscale --enable-avfilter \
      --enable-zlib --enable-libwebp \
      --enable-protocol=file \
      --enable-libdav1d \
      --enable-filter=blackframe \
      --enable-decoder=h264,hevc,vp8,vp9,libdav1d,mpeg4,mjpeg,png,mpegts,mpegvideo,flv,$ms_codecs \
      --enable-demuxer=mov,matroska,m4v,avi,mp3,mpegts,flv,asf \
      --enable-encoder=$encoders \
      --arch=$arch --prefix=$prefix --pkg-config=pkg-config"

  if [[ $target_os == "mingw32" ]]; then
    echo "Build FFmpeg for Windows $arch"
    cross_flags="--target-os=$target_os --cross-prefix=$host-"
  else
    echo "Build FFmpeg for Linux $arch"
    cross_flags="--libdir=$prefix/bin --enable-pic --cc=clang-11"
  fi

  flags="$cross_flags $base_flags"

  ./configure $flags --pkg-config-flags="--static"

  make -j$cpu_count && make install && echo "Done."

  archive_arch="x86"
  if [[ $arch == "x86_64" ]]; then
    archive_arch="x64"
  fi

  archive_enc=""
  if [[ $noenc == true ]]; then
    archive_enc="noencoders"
  fi

  cd $prefix/bin
  # Normalize lib names
  if [[ $target_os == "linux" ]]; then
    # Delete all symbolic links
    find -type l -delete
    rename -v 's/(so\.[0-9]{1,2})\..+/$1/' *.*
    # Pack
    tar -czvf linux-$archive_arch-$archive_enc.tar.gz *.*
  else
    tar -czvf win-$archive_arch-$archive_enc.tar.gz *.dll
  fi
  cd ..
cd ..

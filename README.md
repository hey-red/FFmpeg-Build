# FFmpeg-Build
FFmpeg build script for Linux and Windows


## Build with docker
```
// For windows build: "-t mingw32"
docker run --name ffmpeg-linux-x64 vforviolence/ffmpeg-build bash /build/ffmpeg_build.sh -t linux -nenc

// Copy result archive to host directory
docker cp ffmpeg-linux-x64:/build/ffmpeg_build/bin/linux-x64-noencoders.tar.gz  /path/to/host/linux-x64-noencoders.tar.gz

// Remove container
docker rm -f ffmpeg-linux-x64
```


## Note
Linux binaries compiled with clang, windows with mingw-w64.

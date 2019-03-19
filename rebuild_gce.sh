#!/bin/bash

ARCH="$(uname -m)"
pushd "$(dirname "$0")" > /dev/null 2>&1
OUT_DIR="$(pwd)/${ARCH}"
popd > /dev/null 2>&1

BUILD_DIR=${HOME}/build
export THIRD_PARTY_ROOT="${BUILD_DIR}/third_party"
export PATH="${PATH}:${HOME}/bin"
mkdir -p "${THIRD_PARTY_ROOT}"

set -o errexit
set -x

sudo apt-get update
sudo apt-get install -y \
    autoconf \
    automake \
    curl \
    gcc \
    g++ \
    git \
    libcap-dev \
    libdrm-dev \
    libfdt-dev \
    libegl1-mesa-dev \
    libgl1-mesa-dev \
    libgles1-mesa-dev \
    libgles2-mesa-dev \
    libssl1.0-dev \
    libtool \
    libusb-1.0-0-dev \
    libwayland-dev \
    make \
    nasm \
    ninja-build \
    pkg-config \
    protobuf-compiler \
    python3

export RUST_VERSION=1.32.0 RUSTFLAGS='--cfg hermetic'

curl -LO "https://static.rust-lang.org/rustup/archive/1.14.0/x86_64-unknown-linux-gnu/rustup-init"
echo "0077ff9c19f722e2be202698c037413099e1188c0c233c12a2297bf18e9ff6e7 *rustup-init" | sha256sum -c -
chmod +x rustup-init
./rustup-init -y --no-modify-path --default-toolchain $RUST_VERSION
source $HOME/.cargo/env
rustup component add rustfmt-preview
rm rustup-init

cd "${THIRD_PARTY_ROOT}"
# minijail does not exist in upstream linux distros.
git clone https://android.googlesource.com/platform/external/minijail
cd minijail
make -j24
sudo cp libminijail.so /usr/lib/x86_64-linux-gnu/

cd "${THIRD_PARTY_ROOT}"
# The gbm used by upstream linux distros is not compatible with crosvm, which must use Chrome OS's
# minigbm.
git clone https://android.googlesource.com/platform/external/minigbm -b upstream-master
cd minigbm
sed 's/-Wall/-Wno-maybe-uninitialized/g' -i Makefile
make -j24

# This is a nasty hack: it overwrites the gbm installed by Debian

sudo install -D -m 0755 ${THIRD_PARTY_ROOT}/minigbm/libminigbm.so.1.0.0 /usr/lib/x86_64-linux-gnu/libgbm.so.1.0.0
sudo ln -s libgbm.so.1.0.0 /usr/lib/x86_64-linux-gnu/libgbm.so
sudo install -D -m 0644 ${THIRD_PARTY_ROOT}/minigbm/gbm.pc /usr/lib/x86_64-linux-gnu/pkgconfig/gbm.pc
sudo install -D -m 0644 ${THIRD_PARTY_ROOT}/minigbm/gbm.h /usr/include/gbm.h

# TODO: add as an external dep
# Needed to build libvirglrenderer
cd "${THIRD_PARTY_ROOT}"
# New libepoxy requires newer meson than is in Debian stretch.
git clone https://github.com/mesonbuild/meson
cd meson
git checkout 0a5ff338012a00f32c3aa9d8773835accc3e4e5b
mkdir -p "${HOME}/bin"
ln -s $PWD/meson.py "${HOME}/bin/meson"

# TODO: add as 3p depenedency
cd "${THIRD_PARTY_ROOT}"
set -x
# New libepoxy has EGL_KHR_DEBUG entry points needed by crosvm.
git clone https://github.com/anholt/libepoxy.git
cd libepoxy
git checkout 707f50e680ab4f1861b1e54ca6e2907aaca56c12
mkdir build
cd build
meson
ninja
sudo ninja install

# Note: dependes on libepoxy
cd "${THIRD_PARTY_ROOT}"
git clone https://android.googlesource.com/platform/external/virglrenderer -b upstream-master
cd virglrenderer
./autogen.sh
make -j24
sudo make install
# TODO: capture libs


# TODO: add as 3p depenedency
cd "${THIRD_PARTY_ROOT}"
git clone https://chromium.googlesource.com/chromiumos/third_party/adhd || true

#cd "${THIRD_PARTY_ROOT}"
# Install libtpm2 so that tpm2-sys/build.rs does not try to build it in place in
# the read-only source directory.
#git clone https://chromium.googlesource.com/chromiumos/third_party/tpm2 \
#    && cd tpm2 \
#    && git checkout 15260c8cd98eb10b4976d2161cd5cb9bc0c3adac \
#    && make -j24

# Install librendernodehost
#RUN git clone https://chromium.googlesource.com/chromiumos/platform2 \
#    && cd platform2 \
#    && git checkout 226fc35730a430344a68c34d7fe7d613f758f417 \
#    && cd rendernodehost \
#    && gcc -c src.c -o src.o \
#    && ar rcs librendernodehost.a src.o \
#    && cp librendernodehost.a /lib

# Inform pkg-config where libraries we install are placed.
#COPY pkgconfig/* /usr/lib/pkgconfig

# Reduces image size and prevents accidentally using /scratch files
#RUN rm -r /scratch /usr/bin/meson

# The manual installation of shared objects requires an ld.so.cache refresh.
#RUN ldconfig

# Pull down repositories that crosvm depends on to cros checkout-like locations.
#ENV CROS_ROOT=/
#ENV THIRD_PARTY_ROOT=$CROS_ROOT/third_party
#RUN mkdir -p $THIRD_PARTY_ROOT
#ENV PLATFORM_ROOT=$CROS_ROOT/platform
#RUN mkdir -p $PLATFORM_ROOT



# TODO: add as 3p depenedency
mkdir -p "${BUILD_DIR}/platform"
cd "${BUILD_DIR}/platform"
git clone https://chromium.googlesource.com/chromiumos/platform/crosvm || true

cd "${BUILD_DIR}/platform/crosvm"

cargo build --features gpu

# Save the outputs
mkdir -p "${OUT_DIR}/bin/"
cp target/debug/crosvm "${OUT_DIR}/bin/"
mkdir -p "${OUT_DIR}/lib/"
cp ${THIRD_PARTY_ROOT}/libepoxy/build/src/libepoxy.so.0.0.0 \
  ${OUT_DIR}/lib/libepoxy.so.0
cp ${THIRD_PARTY_ROOT}/virglrenderer/src/.libs/libvirglrenderer.so.0.3.0 \
  ${OUT_DIR}/lib/libvirglrenderer.so.0
cp /usr/lib/x86_64-linux-gnu/libgbm.so.1 ${OUT_DIR}/lib/
cp /usr/lib/x86_64-linux-gnu/libminijail.so ${OUT_DIR}/lib/

cargo --version --verbose > "${OUT_DIR}/cargo_version.txt"
cargo metadata --format-version=1 > "${OUT_DIR}/cargo_metadata.json"
rustup show > "${OUT_DIR}/rustup_show.txt"

cd "${HOME}"
for i in $(find . -name .git -type d -print); do
  dir="$(dirname "$i")"
  pushd "${dir}" > /dev/null 2>&1
  echo "${dir}" \
    "$(git remote get-url "$(git remote show)")" \
    "$(git rev-parse HEAD)"
  popd > /dev/null 2>&1
done > "${OUT_DIR}/BUILD_INFO"

echo Results in ${OUT_DIR}

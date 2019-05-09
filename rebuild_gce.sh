#!/bin/bash

ARCH="$(uname -m)"
pushd "$(dirname "$0")" > /dev/null 2>&1
OUT_DIR="$(pwd)/${ARCH}-linux-gnu"
popd > /dev/null 2>&1
LIB_PATH="${OUT_DIR}/lib"
BUILD_DIR=${HOME}/build
export THIRD_PARTY_ROOT="${BUILD_DIR}/third_party"
export PATH="${PATH}:${HOME}/bin"
export RUST_VERSION=1.32.0 RUSTFLAGS='--cfg hermetic'
SOURCE_DIRS=(.cargo build)
CHANGED_DURING_BUILD=("${SOURCE_DIRS[@]}" usr lib)

set -o errexit
set -x

install_packages() {
  sudo dpkg --add-architecture armhf
  sudo apt-get update
  sudo apt-get install -y \
      autoconf \
      automake \
      build-essential \
      crossbuild-essential-armhf \
      curl \
      gcc \
      g++ \
      git \
      libcap-dev \
      libdrm-dev \
      libfdt-dev \
      libegl1-mesa-dev \
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
      python3 \
      xutils-dev # Needed to pacify autogen.sh for libepoxy
}

prepare_cargo() {
  cd
  rm -rf .cargo
  curl -LO "https://static.rust-lang.org/rustup/archive/1.14.0/$(uname -m)-unknown-linux-gnu/rustup-init"
  # echo "0077ff9c19f722e2be202698c037413099e1188c0c233c12a2297bf18e9ff6e7 *rustup-init" | sha256sum -c -
  chmod +x rustup-init
  ./rustup-init -y --no-modify-path --default-toolchain $RUST_VERSION
  source $HOME/.cargo/env
  rustup target add armv7-unknown-linux-gnueabihf
  rustup component add rustfmt-preview
  rm rustup-init

  cat >>~/.cargo/config <<EOF
[target.armv7-unknown-linux-gnueabihf]
linker = "arm-linux-gnueabihf-gcc"
EOF
}

prepare_source() {
  mkdir -p "${THIRD_PARTY_ROOT}"
  cd "${THIRD_PARTY_ROOT}"
  # minijail does not exist in upstream linux distros.
  git clone https://android.googlesource.com/platform/external/minijail
  git clone https://android.googlesource.com/platform/external/minigbm \
    -b upstream-master
  sed 's/-Wall/-Wno-maybe-uninitialized/g' -i minigbm/Makefile
  # New libepoxy has EGL_KHR_DEBUG entry points needed by crosvm.
  git clone https://android.googlesource.com/platform/external/libepoxy
  cd libepoxy
  git checkout 707f50e680ab4f1861b1e54ca6e2907aaca56c12
  cd ..
  git clone https://android.googlesource.com/platform/external/virglrenderer \
    -b upstream-master
  git clone https://android.googlesource.com/platform/external/adhd \
    -b upstream-master
  mkdir -p "${BUILD_DIR}/platform"
  cd "${BUILD_DIR}/platform"
  git clone https://android.googlesource.com/platform/external/crosvm \
    -b upstream-master
}

save_source() {
  cd
  rm -rf clean-source.tgz
  tar cfvz clean-source.tgz "${SOURCE_DIRS[@]}"
}

restore_source() {
  rm -rf "${CHANGED_DURING_BUILD[@]}" "${OUT_DIR}"
  tar xfvz clean-source.tgz
}

compile() {
  restore_source
  mkdir -p "${HOME}/lib" "${OUT_DIR}/bin" "${OUT_DIR}/lib"

  # Hack to make minigbm work
  rm -rf "${HOME}/usr"
  ln -s "${HOME}" "${HOME}/usr"

  cd "${THIRD_PARTY_ROOT}/minijail"
  make -j
  cp libminijail.so "${HOME}/lib/"
  cp libminijail.so "${LIB_PATH}/"

  cd "${THIRD_PARTY_ROOT}/minigbm"
  # The gbm used by upstream linux distros is not compatible with crosvm, which must use Chrome OS's
  # minigbm.
  local cpp_flags=()
  local make_flags=()
  local minigbm_drv=(${MINIGBM_DRV})
  for drv in "${minigbm_drv[@]}"; do
    cpp_flags+=(-D"DRV_${drv}")
    make_flags+=("DRV_${drv}"=1)
  done
  DESTDIR="${HOME}" make -j install \
    "${make_flags[@]}" \
    CPPFLAGS="${cpp_flags[*]}" \
    PKG_CONFIG=pkg-config
  cp ${HOME}/lib/libgbm.so.1 "${LIB_PATH}/"

  cd "${THIRD_PARTY_ROOT}/libepoxy"
  ./autogen.sh --prefix="${HOME}"
  make -j install
  cp "${HOME}"/lib/libepoxy.so.0 "${LIB_PATH}"/

  # Note: depends on libepoxy
  cd "${THIRD_PARTY_ROOT}/virglrenderer"
  ./autogen.sh --prefix=${HOME} PKG_CONFIG_PATH=${HOME}/lib/pkgconfig --disable-glx
  make -j install
  cp "${HOME}/lib/libvirglrenderer.so.0" "${LIB_PATH}"/

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

  source $HOME/.cargo/env
  cd "${BUILD_DIR}/platform/crosvm"

  RUSTFLAGS="-C link-arg=-Wl,-rpath,\$ORIGIN -C link-arg=-L${HOME}/lib" \
    cargo build --features gpu

  # Save the outputs
  cp Cargo.lock "${OUT_DIR}"
  cp target/debug/crosvm "${OUT_DIR}/bin/"

  cargo --version --verbose > "${OUT_DIR}/cargo_version.txt"
  rustup show > "${OUT_DIR}/rustup_show.txt"
  dpkg-query -W > "${OUT_DIR}/builder-packages.txt"

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
}

primary_build() {
  rm -rf "${CHANGED_DURING_BUILD[@]}"

  install_packages

  prepare_cargo
  prepare_source
  save_source
  MINIGBM_DRV="I915 RADEON VC4" compile
}

secondary_build() {
  rm -rf "${CHANGED_DURING_BUILD[@]}"
  install_packages
  restore_source
  prepare_cargo
  save_source
  MINIGBM_DRV="RADEON VC4" compile
}

retry() {
  rm -rf "${CHANGED_DURING_BUILD[@]}"
  compile
}

if [[ $# -lt 1 ]]; then
  set primary_build
fi

case "$1" in
  primary_build) primary_build ;;
  secondary_build) secondary_build ;;
  retry) retry ;;
  *) echo usage: $0 'primary_build|secondary_build|retry' 1>&2
    exit 2
    ;;
esac

#!/bin/bash

ARCH="$(uname -m)"
pushd "$(dirname "$0")" > /dev/null 2>&1
OUT_DIR="$(pwd)/${ARCH}-linux-gnu"
popd > /dev/null 2>&1
LIB_PATH="${OUT_DIR}/lib"
BUILD_DIR=${HOME}/build
export THIRD_PARTY_ROOT="${BUILD_DIR}/third_party"
export PATH="${PATH}:${HOME}/bin"
export RUST_VERSION=1.35.0 RUSTFLAGS='--cfg hermetic'
SOURCE_DIRS=(build)
BUILD_OUTPUTS=(usr lib)

set -o errexit
set -x

install_packages() {
  echo Installing packages...
  sudo dpkg --add-architecture arm64
  sudo apt-get update
  sudo apt-get install -y \
      autoconf \
      automake \
      build-essential \
      "$@" \
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

retry() {
  for i in $(seq 5); do
    "$@" && return 0
    sleep 1
  done
  return 1
}

prepare_cargo() {
  echo Setting up cargo...
  cd
  rm -rf .cargo
  # Sometimes curl hangs. When it does, retry
  retry curl -LO \
    "https://static.rust-lang.org/rustup/archive/1.14.0/$(uname -m)-unknown-linux-gnu/rustup-init"
  # echo "0077ff9c19f722e2be202698c037413099e1188c0c233c12a2297bf18e9ff6e7 *rustup-init" | sha256sum -c -
  chmod +x rustup-init
  ./rustup-init -y --no-modify-path --default-toolchain $RUST_VERSION
  source $HOME/.cargo/env
  if [[ -n "$1" ]]; then
    rustup target add "$1"
  fi
  rustup component add rustfmt-preview
  rm rustup-init

  if [[ -n "$1" ]]; then
  cat >>~/.cargo/config <<EOF
[target.$1]
linker = "${1/-unknown-/-}"
EOF
  fi
}

save_source() {
  echo Saving source...
  cd
  rm -rf clean-source.tgz
  tar cfvz clean-source.tgz "${SOURCE_DIRS[@]}"
}

prepare_source() {
  echo Fetching source...
  # Clean up anything that might be lurking
  cd
  rm -rf "${SOURCE_DIRS[@]}"
  # Needed so we can use git
  install_packages
  mkdir -p "${THIRD_PARTY_ROOT}"
  cd "${THIRD_PARTY_ROOT}"
  # minijail does not exist in upstream linux distros.
  git clone https://android.googlesource.com/platform/external/minijail
  git clone https://android.googlesource.com/platform/external/minigbm \
    -b upstream-master
  sed 's/-Wall/-Wno-maybe-uninitialized/g' -i minigbm/Makefile
  # New libepoxy has EGL_KHR_DEBUG entry points needed by crosvm.
  git clone https://android.googlesource.com/platform/external/libepoxy \
    -b upstream-master
  cd libepoxy
  cd ..
  git clone https://android.googlesource.com/platform/external/virglrenderer \
    -b upstream-master
  git clone https://android.googlesource.com/platform/external/adhd \
    -b upstream-master
  mkdir -p "${BUILD_DIR}/platform"
  cd "${BUILD_DIR}/platform"
  git clone https://android.googlesource.com/platform/external/crosvm \
    -b upstream-master
  save_source
}

restore_source() {
  echo Unpacking source...
  install_packages
  rm -rf "${SOURCE_DIRS[@]}"
  tar xfvmz clean-source.tgz
}

compile() {
  echo Compiling...
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
  for i in $(find build -name .git -type d -print); do
    dir="$(dirname "$i")"
    pushd "${dir}" > /dev/null 2>&1
    echo "${dir}" \
      "$(git remote get-url "$(git remote show)")" \
      "$(git rev-parse HEAD)"
    popd > /dev/null 2>&1
  done | sort > "${OUT_DIR}/BUILD_INFO"
  echo Results in ${OUT_DIR}
}


arm64_retry() {
  MINIGBM_DRV="RADEON VC4" compile
}

arm64_build() {
  rm -rf "${BUILD_OUTPUTS[@]}"
  prepare_cargo
  arm64_retry
}

x86_64_retry() {
  MINIGBM_DRV="I915 RADEON VC4" compile
}

x86_64_build() {
  rm -rf "${BUILD_OUTPUTS[@]}"
  # Cross-compilation is x86_64 specific
  sudo apt install -y crossbuild-essential-arm64
  prepare_cargo aarch64-unknown-linux-gnu
  x86_64_retry
}

if [[ $# -lt 2 ]]; then
  echo Choosing default config
  set prepare_source x86_64_build
fi

echo Steps: "$@"

for i in "$@"; do
  echo $i
  case "$i" in
    arm64_build) $i ;;
    arm64_retry) $i ;;
    prepare_source) $i ;;
    restore_source) $i ;;
    x86_64_build) $i ;;
    x86_64_retry) $i ;;
    *) echo $i unknown 1>&2
      echo usage: $0 'arm64_build|arm64_retry|prepare_source|restore_source|x86_64_build|x86_64_retry ...' 1>&2
       exit 2
       ;;
  esac
done

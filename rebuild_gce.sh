#!/bin/bash

ARCH="$(uname -m)"
pushd "$(dirname "$0")" > /dev/null 2>&1
OUT_DIR="$(pwd)/${ARCH}-linux-gnu"
popd > /dev/null 2>&1
LIB_PATH="${OUT_DIR}/bin"
REPO_DIR=${HOME}/repo
BUILD_DIR=${HOME}/build
export THIRD_PARTY_ROOT="${BUILD_DIR}/third_party"
export PLATFORM_ROOT="${BUILD_DIR}/platform"
export PATH="${PATH}:${HOME}/bin"
SOURCE_DIRS=(build)
BUILD_OUTPUTS=(usr lib)
CUSTOM_MANIFEST=""

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
  mkdir -p "${HOME}/bin"
  curl https://storage.googleapis.com/git-repo-downloads/repo > ~/bin/repo
  chmod a+x ~/bin/repo
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
  ./rustup-init -y --no-modify-path
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

prepare_source() {
  echo Fetching source...
  # Clean up anything that might be lurking
  cd
  rm -rf "${SOURCE_DIRS[@]}"
  # Needed so we can use git
  install_packages
  mkdir -p "${BUILD_DIR}"
  cd "${BUILD_DIR}"
  git config --global user.name "AOSP Crosvm Builder"
  git config --global user.email "nobody@android.com"
  git config --global color.ui false
  repo init -q -b crosvm-master -u https://android.googlesource.com/platform/manifest
  if [[ -n "${CUSTOM_MANIFEST}" ]]; then
    cp "${HOME}/${CUSTOM_MANIFEST}" .repo/manifests
    repo init -m "${CUSTOM_MANIFEST}"
  fi
  repo sync
}

compile() {
  echo Compiling...
  mkdir -p "${HOME}/lib" "${OUT_DIR}/bin"

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
  if [[ ! -d m4 ]]; then
    ./autogen.sh --prefix="${HOME}"
  fi
  make -j install
  cp "${HOME}"/lib/libepoxy.so.0 "${LIB_PATH}"/

  # Note: depends on libepoxy
  cd "${THIRD_PARTY_ROOT}/virglrenderer"
  ./autogen.sh --prefix=${HOME} PKG_CONFIG_PATH=${HOME}/lib/pkgconfig \
    --disable-egl \
    LDFLAGS=-Wl,-rpath,\\\$\$ORIGIN
  make -j install
  cp "${HOME}/lib/libvirglrenderer.so.0" "${LIB_PATH}"/

  source $HOME/.cargo/env
  cd "${PLATFORM_ROOT}/crosvm"

  RUSTFLAGS="-C link-arg=-Wl,-rpath,\$ORIGIN -C link-arg=-L${HOME}/lib" \
    cargo build --features gpu,x

  # Save the outputs
  cp Cargo.lock "${OUT_DIR}"
  cp target/debug/crosvm "${OUT_DIR}/bin/"

  cargo --version --verbose > "${OUT_DIR}/cargo_version.txt"
  rustup show > "${OUT_DIR}/rustup_show.txt"
  dpkg-query -W > "${OUT_DIR}/builder-packages.txt"
  repo manifest -r -o ${OUT_DIR}/manifest.xml
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

if [[ $# -lt 1 ]]; then
  echo Choosing default config
  set prepare_source x86_64_build
fi

echo Steps: "$@"

for i in "$@"; do
  echo $i
  case "$i" in
    CUSTOM_MANIFEST=*) CUSTOM_MANIFEST="${i/CUSTOM_MANIFEST=/}" ;;
    arm64_build) $i ;;
    arm64_retry) $i ;;
    prepare_source) $i ;;
    x86_64_build) $i ;;
    x86_64_retry) $i ;;
    *) echo $i unknown 1>&2
      echo usage: $0 'arm64_build|arm64_retry|prepare_source|x86_64_build|x86_64_retry ...' 1>&2
       exit 2
       ;;
  esac
done

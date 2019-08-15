#!/bin/bash

for i in */bin/*; do
  name="${i//\//_}"
  name="${name//-/_}"
  name="${name/_bin_/_}"
  path="$(dirname $(dirname "$i"))"
  stem="$(basename "$i")"
  cat <<EOF
cc_prebuilt_binary {
  name: "${name}",
  srcs: ["${i}"],
  stem: "${stem}",
  relative_install_path: "${path}",
  defaults: ["cuttlefish_host_only"],
}

EOF
done

for i in */lib/*; do
  name="${i//\//_}"
  name="${name//-/_}"
  name="${name/_lib_/_}"
  name="${name}_for_crosvm"
  path="$(dirname $(dirname "$i"))"
  stem="$(basename "$i")"
  cat <<EOF
// Using cc_prebuilt_binary because cc_prebuild_library can't handle stem on pie
cc_prebuilt_binary {
  name: "${name}",
  srcs: ["${i}"],
  stem: "${stem}",
  relative_install_path: "${path}",
  defaults: ["cuttlefish_host_only"],
}

EOF
done

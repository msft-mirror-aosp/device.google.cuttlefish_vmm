#!/bin/bash

# Common code to build a host image on GCE

# INTERNAL_extra_source may be set to a directory containing the source for
# extra package to build.

# INTERNAL_IP can be set to --internal-ip run on a GCE instance
# The instance will need --scope compute-rw

source "${ANDROID_BUILD_TOP}/external/shflags/src/shflags"
DIR="${ANDROID_BUILD_TOP}/device/google/cuttlefish_vmm"

DEFINE_string arm_system \
  "" "IP address or DNS name of an ARM system to do the secondary build"
DEFINE_string arm_user \
  "vsoc-01" "User to invoke on the ARM system"
DEFINE_string custom_manifest "" "Custom manifest to use for the build"
DEFINE_string project "$(gcloud config get-value project)" "Project to use" "p"
DEFINE_string source_image_family debian-9 "Image familty to use as the base" \
  "s"
DEFINE_string source_image_project debian-cloud \
  "Project holding the base image" "m"
DEFINE_string x86_instance \
  "${USER}-build" "Instance name to create for the build" "i"
DEFINE_string x86_user cuttlefish_crosvm_builder \
  "User name to use on GCE when doing the build"
DEFINE_string zone "$(gcloud config get-value compute/zone)" "Zone to use" "z"

SSH_FLAGS=(${INTERNAL_IP})

wait_for_instance() {
  alive=""
  while [[ -z "${alive}" ]]; do
    sleep 5
    alive="$(gcloud compute ssh "${SSH_FLAGS[@]}" "$@" -- uptime || true)"
  done
}

main() {
  set -o errexit
  set -x
  fail=0
  source_files=("${DIR}"/rebuild_gce.sh)
  gce_flags=()
  if [[ -n "${FLAGS_custom_manifest}" ]]; then
    if [[ ! -f "${FLAGS_custom_manifest}" ]]; then
      echo custom manifest not found: ${FLAGS_custom_manifest} 1>&1
      exit 2
    fi
    source_files+=("${FLAGS_custom_manifest}")
    gce_flags+=("CUSTOM_MANIFEST=/home/${FLAGS_x86_user}/$(basename "${FLAGS_custom_manifest}")")
  fi
  if [[ -z "${FLAGS_project}" ]]; then
    echo Must specify project 1>&2
    fail=1
  fi
  if [[ -z "${FLAGS_zone}" ]]; then
    echo Must specify zone 1>&2
    fail=1
  fi
  if [[ "${fail}" -ne 0 ]]; then
    exit "${fail}"
  fi
  if [[ -n "${FLAGS_x86_instance}" ]]; then
    project_zone_flags=(--project="${FLAGS_project}" --zone="${FLAGS_zone}")
    delete_instances=("${FLAGS_x86_instance}")
    gcloud compute instances delete -q \
      "${project_zone_flags[@]}" \
      "${delete_instances[@]}" || \
        echo Not running
    gcloud compute instances create \
      "${project_zone_flags[@]}" \
      --boot-disk-size=200GB \
      --machine-type=n1-standard-4 \
      --image-family="${FLAGS_source_image_family}" \
      --image-project="${FLAGS_source_image_project}" \
      "${FLAGS_x86_instance}"
    wait_for_instance "${FLAGS_x86_instance}"
    # beta for the --internal-ip flag that may be passed via SSH_FLAGS
    gcloud beta compute scp "${SSH_FLAGS[@]}" \
      "${project_zone_flags[@]}" \
      "${source_files[@]}" \
      "${FLAGS_x86_user}@${FLAGS_x86_instance}:"
    gcloud compute ssh "${SSH_FLAGS[@]}" \
      "${project_zone_flags[@]}" \
      "${FLAGS_x86_user}@${FLAGS_x86_instance}" -- \
        ./rebuild_gce.sh "${gce_flags[@]}" prepare_source x86_64_build
    gcloud beta compute scp --recurse "${SSH_FLAGS[@]}" \
      "${project_zone_flags[@]}" \
      "${FLAGS_x86_user}@${FLAGS_x86_instance}":x86_64-linux-gnu \
      "${ANDROID_BUILD_TOP}/device/google/cuttlefish_vmm"
    gcloud compute disks describe \
      "${project_zone_flags[@]}" "${FLAGS_x86_instance}" | \
        grep ^sourceImage: > "${DIR}"/x86_64-linux-gnu/builder_image.txt
  fi
  if [[ -n "${FLAGS_arm_system}" ]]; then
    scp \
      "${source_files[@]}" \
      "${FLAGS_arm_user}@${FLAGS_arm_system}:"
    # We're using the source tarball from the x86_64 build
    ssh -t "${FLAGS_arm_user}@${FLAGS_arm_system}" -- \
        ./rebuild_gce.sh "${gce_flags[@]}" prepare_source arm64_build
    scp -r "${FLAGS_arm_user}@${FLAGS_arm_system}":aarch64-linux-gnu \
      "${ANDROID_BUILD_TOP}/device/google/cuttlefish_vmm"
  fi
  exit 0
  gcloud compute instances delete -q \
    "${project_zone_flags[@]}" \
    "${FLAGS_x86_instance}"
}

FLAGS "$@" || exit 1
main "${FLAGS_ARGV[@]}"

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
DEFINE_string source_image_family debian-10 "Image familty to use as the base" \
  "s"
DEFINE_string source_image_project debian-cloud \
  "Project holding the base image" "m"
DEFINE_string x86_instance \
  "${USER}-build" "Instance name to create for the build" "i"
DEFINE_string x86_user cuttlefish_crosvm_builder \
  "User name to use on GCE when doing the build"
DEFINE_string zone "$(gcloud config get-value compute/zone)" "Zone to use" "z"
DEFINE_boolean reuse false "Set to true to reuse a previously-set-up instance."
DEFINE_boolean reuse_resync false "Reuse a previously-set-up instance, but clean and re-sync the sources. Overrides --reuse if both are specified."

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
  arm_flags=()
  if [[ -n "${FLAGS_custom_manifest}" ]]; then
    if [[ ! -f "${FLAGS_custom_manifest}" ]]; then
      echo custom manifest not found: ${FLAGS_custom_manifest} 1>&1
      exit 2
    fi
    source_files+=("${FLAGS_custom_manifest}")
    gce_flags+=("CUSTOM_MANIFEST=/home/${FLAGS_x86_user}/$(basename "${FLAGS_custom_manifest}")")
    arm_flags+=("CUSTOM_MANIFEST=/home/${FLAGS_arm_user}/$(basename "${FLAGS_custom_manifest}")")
  fi
  local _prepare_source=(install_packages prepare_source);
  local _reuse=0
  if [ ${FLAGS_reuse} -eq ${FLAGS_TRUE} ]; then
    # neither install packages, nor sync sources; skip to building them
    _prepare_source=()
    _reuse=1
  fi
  if [ ${FLAGS_reuse_resync} -eq ${FLAGS_TRUE} ]; then
    # do not install packages but clean and sync sources afresh
    _prepare_source=(resync_source);
    _reuse=1
  fi
  if [[ -n "${FLAGS_x86_instance}" ]]; then
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
    project_zone_flags=(--project="${FLAGS_project}" --zone="${FLAGS_zone}")
    if [ ${_reuse} -eq 0 ]; then
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
    fi
    local _status=$(gcloud compute instances list \
                    --project="${FLAGS_project}" \
                    --zones="${FLAGS_zone}" \
                    --filter="name=('${FLAGS_x86_instance}')" \
                    --format=flattened | awk '/status:/ {print $2}')
    if [ "${_status}" != "RUNNING" ] ; then
      echo "Instance ${FLAGS_x86_instance} is not running."
      exit 1;
    fi
    # beta for the --internal-ip flag that may be passed via SSH_FLAGS
    gcloud beta compute scp "${SSH_FLAGS[@]}" \
      "${project_zone_flags[@]}" \
      "${source_files[@]}" \
      "${FLAGS_x86_user}@${FLAGS_x86_instance}:"
    gcloud compute ssh "${SSH_FLAGS[@]}" \
      "${project_zone_flags[@]}" \
      "${FLAGS_x86_user}@${FLAGS_x86_instance}" -- \
        ./rebuild_gce.sh "${gce_flags[@]}" ${_prepare_source[@]} x86_64_build
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
    ssh -t "${FLAGS_arm_user}@${FLAGS_arm_system}" -- \
        ./rebuild_gce.sh "${arm_flags[@]}" ${_prepare_source[@]} arm64_build
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

#!/bin/bash

# Common code to build a host image on GCE

# INTERNAL_extra_source may be set to a directory containing the source for
# extra package to build.

# INTERNAL_IP can be set to --internal-ip run on a GCE instance
# The instance will need --scope compute-rw

source "${ANDROID_BUILD_TOP}/external/shflags/src/shflags"
DIR="${ANDROID_BUILD_TOP}/device/google/cuttlefish_vmm"

# ARM-board options

DEFINE_boolean arm false "Build on an ARM board"
DEFINE_string arm_instance "" "IP address or DNS name of an ARM system to do the secondary build"
DEFINE_string arm_user "vsoc-01" "User to invoke on the ARM system"

# Docker options

DEFINE_boolean docker false "Build inside docker"
DEFINE_boolean docker_persistent true "Build inside a privileged, persistent container (faster for iterative development)"
DEFINE_string docker_arch "$(uname -m)" "Target architectre"
DEFINE_boolean docker_build_image true "When --noreuse is specified, this flag controls building the docker image (else we assume it was built and reuse it)"
DEFINE_string docker_image "docker_vmm" "Name of docker image to build"
DEFINE_string docker_container "docker_vmm" "Name of docker container to create"
DEFINE_string docker_source "" "Path to sources checked out using manifest"
DEFINE_string docker_working "" "Path to working directory"
DEFINE_string docker_output "${ANDROID_BUILD_TOP}/device/google/cuttlefish_vmm/${FLAGS_docker_arch}-linux-gnu" "Output directory"
DEFINE_string docker_user "${USER}" "Docker-container user"
DEFINE_string docker_uid "${UID}" "Docker-container user ID"

# GCE options

DEFINE_boolean gce false "Build on a GCE instance"
DEFINE_string gce_project "$(gcloud config get-value project)" "Project to use" "p"
DEFINE_string gce_source_image_family debian-10 "Image familty to use as the base" "s"
DEFINE_string gce_source_image_project debian-cloud "Project holding the base image" "m"
DEFINE_string gce_instance "${USER}-build" "Instance name to create for the build" "i"
DEFINE_string gce_user cuttlefish_crosvm_builder "User name to use on GCE when doing the build"
DEFINE_string gce_zone "$(gcloud config get-value compute/zone)" "Zone to use" "z"

# Common options

DEFINE_string manifest \
          "${ANDROID_BUILD_TOP}/device/google/cuttlefish_vmm/$(uname -m)-linux-gnu/manifest.xml" \
          "manifest to use for the build"
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

function container_exists() {
  [[ $(docker ps -a --filter "name=^/$1$" --format '{{.Names}}') == $1 ]] && echo $1;
}

# inputs
# $1 = FLAGS_docker_image
# $2 = FLAGS_docker_container
# $3 = FLAGS_docker_arch
# $4 = FLAGS_docker_user
# $5 = FLAGS_docker_uid
# $6 = FLAGS_docker_persistent
# $7 = FLAGS_docker_source
# $8 = FLAGS_docker_working
# $9 = FLAGS_docker_output
# $10 = _reuse
# $11 = docker_flags
# $12 = _prepare_source
# $13 = USE
build_locally_using_docker() {
  if [[ -z "${FLAGS_docker_image}" ]]; then
    echo Option --docker_image must not be empty 1>&1
    fail=1
  fi
  if [[ -z "${FLAGS_docker_container}" ]]; then
    echo Options --docker_container must not be empty 1>&2
    fail=1
  fi
  case "${FLAGS_docker_arch}" in
    aarch64) ;;
    x86_64) ;;
    *) echo Invalid value ${FLAGS_docker_arch} for --docker_arch 1>&2
      fail=1
      ;;
  esac
  if [[ -z "${FLAGS_docker_user}" ]]; then
    echo Options --docker_user must not be empty 1>&2
    fail=1
  fi
  if [[ -z "${FLAGS_docker_uid}" ]]; then
    echo Options --docker_uid must not be empty 1>&2
    fail=1
  fi
  # Volume mapping are specified only when a container is created.  With
  # --reuse, an already-created persistent container is reused, which implies
  # that we cannot change the volume maps.  For non-persistent containers, we
  # use docker run, which creates and runs the continer in one step; in that
  # case, we must pass the same values for --docker_source and --docker_output
  # that we passed when we ran the non-persistent continer the first time.
  if [[ ${_reuse} -eq 1 && ${FLAGS_docker_persistent} -eq ${FLAGS_TRUE} ]]; then
    if [ -n "${FLAGS_docker_source}" ]; then
      echo Option --docker_source may not be specified with --reuse 1>&2
      fail=1
    fi
    if [ -n "${FLAGS_docker_working}" ]; then
      echo Option --docker_working may not be specified with --reuse 1>&2
      fail=1
    fi
  fi
  if [[ "${fail}" -ne 0 ]]; then
    exit "${fail}"
  fi
  local _docker_source=
  if [ -n "${FLAGS_docker_source}" ]; then
    _docker_source="-v ${FLAGS_docker_source}:/source:rw"
  fi
  local _docker_working=
  if [ -n "${FLAGS_docker_working}" ]; then
    _docker_working="-v ${FLAGS_docker_working}:/working:rw"
  fi
  local _docker_output=${FLAGS_docker_output}
  if [[ "${_docker_output}" == "${ANDROID_BUILD_TOP}/device/google/cuttlefish_vmm/$(uname -m)-linux-gnu" && \
        "$(uname -m)" != ${FLAGS_docker_arch} ]]; then
    _docker_output="${ANDROID_BUILD_TOP}/device/google/cuttlefish_vmm/${FLAGS_docker_arch}-linux-gnu"
  fi
  local _docker_image=${FLAGS_docker_image}_${FLAGS_docker_arch};
  if [[ ${FLAGS_docker_persistent} -eq ${FLAGS_TRUE} ]]; then
    _docker_image=${FLAGS_docker_image}_${FLAGS_docker_arch}_persistent;
  fi
  local _build_or_retry=${FLAGS_docker_arch}_retry
  if [[ ${_reuse} -eq 0 ]]; then
    _build_or_retry=${FLAGS_docker_arch}_build
    local _docker_target=()
    _docker_target+=("${FLAGS_docker_image}");
    if [[ ${FLAGS_docker_persistent} -eq ${FLAGS_TRUE} ]]; then
      _docker_target+=("${FLAGS_docker_image}_persistent");
    fi
    if [[ ${FLAGS_docker_build_image} -eq ${FLAGS_TRUE} ]]; then
      if [[ ${FLAGS_docker_arch} == aarch64 ]]; then
        export DOCKER_CLI_EXPERIMENTAL=enabled
        docker buildx create --name docker_vmm_${FLAGS_docker_arch}_builder --platform linux/arm64 --use
        for _target in ${_docker_target[@]}; do
          docker buildx build \
            --platform linux/arm64 \
            --target ${_target} \
            -f ${DIR}/Dockerfile \
            -t ${_docker_image}:latest \
            ${DIR} \
            --build-arg USER=${FLAGS_docker_user} \
            --build-arg UID=${FLAGS_docker_uid} --load
        done
        docker buildx rm docker_vmm_${FLAGS_docker_arch}_builder
        unset DOCKER_CLI_EXPERIMENTAL
      else
        for _target in ${_docker_target[@]}; do
          docker build \
            -f ${DIR}/Dockerfile \
            --target ${_target} \
            -t ${_docker_image}:latest \
            ${DIR} \
            --build-arg USER=${FLAGS_docker_user} \
            --build-arg UID=${FLAGS_docker_uid}
        done
      fi
    fi
    if [[ ${FLAGS_docker_persistent} -eq ${FLAGS_TRUE} ]]; then
      if [[ -n "$(container_exists ${FLAGS_docker_container})" ]]; then
        docker rm -f ${FLAGS_docker_container}
      fi
      docker run -d \
        --privileged \
        --name ${FLAGS_docker_container} \
        -h ${FLAGS_docker_container} \
        ${_docker_source} \
        ${_docker_working} \
        -v "${_docker_output}":/output:rw \
        -v /sys/fs/cgroup:/sys/fs/cgroup:ro \
        ${_docker_image}:latest
    fi
  fi
  if [[ ${FLAGS_docker_persistent} -eq ${FLAGS_TRUE} ]]; then
    if [[ "$(docker inspect --format='{{.State.Status}}' ${FLAGS_docker_container})" == "paused" ]]; then
      docker unpause ${FLAGS_docker_container}
    fi
    docker exec -it \
      --user ${FLAGS_docker_user} \
      ${docker_flags[@]} \
      ${FLAGS_docker_container} \
      /static/rebuild-internal.sh ${_prepare_source[@]} ${_build_or_retry}
    docker pause ${FLAGS_docker_container}
  else
    docker run -it --rm \
      --user ${FLAGS_docker_user} \
      ${docker_flags[@]} \
      ${_docker_source} \
      ${_docker_working} \
      -v "${_docker_output}":/output:rw \
      ${_docker_image}:latest \
      /static/rebuild-internal.sh ${_prepare_source[@]} ${_build_or_retry}
  fi
}

function build_on_gce() {
  if [[ -z "${FLAGS_gce_instance}" ]]; then
    echo Must specify instance 1>&2
    fail=1
  fi
  if [[ -z "${FLAGS_gce_project}" ]]; then
    echo Must specify project 1>&2
    fail=1
  fi
  if [[ -z "${FLAGS_gce_zone}" ]]; then
    echo Must specify zone 1>&2
    fail=1
  fi
  if [[ "${fail}" -ne 0 ]]; then
    exit "${fail}"
  fi
  project_zone_flags=(--project="${FLAGS_gce_project}" --zone="${FLAGS_gce_zone}")
  if [ ${_reuse} -eq 0 ]; then
    delete_instances=("${FLAGS_gce_instance}")
    gcloud compute instances delete -q \
      "${project_zone_flags[@]}" \
      "${delete_instances[@]}" || \
        echo Not running
    gcloud compute instances create \
      "${project_zone_flags[@]}" \
      --boot-disk-size=200GB \
      --machine-type=n1-standard-4 \
      --image-family="${FLAGS_gce_source_image_family}" \
      --image-project="${FLAGS_gce_source_image_project}" \
      "${FLAGS_gce_instance}"
    wait_for_instance "${FLAGS_gce_instance}"
  fi
  local _status=$(gcloud compute instances list \
                  --project="${FLAGS_gce_project}" \
                  --zones="${FLAGS_gce_zone}" \
                  --filter="name=('${FLAGS_gce_instance}')" \
                  --format=flattened | awk '/status:/ {print $2}')
  if [ "${_status}" != "RUNNING" ] ; then
    echo "Instance ${FLAGS_gce_instance} is not running."
    exit 1;
  fi
  # beta for the --internal-ip flag that may be passed via SSH_FLAGS
  gcloud beta compute scp "${SSH_FLAGS[@]}" \
    "${project_zone_flags[@]}" \
    "${source_files[@]}" \
    "${FLAGS_gce_user}@${FLAGS_gce_instance}:"
  if [ ${_reuse} -eq 0 ]; then
    gcloud compute ssh "${SSH_FLAGS[@]}" \
      "${project_zone_flags[@]}" \
      "${FLAGS_gce_user}@${FLAGS_gce_instance}" -- \
      ./rebuild-internal.sh install_packages
  fi
  if [ ${_reuse} -eq 0 ]; then
    gcloud compute ssh "${SSH_FLAGS[@]}" \
      "${project_zone_flags[@]}" \
      "${FLAGS_gce_user}@${FLAGS_gce_instance}" -- \
      ./rebuild-internal.sh "${gce_flags[@]}" ${_prepare_source[@]} '$(uname -m)_build'
  else
    gcloud compute ssh "${SSH_FLAGS[@]}" \
      "${project_zone_flags[@]}" \
      "${FLAGS_gce_user}@${FLAGS_gce_instance}" -- \
      ./rebuild-internal.sh "${gce_flags[@]}" ${_prepare_source[@]} '$(uname -m)_retry'
  fi
  gcloud beta compute scp --recurse "${SSH_FLAGS[@]}" \
    "${project_zone_flags[@]}" \
    "${FLAGS_gce_user}@${FLAGS_gce_instance}":x86_64-linux-gnu \
    "${ANDROID_BUILD_TOP}/device/google/cuttlefish_vmm"
  gcloud compute disks describe \
    "${project_zone_flags[@]}" "${FLAGS_gce_instance}" | \
      grep ^sourceImage: > "${DIR}"/x86_64-linux-gnu/builder_image.txt
}

function build_on_arm_board() {
  if [[ -z "${FLAGS_arm_instance}" ]]; then
    echo Must specify IP address of ARM board 1>&2
    fail=1
  fi
  if [[ -z "${FLAGS_arm_user}" ]]; then
    echo Must specify a user account on ARM board 1>&2
    fail=1
  fi
  if [[ "${fail}" -ne 0 ]]; then
    exit "${fail}"
  fi
  scp \
    "${source_files[@]}" \
    "${FLAGS_arm_user}@${FLAGS_arm_instance}:"
  if [ ${_reuse} -eq 0 ]; then
    ssh -t "${FLAGS_arm_user}@${FLAGS_arm_instance}" -- \
      ./rebuild-internal.sh install_packages
    ssh -t "${FLAGS_arm_user}@${FLAGS_arm_instance}" -- \
      ./rebuild-internal.sh "${arm_flags[@]}" ${_prepare_source[@]} '$(uname -m)_build'
  else
    ssh -t "${FLAGS_arm_user}@${FLAGS_arm_instance}" -- \
      ./rebuild-internal.sh "${arm_flags[@]}" ${_prepare_source[@]} '$(uname -m)_retry'
  fi
  scp -r "${FLAGS_arm_user}@${FLAGS_arm_instance}":aarch64-linux-gnu \
    "${ANDROID_BUILD_TOP}/device/google/cuttlefish_vmm"
}

main() {
  set -o errexit
  set -x
  fail=0
  source_files=("${DIR}"/rebuild-internal.sh)
  # These must match the definitions in the Dockerfile
  docker_flags=("-e SOURCE_DIR=/source" "-e WORKING_DIR=/working" "-e OUTPUT_DIR=/output" "-e TOOLS_DIR=/static/tools")
  gce_flags=()
  arm_flags=()

  if [[ $(( $((${FLAGS_gce}==${FLAGS_TRUE})) + $((${FLAGS_arm}==${FLAGS_TRUE})) + $((${FLAGS_docker}==${FLAGS_TRUE})) )) > 1 ]]; then
    echo You may specify only one of --gce, --docker, or --arm 1>&2
    exit 2
  fi

  if [[ -n "${FLAGS_manifest}" ]]; then
    if [[ ! -f "${FLAGS_manifest}" ]]; then
      echo custom manifest not found: ${FLAGS_manifest} 1>&1
      exit 2
    fi
    source_files+=("${FLAGS_manifest}")
    docker_flags+=("-e CUSTOM_MANIFEST=/static/${FLAGS_docker_arch}-linux-gnu/$(basename ${FLAGS_manifest})")
    gce_flags+=("CUSTOM_MANIFEST=/home/${FLAGS_gce_user}/$(basename "${FLAGS_manifest}")")
    arm_flags+=("CUSTOM_MANIFEST=/home/${FLAGS_arm_user}/$(basename "${FLAGS_manifest}")")
  fi
  local _prepare_source=(setup_env fetch_source);
  local _reuse=0
  if [[ ${FLAGS_reuse} -eq ${FLAGS_TRUE} ]]; then
    # neither install packages, nor sync sources; skip to building them
    _prepare_source=(setup_env)
    _reuse=1
  fi
  if [[ ${FLAGS_reuse_resync} -eq ${FLAGS_TRUE} ]]; then
    # do not install packages but clean and sync sources afresh
    _prepare_source=(setup_env resync_source);
    _reuse=1
  fi
  if [[ ${FLAGS_gce} -eq ${FLAGS_TRUE} ]]; then
    build_on_gce
    exit 0
    gcloud compute instances delete -q \
      "${project_zone_flags[@]}" \
      "${FLAGS_gce_instance}"
  fi
  if [ ${FLAGS_arm} -eq ${FLAGS_TRUE} ]; then
    build_on_arm_board
    exit 0
  fi
  if [[ ${FLAGS_docker} -eq ${FLAGS_TRUE} ]]; then
    build_locally_using_docker
    exit 0
  fi
}

FLAGS "$@" || exit 1
main "${FLAGS_ARGV[@]}"

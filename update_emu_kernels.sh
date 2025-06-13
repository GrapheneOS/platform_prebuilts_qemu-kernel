#!/bin/bash

KERNEL_VERSION="6.6"

# ./update_emu_kernel.sh --bug 123 --bid 123456

set -e
set -o errexit
source gbash.sh

DEFINE_int bug 0 "Bug with the reason for the update"
DEFINE_int bid 0 "Build id for goldfish modules"

fetch_arch() {
  scratch_dir="${1}"
  bid="${2}"
  kernel_target="${3}"
  kernel_artifact="${4}"
  modules_target="${5}"

  mkdir "${scratch_dir}"
  pushd "${scratch_dir}"
  /google/data/ro/projects/android/fetch_artifact \
    --bid "${bid}" \
    --target "${kernel_target}" \
    "${kernel_artifact}"
  
  mkdir "${scratch_dir}/gki_modules"
  pushd "${scratch_dir}/gki_modules"
  /google/data/ro/projects/android/fetch_artifact \
    --bid "${bid}" \
    --target "${kernel_target}" \
    "*.ko"
  popd

  mkdir "${scratch_dir}/goldfish_modules"
  pushd "${scratch_dir}/goldfish_modules"
  /google/data/ro/projects/android/fetch_artifact \
    --bid "${bid}" \
    --target "${modules_target}" \
    "*.ko"
  popd

  popd
}

move_artifacts() {
  scratch_dir="${1}"
  dst_dir="${2}"
  kernel_artifact="${3}"
  kernel_filename="${4}"

  if [[ ! -d "${dst_dir}" ]]; then
    mkdir -p "${dst_dir}"
  fi

  pushd "${scratch_dir}"

  if [[ -f "${kernel_artifact}" ]]; then
    mv "${kernel_artifact}" "${dst_dir}/${kernel_filename}"
    rm -rf "${dst_dir}/gki_modules"
    mv "${scratch_dir}/gki_modules" "${dst_dir}/gki_modules"
  fi

  rm -rf "${dst_dir}/goldfish_modules"
  mv "${scratch_dir}/goldfish_modules" "${dst_dir}/goldfish_modules"

  popd
}

make_git_commit() {
  git commit -a -m "$(
  echo Update kernel prebuilts to go/ab/${FLAGS_bid}
  echo
  echo Test: TreeHugger
  echo Bug: ${FLAGS_bug}
  )"
  git commit --amend -s
}

main() {
  fail=0
  if [[ "${FLAGS_bug}" -eq 0 ]]; then
    echo "Must specify --bug" 1>&2
    fail=1
  fi
  if [[ "${FLAGS_bid}" -eq 0 ]]; then
    echo "Must specify --bid" 1>&2
    fail=1
  fi

  if [[ "${fail}" -ne 0 ]]; then
    exit "${fail}"
  fi

  here="$(pwd)"
  x86_dst_dir="${here}/x86_64/${KERNEL_VERSION}"
  arm_dst_dir="${here}/arm64/${KERNEL_VERSION}"
  arm16k_dst_dir="${here}/arm64_16k/${KERNEL_VERSION}"

  scratch_dir="$(mktemp -d)"
  x86_scratch_dir="${scratch_dir}/x86"
  arm_scratch_dir="${scratch_dir}/arm"
  arm16k_scratch_dir="${scratch_dir}/arm16k"

  fetch_arch "${x86_scratch_dir}" "${FLAGS_bid}" \
    "kernel_x86_64" "bzImage" "kernel_virt_x86_64"

  fetch_arch "${arm_scratch_dir}" "${FLAGS_bid}" \
    "kernel_aarch64" "Image" "kernel_virt_aarch64"

  fetch_arch "${arm16k_scratch_dir}" "${FLAGS_bid}" \
    "kernel_aarch64_16k" "Image" "kernel_virt_aarch64_16k"


  if [[ -f "${arm_scratch_dir}/Image" ]]; then
    gzip -9 "${arm_scratch_dir}/Image"
  fi

  if [[ -f "${arm16k_scratch_dir}/Image" ]]; then
    gzip -9 "${arm16k_scratch_dir}/Image"
  fi


  move_artifacts "${x86_scratch_dir}" "${x86_dst_dir}" \
    "bzImage" "kernel-${KERNEL_VERSION}"

  move_artifacts "${arm_scratch_dir}" "${arm_dst_dir}" \
    "Image.gz" "kernel-${KERNEL_VERSION}-gz"

  move_artifacts "${arm16k_scratch_dir}" "${arm16k_dst_dir}" \
    "Image.gz" "kernel-${KERNEL_VERSION}-gz"

  git add "${x86_dst_dir}"
  git add "${arm_dst_dir}"
  git add "${arm16k_dst_dir}"

  make_git_commit
}

gbash::main "$@"

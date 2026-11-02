#!/usr/bin/env bash
set -euo pipefail

# CI smoke-test official tcp-brutal against this exact kernel build.
# We DON'T bundle Brutal into the kernel: production servers already have
# tcp-brutal 2.0.1 DKMS configured with AUTOINSTALL=yes.
workspace="${GITHUB_WORKSPACE:-$(pwd)}"
linux_tree="${1:?usage: verify-brutal-module.sh <absolute-kernel-tree> <localversion>}"
localver="${2:?usage: verify-brutal-module.sh <absolute-kernel-tree> <localversion>}"
[[ "$linux_tree" = /* && -f "$linux_tree/Makefile" ]] || {
  echo 'ERROR: absolute Linux source tree required' >&2; exit 1;
}
commit_file="$workspace/integrations/tcp-brutal/COMMIT"
[[ -f "$commit_file" ]] || { echo "Missing $commit_file" >&2; exit 1; }
commit=$(tr -d '\r\n' < "$commit_file")
[[ "$commit" =~ ^[0-9a-f]{40}$ ]] || { echo 'Bad Brutal commit SHA' >&2; exit 1; }

src="$workspace/kernel/tcp-brutal-pinned"
[[ ! -e "$src" ]] || { echo 'Brutal source directory already exists' >&2; exit 1; }
mkdir -p "$src"
git -C "$src" init -q
git -C "$src" remote add origin https://github.com/HyNetworks/tcp-brutal.git
git -C "$src" fetch --depth 1 -q origin "$commit"
git -C "$src" checkout -q --detach FETCH_HEAD
[[ "$(git -C "$src" rev-parse HEAD)" = "$commit" ]] || {
  echo 'Brutal commit mismatch' >&2; exit 1;
}

# The official Makefile accepts KERNEL_DIR, and invokes Kbuild in that tree.
make -C "$src" KERNEL_DIR="$linux_tree" LOCALVERSION="$localver" -j"$(nproc)"
[[ -s "$src/brutal.ko" ]] || { echo 'Brutal module not produced' >&2; exit 1; }
expected=$(make -s -C "$linux_tree" ARCH=arm64 LOCALVERSION="$localver" kernelrelease)
actual=$(modinfo -F vermagic "$src/brutal.ko")
case "$actual" in
  "$expected "*) echo "Brutal Kbuild ABI smoke test OK: $actual" ;;
  *) echo "Brutal vermagic mismatch: expected $expected, got $actual" >&2; exit 1 ;;
esac
cp "$src/brutal.ko" "$workspace/kernel/brutal-${expected}.ko"

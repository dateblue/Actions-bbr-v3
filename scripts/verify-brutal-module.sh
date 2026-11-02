#!/usr/bin/env bash
set -euo pipefail
# An early Kbuild object compilation must succeed BEFORE the costly kernel DEB
# build. Full .ko + vermagic validation happens AFTER a completed DEB build.
# Always pass Kbuild an absolute M=<actual external source directory>.

usage='usage: verify-brutal-module.sh <absolute-linux-tree> <localversion> <preflight|build>'
[[ $# -eq 3 ]] || { echo "ERROR: $usage" >&2; exit 2; }
linux_tree="$1" localver="$2" mode="$3"
[[ "$mode" == preflight || "$mode" == build ]] || { echo "ERROR: invalid mode: $mode" >&2; exit 2; }
[[ "$linux_tree" = /* && -f "$linux_tree/Makefile" ]] || {
    echo 'ERROR: absolute path to existing Linux source tree required' >&2; exit 2;
}
workspace="${GITHUB_WORKSPACE:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)}"
commit_file="$workspace/integrations/tcp-brutal/COMMIT"
[[ -f "$commit_file" ]] || { echo "ERROR: pinned commit file missing: $commit_file" >&2; exit 2; }
commit=$(tr -d '\r\n' < "$commit_file")
[[ "$commit" =~ ^[[:xdigit:]]{40}$ ]] || { echo 'ERROR: invalid pinned Brutal commit' >&2; exit 2; }
src="$workspace/kernel/tcp-brutal-pinned"
mkdir -p -- "$workspace/kernel"
if [[ ! -d "$src/.git" ]]; then
    [[ ! -e "$src" ]] || { echo "ERROR: existing source folder is not a Git checkout: $src" >&2; exit 2; }
    git init -q -- "$src"
    git -C "$src" remote add origin https://github.com/HyNetworks/tcp-brutal.git
    git -C "$src" fetch -q --depth=1 origin "$commit"
    git -C "$src" checkout -q --detach FETCH_HEAD
fi
[[ "$(git -C "$src" rev-parse HEAD)" == "$commit" ]] || {
    echo 'ERROR: checked-out Brutal commit differs from pin' >&2; exit 2;
}
for file in Makefile brutal_cc.c brutal_sockopt.c brutal_rules.c; do
    [[ -s "$src/$file" ]] || { echo "ERROR: missing Brutal file: $file" >&2; exit 2; }
done

# No -C on the external module Makefile! That Makefile uses M=$(PWD), which
# can be the *workflow* directory. Directly invoke the kernel Kbuild instead.
# Preflight must exercise the same M= directory used by the release build.
common=( -C "$linux_tree" ARCH=arm64 LOCALVERSION="$localver" M="$src" )
expected=$(make -s -C "$linux_tree" ARCH=arm64 LOCALVERSION="$localver" kernelrelease)
[[ -n "$expected" ]] || { echo 'ERROR: kernelrelease unavailable' >&2; exit 2; }
echo "Kernel release=$expected; external module M=$src"
if [[ "$mode" == preflight ]]; then
    # Do not require Module.symvers here. Source/headers compile check only;
    # Module.symvers and the complete .ko will be validated after bindeb-pkg.
    make -C "$linux_tree" ARCH=arm64 LOCALVERSION="$localver" modules_prepare
    # Kbuild expects object *names*, not absolute target paths.
    make "${common[@]}" -j"$(nproc)" \
        brutal_cc.o brutal_sockopt.o brutal_rules.o
    for file in brutal_cc.o brutal_sockopt.o brutal_rules.o; do
        [[ -s "$src/$file" ]] || { echo "ERROR: preflight did not produce $file" >&2; exit 2; }
    done
    echo 'OK: official tcp-brutal C objects compiled BEFORE full kernel build'
    exit 0
fi

# Check genuine kernel ABI availability before invoking the external build.
[[ -s "$linux_tree/Module.symvers" ]] || {
    echo 'ERROR: Module.symvers missing after kernel build; cannot validate DKMS ABI' >&2; exit 2;
}
make "${common[@]}" -j"$(nproc)" modules
[[ -s "$src/brutal.ko" ]] || { echo 'ERROR: missing compiled brutal.ko' >&2; exit 2; }
actual=$(modinfo -F vermagic "$src/brutal.ko")
case "$actual" in
    "$expected "*) echo "OK: Brutal vermagic=$actual" ;;
    *) echo "ERROR: expected ABI '$expected' but got '$actual'" >&2; exit 2 ;;
esac
cp -- "$src/brutal.ko" "$workspace/kernel/brutal-${expected}.ko"

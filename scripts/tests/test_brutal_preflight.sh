#!/usr/bin/env bash
set -euo pipefail
# Regression test for the exact M=$(PWD) bug that wasted a 58-minute build.
# Uses fake Kbuild and a local pinned fake Git module, never downloads Linux.
repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf -- "$tmp"' EXIT
ws="$tmp/ws" src="$tmp/ws/kernel/tcp-brutal-pinned" kernel="$tmp/linux"
mkdir -p "$src" "$kernel" "$ws/integrations/tcp-brutal" "$tmp/bin"
cat >"$kernel/Makefile" <<'EOF'
.PHONY: kernelrelease modules_prepare modules brutal_cc.o brutal_sockopt.o brutal_rules.o
kernelrelease:
	@echo 7.3.1-bbrv3plus-slim
modules_prepare:
	@true
brutal_cc.o brutal_sockopt.o brutal_rules.o:
	@test -n "$(M)" && test -f "$(M)/$(@:.o=.c)"
	@echo object > "$(M)/$@"
modules:
	@test -n "$(M)" && test -f "$(M)/Makefile"
	@echo module > "$(M)/brutal.ko"
EOF
for item in Makefile brutal_cc.c brutal_sockopt.c brutal_rules.c; do
    echo '// test fixture' > "$src/$item"
done
git -C "$src" init -q
git -C "$src" config user.email ci@example.invalid
git -C "$src" config user.name CIBot
git -C "$src" add .
git -C "$src" -c commit.gpgsign=false commit -qm pinned
commit=$(git -C "$src" rev-parse HEAD)
printf '%s\n' "$commit" >"$ws/integrations/tcp-brutal/COMMIT"
echo 'mock symbol versions' >"$kernel/Module.symvers"
cat >"$tmp/bin/modinfo" <<'EOF'
#!/usr/bin/env bash
[[ "$1" == -F && "$2" == vermagic && -s "$3" ]] || exit 2
echo '7.3.1-bbrv3plus-slim SMP preempt mod_unload modversions aarch64'
EOF
chmod +x "$tmp/bin/modinfo"
GITHUB_WORKSPACE="$ws" PATH="$tmp/bin:$PATH" \
  bash "$repo/scripts/verify-brutal-module.sh" "$kernel" -bbrv3plus-slim preflight
for file in brutal_cc.o brutal_sockopt.o brutal_rules.o; do
    test -s "$src/$file" || { echo "ERROR: mock Kbuild did not compile $file"; exit 1; }
done
GITHUB_WORKSPACE="$ws" PATH="$tmp/bin:$PATH" \
  bash "$repo/scripts/verify-brutal-module.sh" "$kernel" -bbrv3plus-slim build
test -s "$ws/kernel/brutal-7.3.1-bbrv3plus-slim.ko"
echo 'OK: pinned external-module path, preflight objects, final ABI/artifact chain'

#!/usr/bin/env bash
set -euo pipefail

# Run from a Linux kernel build tree AFTER apply-bbrv3-port.sh.
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
src=net/ipv4/tcp_bbr.c
plus=net/ipv4/tcp_bbrplus.c

if [[ ! -f "$src" || ! -f net/ipv4/Kconfig || ! -f net/ipv4/Makefile ]]; then
  echo 'ERROR: Run this script from the root of a Linux kernel source tree.' >&2
  exit 1
fi
if [[ -e "$plus" ]] || grep -q 'CONFIG_TCP_CONG_BBRPLUS' net/ipv4/Makefile; then
  echo 'ERROR: BBRv3 Plus source/config already exists; refusing to apply twice.' >&2
  exit 1
fi
if ! grep -Eq '^#define[[:space:]]+BBR_VERSION[[:space:]]+3\b' "$src"; then
  echo 'ERROR: Apply the BBRv3 upstream port before creating BBRv3 Plus.' >&2
  exit 1
fi

# IMPORTANT: Leave tcp_bbr.c completely untouched.
cp "$src" "$plus"
bash "$script_dir/apply-bbrv3-max-profile.sh" "$plus" >/dev/null
bash "$script_dir/apply-bbrv3-extreme-profile.sh" "$plus"

python3 - <<'PY'
import re
from pathlib import Path

plus = Path('net/ipv4/tcp_bbrplus.c')
text = plus.read_text()

# Source-local function/constant names get their own namespace to avoid
# duplicate BPF/kfunc and initcall symbol registration when built in.
# Do NOT rename UAPI fields such as info->bbr.bbr_bw_lo.
text = re.sub(r'(?<![.>])\bbbr_(?=[A-Za-z0-9_])', 'bbrplus_', text)

for old, new in (
    ('tcp_bbr_cong_ops', 'tcp_bbrplus_cong_ops'),
    ('tcp_bbr_check_kfunc_ids', 'tcp_bbrplus_check_kfunc_ids'),
    ('tcp_bbr_kfunc_set', 'tcp_bbrplus_kfunc_set'),
):
    if old not in text:
        raise SystemExit(f'ERROR: missing expected symbol {old}')
    text = text.replace(old, new)

text, count = re.subn(r'(\.name\s*=\s*)"bbr"', r'\g<1>"bbrv3plus"', text)
if count != 1:
    raise SystemExit(f'ERROR: expected one bbr congestion-control registration, found {count}')

# Distinct module description; keep SPDX/license/author metadata.
text, desc_count = re.subn(r'(?m)^MODULE_DESCRIPTION\([^\n]+\);\s*\n?', '', text)
if desc_count != 1:
    raise SystemExit(f'ERROR: expected one MODULE_DESCRIPTION, found {desc_count}')
text = text.rstrip() + '\nMODULE_DESCRIPTION("TCP BBRv3 Plus Extreme");\n'

if re.search(r'(?m)^\s*\.name\s*=\s*"bbr"', text):
    raise SystemExit('ERROR: duplicate bbr registration remains in plus source')
plus.write_text(text)

makefile = Path('net/ipv4/Makefile')
make_text = makefile.read_text()
needle = 'obj-$(CONFIG_TCP_CONG_BBR) += tcp_bbr.o\n'
if make_text.count(needle) != 1:
    raise SystemExit('ERROR: net/ipv4/Makefile BBR object entry missing/ambiguous')
make_text = make_text.replace(needle, needle + 'obj-$(CONFIG_TCP_CONG_BBRPLUS) += tcp_bbrplus.o\n')
makefile.write_text(make_text)

kconfig = Path('net/ipv4/Kconfig')
kconfig_text = kconfig.read_text()
anchor = 'choice\n\tprompt "Default TCP congestion control"'
if kconfig_text.count(anchor) != 1:
    raise SystemExit('ERROR: Kconfig TCP default congestion-control choice not found uniquely')
kconfig_text = kconfig_text.replace(anchor, '''config TCP_CONG_BBRPLUS
\ttristate "BBRv3 Plus Extreme TCP"
\tdefault n
\thelp
\t  BBRv3 Plus Extreme is an independent experimental TCP
\t  congestion-control variant based on BBRv3.
\t  The original BBRv3 implementation remains unchanged.

''' + anchor)
kconfig.write_text(kconfig_text)

print('OK: independent bbrv3plus source, Kconfig and Makefile installed')
print('OK: base tcp_bbr.c remains unchanged')
PY

# Two implementations must register different names.
grep -Eq '\.name[[:space:]]*=[[:space:]]*"bbrv3plus"' "$plus"
grep -Eq '\.name[[:space:]]*=[[:space:]]*"bbr"' "$src"
grep -q 'CONFIG_TCP_CONG_BBRPLUS' net/ipv4/Makefile

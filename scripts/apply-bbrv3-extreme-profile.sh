#!/usr/bin/env bash
set -euo pipefail

# Apply ONLY to the private BBRv3 Plus copy, after byJoey's Max profile,
# before create-bbrv3plus.sh namespaces symbols. Never touch tcp_bbr.c.
target="${1:-net/ipv4/tcp_bbrplus.c}"
[[ -f "$target" ]] || { echo "Missing BBRv3 Plus source: $target" >&2; exit 1; }

python3 - "$target" <<'PY'
import re
import sys
from pathlib import Path

path = Path(sys.argv[1])
src = path.read_text()
if not re.search(r'^#define\s+BBR_VERSION\s+3\b', src, re.M):
    raise SystemExit('ERROR: Expected BBR_VERSION 3')

# First v0.2 experiment: gain changes ONLY. Keep BBRv3 loss/inflight/ECN
# safeguards from the parent Max profile. All patterns must match once.
changes = [
    ('startup_pacing',
     r'(static const int bbr_startup_pacing_gain\s*=\s*)BBR_UNIT \* 3;',
     r'\g<1>BBR_UNIT * 7 / 2;'),                     # 3.50
    ('startup_cwnd',
     r'(static const int bbr_startup_cwnd_gain\s*=\s*)BBR_UNIT \* 5 / 2;',
     r'\g<1>BBR_UNIT * 3;'),                         # 3.00
    ('steady_cwnd',
     r'(static const int bbr_cwnd_gain\s*=\s*)BBR_UNIT \* 5 / 2;',
     r'\g<1>BBR_UNIT * 3;'),                         # 3.00
    ('probe_up',
     r'BBR_UNIT \* 3 / 2,(\s*/\* UP:)',
     r'BBR_UNIT * 37 / 20,\g<1>'),                   # 1.85
    ('probe_refill',
     r'BBR_UNIT \* 5 / 4,(\s*/\* REFILL:)',
     r'BBR_UNIT * 3 / 2,\g<1>'),                     # 1.50
]
for name, old, new in changes:
    src, hits = re.subn(old, new, src)
    if hits != 1:
        raise SystemExit(f'ERROR: {name}: expected one match, got {hits}; file unchanged')
    print('Extreme Slim v0.2:', name, 'OK')

path.write_text(src)
print('BBRv3 Plus v0.2 gains applied; source TCP BBR unchanged')
PY

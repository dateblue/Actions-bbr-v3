#!/usr/bin/env bash
set -euo pipefail

target="${1:-net/ipv4/tcp_bbr.c}"

if [[ ! -f "$target" ]]; then
    echo "BBRv3 source not found: $target" >&2
    exit 1
fi

python3 - "$target" <<'PY'
import re
import sys
from pathlib import Path

path = Path(sys.argv[1])
source = path.read_text()

if not re.search(r"^#define BBR_VERSION\s+3\b", source, re.M):
    sys.exit("ERROR: BBR_VERSION=3 not found")

changes = [
    (
        "startup_pacing_gain",
        r"(static const int bbr_startup_pacing_gain\s*=\s*)BBR_UNIT \* 3;",
        r"\g<1>BBR_UNIT * 13 / 4;",
    ),
    (
        "startup_cwnd_gain",
        r"(static const int bbr_startup_cwnd_gain\s*=\s*)BBR_UNIT \* 5 / 2;",
        r"\g<1>BBR_UNIT * 11 / 4;",
    ),
    (
        "cwnd_gain",
        r"(static const int bbr_cwnd_gain\s*=\s*)BBR_UNIT \* 5 / 2;",
        r"\g<1>BBR_UNIT * 11 / 4;",
    ),
    (
        "probebw_up",
        r"BBR_UNIT \* 3 / 2,(\s*/\* UP:)",
        r"BBR_UNIT * 33 / 20,\g<1>",
    ),
    (
        "probebw_refill",
        r"BBR_UNIT \* 5 / 4,(\s*/\* REFILL:)",
        r"BBR_UNIT * 27 / 20,\g<1>",
    ),
]

for name, pattern, replacement in changes:
    source, count = re.subn(pattern, replacement, source)
    if count != 1:
        sys.exit(
            f"ERROR: {name} expected exactly once, got {count}"
        )
    print(f"Extreme: {name} OK")

path.write_text(source)
print("BBRv3 Plus Extreme profile applied successfully")
PY

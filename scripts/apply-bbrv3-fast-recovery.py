#!/usr/bin/env python3
"""Inject an opt-in-to-Plus-only conservative early ProbeBW REFILL gate.

Must run on tcp_bbrplus.c AFTER Max + Extreme profiles and BEFORE namespacing.
No extra sk memory, no timers or eBPF, and no change to upstream BBRv3.
"""
import re
import sys
from pathlib import Path

MARKER = 'BBRPLUS_FAST_RECOVERY'
HELPER = r'''/* BBRPLUS_FAST_RECOVERY: after real loss/ECN has reduced bw_lo, allow an
 * early *normal* REFILL probe if clean feedback shows that usable bandwidth
 * is back. Never probe from PROBE_DOWN, while TCP is recovering, or on
 * application-limited/retransmission/ECN/loss samples. This does NOT bypass
 * inflight_hi/lo, loss recovery, or the regular BBRv3 probe state machine.
 *
 * Reuse existing per-socket BBR state. No extra fields, allocations or BPF.
 */
static bool bbr_fast_reprobe_ready(struct sock *sk,
                                   const struct rate_sample *rs)
{
    const struct bbr *bbr = inet_csk_ca(sk);

    if (bbr->cycle_idx != BBR_BW_PROBE_CRUISE ||
        inet_csk(sk)->icsk_ca_state != TCP_CA_Open ||
        !bbr->loss_round_start ||
        bbr->rounds_since_probe < 4 ||
        bbr->prev_probe_too_high || bbr->stopped_risky_probe ||
        bbr->loss_in_round || bbr->ecn_in_round ||
        rs->losses > 0 || rs->delivered_ce > 0 ||
        rs->delivered <= 0 || rs->interval_us <= 0 ||
        rs->is_app_limited || rs->is_retrans ||
        bbr->bw_lo == ~0U || bbr->bw_lo == 0 ||
        bbr->bw_latest <= ((u64)bbr->bw_lo * 9 >> 3))
        return false;

    /* The normal wait is 750-1000 ms in Extreme Slim. Do not allow an
     * early attempt before 500 ms or less than four packet-timed rounds.
     * The existing PROBE_DOWN/CRUISE transition and loss feedback remain.
     */
    return bbr_has_elapsed_in_phase(sk, 500 * 1000);
}

'''
INJECT = '''\tif (bbr_fast_reprobe_ready(sk, rs)) {\n\t\tbbr_start_bw_probe_refill(sk, 0);\n\t\treturn true;\n\t}\n\n'''


def apply(src: str) -> str:
    if MARKER in src:
        raise ValueError('Fast Recovery already present; refuse duplicate injection')
    if not re.search(r'^#define\s+BBR_VERSION\s+3\b', src, re.M):
        raise ValueError('BBRv3 source (BBR_VERSION 3) required')
    start_re = re.compile(
        r'(?m)^static bool bbr_check_time_to_probe_bw\(struct sock \*sk,\s*\n'
        r'\s*const struct rate_sample \*rs\)\s*\n\{'
    )
    matches = list(start_re.finditer(src))
    if len(matches) != 1:
        raise ValueError(f'expected one ProbeBW function, found {len(matches)}')
    start = matches[0].start()
    # Require an intact known source layout, never patch an arbitrary block.
    after = src.find('\n/* Is it time to transition from PROBE_DOWN', start)
    if after < 0:
        raise ValueError('expected ProbeBW function terminator not found')
    target = src[start:after]
    needle = '\tif (bbr_has_elapsed_in_phase(sk, bbr->probe_wait_us) ||\n'
    if target.count(needle) != 1:
        raise ValueError('ProbeBW normal-wait anchor missing or ambiguous')
    if target.count('bbr_start_bw_probe_refill(sk, 0);') != 1:
        raise ValueError('unexpected ProbeBW REFILL call count')
    return src[:start] + HELPER + target.replace(needle, INJECT + needle) + src[after:]


def main() -> None:
    if len(sys.argv) != 2:
        raise SystemExit('Usage: apply-bbrv3-fast-recovery.py <tcp_bbrplus.c>')
    path = Path(sys.argv[1])
    if path.name != 'tcp_bbrplus.c':
        raise SystemExit('ERROR: will only modify tcp_bbrplus.c')
    before = path.read_text()
    try:
        after = apply(before)
    except ValueError as e:
        raise SystemExit(f'ERROR: {e}') from e
    path.write_text(after)
    print('OK: BBRv3 Plus early REFILL gate installed (no additional socket state)')


if __name__ == '__main__':
    main()

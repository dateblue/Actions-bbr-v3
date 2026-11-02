#!/usr/bin/env python3
"""Tests run on push before fetching/building an entire Linux kernel."""
from pathlib import Path
import importlib.util
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / 'scripts' / 'apply-bbrv3-fast-recovery.py'
spec = importlib.util.spec_from_file_location('fast_recovery', SCRIPT)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

# The function anchors below are copied from the Linux-7.3 BBRv3 port.
# These are intentionally limited fixtures, not a substitute for compiling
# the actual generated tcp_bbrplus.o against the pinned ARM64 kernel tree.
SOURCE = '''#define BBR_VERSION 3
static bool bbr_check_time_to_probe_bw(struct sock *sk,
                                       const struct rate_sample *rs)
{
    struct bbr *bbr = inet_csk_ca(sk);
    u32 n;
    if (bbr_param(sk, ecn_reprobe_gain)) {
        n = 0;
        bbr_start_bw_probe_refill(sk, n);
        return true;
    }

\tif (bbr_has_elapsed_in_phase(sk, bbr->probe_wait_us) ||
\t    bbr_is_reno_coexistence_probe_time(sk)) {
\t\tbbr_start_bw_probe_refill(sk, 0);
\t\treturn true;
\t}
\treturn false;
}

/* Is it time to transition from PROBE_DOWN to PROBE_CRUISE? */
static bool next_func(void) { return false; }
'''


class FastRecoveryTests(unittest.TestCase):
    def test_injection_once_and_guard(self):
        modified = module.apply(SOURCE)
        self.assertEqual(modified.count('BBRPLUS_FAST_RECOVERY'), 1)
        self.assertEqual(modified.count('bbr_fast_reprobe_ready(sk, rs)'), 1)
        self.assertIn('bbr->bw_latest <= ((u64)bbr->bw_lo * 9 >> 3)', modified)
        self.assertIn('bbr->cycle_idx != BBR_BW_PROBE_CRUISE', modified)
        self.assertIn('bbr_has_elapsed_in_phase(sk, 500 * 1000)', modified)
        self.assertEqual(modified.count('bbr_start_bw_probe_refill(sk, 0);'), 2)
        self.assertLess(modified.index('bbr_fast_reprobe_ready(sk, rs)'),
                        modified.index('bbr_has_elapsed_in_phase(sk, bbr->probe_wait_us)'))

    def test_no_duplicate_patch(self):
        with self.assertRaisesRegex(ValueError, 'already present'):
            module.apply(module.apply(SOURCE))

    def test_no_unrecognized_source(self):
        with self.assertRaisesRegex(ValueError, 'BBRv3 source'):
            module.apply(SOURCE.replace('#define BBR_VERSION 3', '#define BBR_VERSION 2'))
        with self.assertRaisesRegex(ValueError, 'anchor'):
            module.apply(SOURCE.replace('\tif (bbr_has_elapsed_in_phase',
                                        '\tif (bbr_UNKNOWN_elapsed'))

    @unittest.skipUnless(shutil.which('cc'), 'requires C compiler')
    def test_helper_compiles_and_guards_expected_states(self):
        src = module.apply(SOURCE)
        helper = src[src.index('/* BBRPLUS_FAST_RECOVERY:'):src.index('static bool bbr_check_time_to_probe_bw')]
        header = r'''
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
typedef uint32_t u32;
typedef uint64_t u64;
#define BBR_BW_PROBE_CRUISE 2
#define TCP_CA_Open 0
struct bbr {
    u32 cycle_idx;
    u32 rounds_since_probe;
    bool loss_round_start;
    bool loss_in_round;
    bool ecn_in_round;
    bool prev_probe_too_high;
    bool stopped_risky_probe;
    u32 bw_lo;
    u32 bw_latest;
};
struct rate_sample {
    int losses, delivered_ce, delivered, interval_us;
    bool is_app_limited, is_retrans;
};
struct sock {
    struct bbr bbr;
    int ca_state;
    bool time_elapsed;
};
struct connection { int icsk_ca_state; };
static struct bbr *inet_csk_ca(struct sock *sk) { return &sk->bbr; }
static struct connection *inet_csk(struct sock *sk) {
    static struct connection x;
    x.icsk_ca_state = sk->ca_state;
    return &x;
}
static bool bbr_has_elapsed_in_phase(const struct sock *sk, u32 us) {
    return sk->time_elapsed && us == 500000;
}
'''
        tests = r'''
int main(void) {
    struct sock s = {0};
    struct rate_sample rs = {0};
    s.bbr.cycle_idx = BBR_BW_PROBE_CRUISE;
    s.bbr.rounds_since_probe = 4;
    s.bbr.loss_round_start = true;
    s.bbr.bw_lo = 1000;
    s.bbr.bw_latest = 1400;
    s.time_elapsed = true;
    rs.delivered = 4;
    rs.interval_us = 50000;
    if (!bbr_fast_reprobe_ready(&s, &rs)) return 1;
    s.bbr.loss_in_round = true;
    if (bbr_fast_reprobe_ready(&s, &rs)) return 2;
    s.bbr.loss_in_round = false;
    s.bbr.ecn_in_round = true;
    if (bbr_fast_reprobe_ready(&s, &rs)) return 3;
    s.bbr.ecn_in_round = false;
    s.bbr.prev_probe_too_high = true;
    if (bbr_fast_reprobe_ready(&s, &rs)) return 11;
    s.bbr.prev_probe_too_high = false;
    s.bbr.stopped_risky_probe = true;
    if (bbr_fast_reprobe_ready(&s, &rs)) return 12;
    s.bbr.stopped_risky_probe = false;
    s.bbr.cycle_idx = 1;  /* drain is forbidden */
    if (bbr_fast_reprobe_ready(&s, &rs)) return 4;
    s.bbr.cycle_idx = BBR_BW_PROBE_CRUISE;
    s.bbr.bw_latest = 1050;
    if (bbr_fast_reprobe_ready(&s, &rs)) return 5;
    s.bbr.bw_latest = 1400;
    s.ca_state = 1;
    if (bbr_fast_reprobe_ready(&s, &rs)) return 6;
    s.ca_state = 0;
    rs.is_retrans = true;
    if (bbr_fast_reprobe_ready(&s, &rs)) return 7;
    rs.is_retrans = false;
    rs.is_app_limited = true;
    if (bbr_fast_reprobe_ready(&s, &rs)) return 8;
    rs.is_app_limited = false;
    s.bbr.bw_lo = ~0U;
    if (bbr_fast_reprobe_ready(&s, &rs)) return 9;
    s.bbr.bw_lo = 1000;
    s.time_elapsed = false;
    if (bbr_fast_reprobe_ready(&s, &rs)) return 10;
    puts("Fast Recovery gate OK: 10 positive/negative checks");
    return 0;
}
'''
        with tempfile.TemporaryDirectory() as td:
            test_c = Path(td) / 'verify.c'
            test_exe = Path(td) / 'verify'
            test_c.write_text(header + helper + tests)
            subprocess.run(['cc', '-std=c11', '-O2', '-Wall', '-Wextra', '-Werror',
                            str(test_c), '-o', str(test_exe)], check=True, capture_output=True)
            subprocess.run([str(test_exe)], check=True, capture_output=True)


if __name__ == '__main__':
    unittest.main()

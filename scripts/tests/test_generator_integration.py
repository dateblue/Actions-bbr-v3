#!/usr/bin/env python3
"""Generator-level static test: use real Max/Extreme/Fast Recovery scripts."""
from pathlib import Path
import hashlib
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


def bbr_fixture():
    # Keep all current Max-profile constants so the complete generator executes.
    u32 = [
        'probe_rtt_win_ms', 'probe_rtt_cwnd_gain', 'probe_rtt_mode_ms',
        'tso_rtt_shift', 'cwnd_min_target', 'full_bw_thresh', 'full_bw_cnt',
        'extra_acked_max_us', 'ecn_max_rtt_us', 'beta', 'ecn_alpha_gain',
        'ecn_alpha_init', 'ecn_factor', 'ecn_thresh', 'ecn_reprobe_gain',
        'loss_thresh', 'full_loss_cnt', 'full_ecn_cnt', 'inflight_headroom',
        'bw_probe_cwnd_gain', 'bw_probe_max_rounds', 'bw_probe_rand_rounds',
        'bw_probe_base_us', 'bw_probe_rand_us',
    ]
    int_fields = ['pacing_margin_percent', 'startup_pacing_gain',
                  'startup_cwnd_gain', 'drain_gain', 'extra_acked_gain']
    bool_fields = ['precise_ece_ack', 'loss_probe_recovery']
    result = '#define BBR_VERSION 3\n#define bbr_param(sk, name) (bbr_ ## name)\n'
    result += ''.join(f'static const u32 bbr_{name} = 0;\n' for name in u32)
    result += ''.join(f'static const int bbr_{name} = 0;\n' for name in int_fields)
    result += ''.join(f'static const bool bbr_{name} = false;\n' for name in bool_fields)
    # The Max script deliberately uses a two-space anchor for this field.
    result += 'static const int bbr_cwnd_gain  = 0;\n'
    result += '''static const int bbr_pacing_gain[] = {
        BBR_UNIT,
        BBR_UNIT,
};
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
static void dummy(void) {}
static int tcp_bbr_check_kfunc_ids;
static int tcp_bbr_kfunc_set;
static struct tcp_congestion_ops tcp_bbr_cong_ops = { .name = "bbr", };
MODULE_DESCRIPTION("BBRv3");
'''
    return result


class GeneratorIntegrationTest(unittest.TestCase):
    def test_generator_keeps_base_untouched(self):
        for name in ('create-bbrv3plus.sh', 'apply-bbrv3-max-profile.sh',
                     'apply-bbrv3-extreme-profile.sh'):
            if not (ROOT / 'scripts' / name).exists():
                self.fail('merge overlay into a full repository; missing scripts/' + name)
        with tempfile.TemporaryDirectory() as td:
            tree = Path(td)
            (tree / 'net/ipv4').mkdir(parents=True)
            base = tree / 'net/ipv4/tcp_bbr.c'
            base.write_text(bbr_fixture())
            base_sha = hashlib.sha256(base.read_bytes()).hexdigest()
            (tree / 'net/ipv4/Makefile').write_text(
                'obj-$(CONFIG_TCP_CONG_BBR) += tcp_bbr.o\n')
            (tree / 'net/ipv4/Kconfig').write_text(
                'choice\n\tprompt "Default TCP congestion control"\nendchoice\n')
            result = subprocess.run(['bash', str(ROOT / 'scripts/create-bbrv3plus.sh')],
                                    cwd=tree, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertEqual(hashlib.sha256(base.read_bytes()).hexdigest(), base_sha)
            plus = (tree / 'net/ipv4/tcp_bbrplus.c').read_text()
            self.assertIn('bbrplus_fast_reprobe_ready', plus)
            self.assertEqual(plus.count('BBRPLUS_FAST_RECOVERY'), 1)
            self.assertIn('bbrplus_ ## name', plus)
            self.assertNotIn('bbr_ ## name', plus)
            self.assertIn('.name = "bbrv3plus"', plus)
            self.assertIn('BBR_UNIT * 7 / 2;', plus)
            self.assertIn('BBR_UNIT * 37 / 20,', plus)
            self.assertIn('obj-$(CONFIG_TCP_CONG_BBRPLUS)',
                          (tree / 'net/ipv4/Makefile').read_text())


if __name__ == '__main__':
    unittest.main()

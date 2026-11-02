# BBRv3 Plus Extreme Slim — consolidated Fast Recovery release candidate

Target branch: `dateblue/Actions-bbr-v3`, `bbrv3-extreme`; parent tested commit `a49a6b7`.

## Scope, with hard boundaries

- The original `tcp_bbr.c` remains byte-for-byte unchanged by the Plus generator.
- In `tcp_bbrplus.c`, retain v0.2 gains: STARTUP 3.50/3.00, ProbeBW UP 1.85, REFILL 1.50, normal cwnd gain 3.00. No unvalidated increase to these gains.
- `BBRPLUS_FAST_RECOVERY` adds an early **standard** `REFILL -> UP` decision **only** when an already-loss-limited connection in ProbeBW CRUISE has a newly valid, clean-delivery rebound (>12.5% over `bw_lo`), at least 4 packet-timed rounds and 500 ms since the previous probe. No new per-socket state, eBPF, qdisc or custom timer.
- Existing TCP loss response, ECN, inflight bound and TLP machinery are preserved. No change to kernel UDP/QUIC congestion-control semantics.
- Brutal 2.0.1 stays independent (out-of-tree official DKMS), and existing `congctl lock brutal` routes keep priority over the default TCP algorithm.
- Existing Oracle A1 `apply-oracle-a1-slim.sh` is retained. Do **not** remove boot/storage/network/virtio drivers on the basis of assumptions.

## Build flow

- `push`: GitHub ARM64 job runs checkout, BBR/Plus object compilation, actual **three official Brutal C objects** via the correct absolute `M=<brutal-src>` path; **does not** invoke `bindeb-pkg`.
- `workflow_dispatch`: defaults to `check`. Set `build_mode=release` only after a green push preflight and source review.
- Release: preflight again, then one full `bindeb-pkg`, then immediate independent upload of `linux-image-*.deb` and `linux-headers-*.deb`, then verify DEBs and build/check official Brutal `.ko` ABI.
- A failure in final `brutal.ko` validation does **not** discard successfully created kernel DEBs.

## Checks performed during overlay authoring

- `bash -n` over scripts; PyYAML parse of workflow; Python compile.
- Python fixture tests for single anchored insertion, reject unknown/duplicate source, and C-compiled Fast Recovery predicate with positive and negative test cases.
- Fake pinned-module/Kbuild end-to-end regression test: `M=` and relative object targets, plus mock ABI and artifact copy.
- Local Linux kernel headers Kbuild smoke: `M=/absolute/path brutal_cc.o brutal_sockopt.o brutal_rules.o` compiles, while passing absolute filenames as targets fails.

## Checks that remain REQUIRED before production rollout

This overlay **has not** been compiled against the actual Linux 7.3.1 ARM64 kernel in this workspace; the runtime here has no network access to fetch the full Linux source tree. It has **not** been booted on Oracle A1 and throughput gains are **not** proven. The new GitHub `push` preflight is designed to catch this before the hour-long release build.

1. Apply overlay to a clean `bbrv3-extreme` working tree based on `a49a6b7`.
2. `git diff --check` and `bash -n` (WSL/Linux or CI).
3. Push to the development branch; wait only for the fast **preflight** check to pass, or use the default manual `check` mode.
4. Review the diff on the generated `tcp_bbrplus.c` and verify `tcp_bbr.c` SHA256 remains unchanged.
5. Run a single manual `release` if preflight is green. After artifact download, verify both DEB packages, install without changing permanent GRUB default, and one-time boot on test instance with recovery console.
6. Do not treat Fast Recovery as confirmed faster until measuring repeated goodput, RTT and retransmissions with no Brutal rule covering the test TCP socket.

## Known limitations

- The early re-probe opportunity is small because the previous v0.2 Normal ProbeBW timer is already 750–1000 ms: this gate lowers it to about 500 ms **only when backed by a positive recovery signal**.
- It does not guarantee high throughput on a path with severe continuing loss or application-side throttling. This is deliberately conservative under persistent congestion.
- This is an experimental congestion-control change; retain the original `bbr` and already-installed kernel boot fallback.

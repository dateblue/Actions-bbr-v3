# QUIC BBRv3 Plus: separate sing-box implementation, not kernel support

This file is a design contract, NOT an implemented QUIC congestion controller.

* TCP routing: `congctl lock brutal` on configured prefixes, `bbrv3plus` as the
  default on other new connections. Do not run two TCP CC algorithms per flow.
* QUIC for HY2/TUIC: congestion control lives in the user-space QUIC stack.
  The kernel BBRv3 Plus code cannot control UDP. A QUIC BBRv3 Plus needs a
  separate user-space controller in dateblue/intel, compatible with the exact
  vendored quic-go API used there.
* QUIC options should be explicit per inbound/outbound:
  `brutal` with known target rate, `bbr` fallback, `bbrv3plus` experimental.
* No automatic per-packet CC switching. If future selection is implemented,
  switch at NEW session creation and use hysteresis based on sustained goodput
  vs configured rate, excessive loss, and queueing delay. Preserve existing
  sessions and do not infer link capacity from one 30-second benchmark.
* Shared kernel/user space interface is NOT assumed; QUIC code needs its own
  pacing, ACK sampling, loss, inflight, ECN and recovery tests.
* Mandatory before release: unit tests on QUIC ACK/loss timing; integration
  tests for HY2 and TUIC; rollback to current controller after failures.

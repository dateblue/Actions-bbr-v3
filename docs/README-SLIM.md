# BBRv3 Plus Extreme Slim v0.2 — experiment

Targets official Linux stable 7.3.1 as of 2026-11-02. Does NOT include a new
Linux source tree or change base `tcp_bbr.c`. The only modified CC implementation
is a private, independently registered `bbrv3plus` copy.

* `bbr`: upstream byJoey BBRv3 (unaltered)
* `bbrv3plus`: private BBRv3 Plus Extreme v0.2 (pacing 3.50 startup, cwnd 3.0,
  ProbeBW UP 1.85, refill 1.50; keep Max loss, inflight, ECN safeguards)
* `brutal`: official module supplied through DKMS on the actual VM; CI also
  builds official, pinned v2.0.1 to check Linux source compatibility.
* Conservative A1 slim removes desktop display / media / sound / WLAN /
  Bluetooth / RDMA subsystems. It intentionally retains EFI, SCSI, NVMe,
  VirtIO, TCP/IP, WireGuard, TUN, netfilter, BPF and serial console support.
* New kernel suffix `-bbrv3plus-slim` prevents overwriting the already proven
  `7.3.1-bbrv3plus-extreme` and `7.3.1-joeyblog-bbrv3-max` installations.
* Original build.yml is unchanged; the experimental build remains separately
  triggered by the `bbrv3-extreme` branch.
* DO NOT install without checking .config, .deb metadata, DKMS, initramfs,
  boot menu, and cloud serial console rollback. The profile has not yet passed
  an actual ARM64 kernel build or boot test.

Not included: QUIC BBRv3 Plus implementation. See QUIC-BBRV3PLUS-DESIGN.md.

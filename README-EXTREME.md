# BBRv3 Plus Extreme: dual-algorithm proof-of-build

Overlay these files into the dateblue/Actions-bbr-v3 `bbrv3-extreme` branch. Keep the already-created `scripts/apply-bbrv3-extreme-profile.sh` and `integrations/tcp-brutal/COMMIT` files.

The build script applies BBRv3 v3 port once, **copies** `tcp_bbr.c` to `tcp_bbrplus.c`, applies Max and Extreme parameters **only** to the copy, namespaces private callback names, registers `bbrv3plus`, adds Kconfig/Makefile entries, builds both algorithms as built-in, and produces ARM64 Linux DEBs.

This is an **experimental first build**, not yet proven against the exact Linux 7.3.1 patched tree. GitHub Actions must compile successfully and an offline/VM test should demonstrate both entries in `/proc/sys/net/ipv4/tcp_available_congestion_control` before installing on a production Oracle VPS.

The `tcp-brutal` integration is intentionally **not built in this stage**. It will be built separately against the new kernel's matching headers after the dual algorithm build is verified.

Because the workflow has a push trigger for the `bbrv3-extreme` branch, pushing it can launch the ARM64 test build without needing the workflow to exist on the default branch first. No GitHub Release is published.

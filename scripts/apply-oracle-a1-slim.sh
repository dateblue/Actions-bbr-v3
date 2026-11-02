#!/usr/bin/env bash
set -euo pipefail

# Run inside the target ARM64 kernel source tree after prepare-kernel-config.sh
# and after enabling CONFIG_TCP_CONG_BBRPLUS=y. Conservative Oracle A1 profile:
# remove bulk desktop/physical-device subsystems, NOT storage, EFI, networking,
# WireGuard, TUN, netfilter, virtualization, serial consoles, USB/HID or BPF.
[[ -f .config && -x scripts/config ]] || {
  echo 'ERROR: run in configured Linux kernel tree' >&2; exit 1;
}

for item in DRM MEDIA_SUPPORT SOUND INFINIBAND WLAN BT CAN NFC IEEE802154; do
  scripts/config --disable "$item"
done

make ARCH=arm64 olddefconfig < /dev/null

for item in DRM MEDIA_SUPPORT SOUND INFINIBAND WLAN BT; do
  grep -qx "# CONFIG_${item} is not set" .config || {
    echo "ERROR: CONFIG_${item} not disabled after olddefconfig" >&2; exit 1;
  }
done

# Oracle A1 critical requirements: do not make a build that could omit the
# boot block/network drivers or the two congestion-control algorithms.
for item in ACPI PCI SCSI BLK_DEV_SD BLK_DEV_NVME VIRTIO_PCI VIRTIO_BLK \
            VIRTIO_NET EFI EXT4_FS NET_SCH_FQ TCP_CONG_BBR TCP_CONG_BBRPLUS; do
  grep -qx "CONFIG_${item}=y" .config || {
    echo "ERROR: required CONFIG_${item}=y missing after slimming" >&2; exit 1;
  }
done

# Runtime features needed by the deployed VPN/proxy workload.
for item in TUN NETFILTER BPF; do
  grep -qx "CONFIG_${item}=y" .config || {
    echo "ERROR: required CONFIG_${item}=y missing after slimming" >&2; exit 1;
  }
done

echo 'Oracle A1 conservative Slim config verified.'

# ib_info.sh — CSV Field Reference

Each row output by `ib_info.sh` contains 10 double-quoted, comma-separated fields.
One row is produced per unique Mellanox card on the node. Nodes without any
Mellanox hardware produce a single row with `UNAVAILABLE` for the card-specific
fields (6–10).

---

## Field 1: Hostname

| Item | Value |
|------|-------|
| Source | `hostname` command |
| Fallback | `UNAVAILABLE` if `hostname` fails |
| Example | `node001` |

The short hostname of the node running the script.

---

## Field 2: Serial Number

| Item | Value |
|------|-------|
| Source | `dmidecode -t1` → `Serial Number` field |
| Fallback | `UNAVAILABLE` if dmidecode is missing or returns empty |
| Example | `ABCDEF1` |

The chassis serial number as reported by the system BIOS/UEFI. Requires root
privileges. On VMware VMs this returns the VM's UUID-derived serial.

---

## Field 3: Model

| Item | Value |
|------|-------|
| Source | `dmidecode -t1` → `Product Name` field |
| Fallback | `UNAVAILABLE` if dmidecode is missing or returns empty |
| Example | `PowerEdge R750` |

The server product name from the BIOS/UEFI. On VMware VMs this returns
`VMware Virtual Platform` or similar.

---

## Field 4: OS

| Item | Value |
|------|-------|
| Source | `lsb_release -d` (preferred), then `/etc/os-release` `PRETTY_NAME` |
| Fallback | `UNAVAILABLE` if neither source is available |
| Example | `Rocky Linux 9.7 (Blue Onyx)` |

The distribution name and version. The script tries `lsb_release` first because
it produces a cleaner single-line description, then falls back to `os-release`.

---

## Field 5: Kernel

| Item | Value |
|------|-------|
| Source | `uname -r` |
| Fallback | `UNAVAILABLE` if `uname` fails |
| Example | `5.14.0-503.21.1.el9_5.aarch64` |

The running kernel release string.

---

## Field 6: Mellanox Card Model

| Item | Value |
|------|-------|
| Source | `lspci` — full device description after the bus/type prefix |
| Fallback | `UNAVAILABLE` if no Mellanox devices found in `lspci` output |
| Example | `Mellanox Technologies MT27800 Family [ConnectX-5]` |

The full PCI device description for each unique Mellanox card. Dual-port cards
sharing the same PCI bus:slot are deduplicated — only one row is produced.

The script strips the PCI slot and device-class prefix from the `lspci` line,
keeping everything after the second colon (e.g., `3b:00.0 InfiniBand: Mellanox
Technologies MT27800 Family [ConnectX-5]` becomes `Mellanox Technologies MT27800
Family [ConnectX-5]`).

---

## Field 7: Driver Type

| Item | Value |
|------|-------|
| Source | `rpm -qa` — checks for `mlnx` InfiniBand packages |
| Values | `MOFED` or `Linux OFED` |
| Example | `MOFED` |

If any installed RPM matching `infiniband` contains `mlnx` in its name, the
driver stack is Mellanox OFED (MOFED). Otherwise it is the inbox Linux OFED
driver.

---

## Field 8: Installed OFED

| Item | Value |
|------|-------|
| Source | `ofed_info -s` |
| Fallback | `UNAVAILABLE` if `ofed_info` is not installed or returns empty |
| Example | `MLNX_OFED_LINUX-5.8-4.1.5.0:` |

The OFED version string as reported by the `ofed_info` utility. This reflects
what is installed on disk, which may differ from what the kernel has loaded if
OFED was recently upgraded without a reboot.

---

## Field 9: Loaded OFED

| Item | Value |
|------|-------|
| Source | `/sys/module/mlx5_core/version` |
| Fallback | `UNAVAILABLE` if the mlx5_core module is not loaded |
| Example | `5.8-4.1.5` |

The version of the `mlx5_core` kernel module currently loaded. When this differs
from the installed OFED version (field 8), the script logs a mismatch warning —
a reboot or `systemctl restart openibd` is likely needed.

---

## Field 10: Firmware Version

| Item | Value |
|------|-------|
| Source | `ethtool -i <interface>` → `firmware-version` field |
| Fallback | `UNAVAILABLE` if no network interface can be resolved for the card |
| Example | `20.31.1014 (MT_0000000225)` |

The HCA firmware version as reported by the network driver. The number in
parentheses is the Mellanox Board ID (PSID) — a unique identifier for the
specific OEM board variant. The PSID determines which firmware binary is
compatible with the card.

The script resolves the firmware by:
1. Matching the card's PCI slot to an IB device in `/sys/class/infiniband/`
2. Finding the network interface under that device's `device/net/` directory
3. Querying `ethtool -i` on that interface

If no direct match is found (e.g., sysfs paths don't resolve), the script falls
back to querying the first UP IB link and logs a warning that the firmware may
not correspond to the expected card on multi-rail nodes.

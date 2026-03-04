# ib_info.sh

Collect InfiniBand hardware and configuration details from cluster nodes running
RHEL 7+, RHEL 8+, Rocky 8+, or RHEL 9+ with Mellanox ConnectX adapters. Outputs one CSV row per
unique Mellanox card to stdout; errors and warnings are buffered in memory and
flushed to stderr as a labeled block at exit. No files are written on the node.

## Quick Start

Single node:

```bash
sudo ./ib_info.sh
```

Cluster-wide via `clush`:

```bash
clush -a 'sudo /shared/ib_tools/ib_info.sh' > cluster_ib.csv 2> cluster_ib_errors.log
```

Print the CSV header:

```bash
./ib_info.sh --header
```

## CSV Output Format

```
"Hostname","Serial Number","Model","OS","Kernel","Mellanox Card Model","Driver Type","Installed OFED","Loaded OFED","Firmware Version"
```

- One row per unique Mellanox card (dual-port cards produce one row, not two).
- Fields fall back to `UNAVAILABLE` when a tool is missing or a command fails;
  the script continues collecting whatever it can rather than aborting.

## Error Output Format (stderr)

```
=== IB_INFO ERRORS: node001 ===
[2026-02-21 19:18:47] node001 ERROR: No Mellanox cards found
[2026-02-21 19:18:47] node001 INFO:  Completed with 1 error(s), 0 warning(s)
=== END: node001 ===
```

When run via `clush`, each node's error block is tagged with the hostname so
blocks from different nodes can be separated in the aggregated stderr stream.

## Requirements

- **bash** 4.2+ (RHEL 7+, Rocky 8+, RHEL 8+, RHEL 9+)
- **lspci** (pciutils) — required, detects Mellanox cards
- **ethtool** — required, reads firmware version
- **dmidecode** — optional, reads chassis serial and model
- **ofed_info** — optional, reads installed OFED version
- **lsb_release** or `/etc/os-release` — optional, reads OS version
- Standard utilities: `hostname`, `ip`, `awk`, `sed`, `grep`, `uname`, `rpm`

Most commands must be run as root or with equivalent privileges.

## Installation

1. Copy the script to a shared path accessible from all cluster nodes (typically
   an NFS-mounted directory):

   ```bash
   chmod +x ib_info.sh
   sudo cp ib_info.sh /shared/ib_tools/
   ```

2. Run directly on a single node or broadcast with `clush`:

   ```bash
   # Single node
   sudo /shared/ib_tools/ib_info.sh

   # All nodes — CSV to file, errors to separate file
   clush -a 'sudo /shared/ib_tools/ib_info.sh' > cluster_ib.csv 2> cluster_ib_errors.log

   # Specific nodes
   clush -w node[001-010] 'sudo /shared/ib_tools/ib_info.sh' > cluster_ib.csv 2> cluster_ib_errors.log
   ```

## Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Success (or warnings only) |
| 1 | One or more errors logged (e.g., no Mellanox cards found) |

When broadcast via `clush`, the overall exit code is non-zero if any node returned 1.

## Troubleshooting

- **Permission errors:** run with `sudo` or as root — `dmidecode`, `ethtool`,
  and `lspci` require elevated privileges.
- **Missing commands:** install the missing packages (`pciutils`, `ethtool`,
  `dmidecode`). The script logs which tools are missing and continues with
  `UNAVAILABLE` for affected fields.
- **No Mellanox devices found:** verify the host has Mellanox adapters and that
  at least one IB link is up (`ip link`).
- **OFED version mismatch warning:** the installed OFED version differs from the
  loaded kernel module version — a reboot or `systemctl restart openibd` is
  likely needed.

## License

No license is provided in this repository. If you intend to share or publish
this script, please add a LICENSE file (e.g., MIT or Apache 2.0) to make
redistribution terms explicit.

## Contact

If you need help adapting the script to your environment, open an issue or
contact the repository owner.

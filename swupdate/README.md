# SWUpdate OTA for Raspberry Pi 5

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [SD Card Partition Layout](#sd-card-partition-layout)
3. [Update Flow — Step by Step](#update-flow--step-by-step)
4. [File Map](#file-map)
5. [Building an Update Package](#building-an-update-package)
6. [Delivering an Update](#delivering-an-update)
7. [Web UI Manual](#web-ui-manual)
8. [CLI Manual](#cli-manual)
9. [On-Device Manual](#on-device-manual)
10. [Rollback](#rollback)
11. [Customising the Update Package](#customising-the-update-package)
12. [Troubleshooting](#troubleshooting)

---

## Architecture Overview

```
┌──────────────────────────────────────────────────────────────────────┐
│                  Raspberry Pi 5  256 GB SD card                      │
│                                                                      │
│  ┌──────────┐  ┌────────────────┐  ┌────────────────┐  ┌──────────┐ │
│  │  p1/boot │  │  p2/rootfs-a   │  │  p3/rootfs-b   │  │  p4/data │ │
│  │  256 MB  │  │    8192 MB     │  │    8192 MB     │  │  ~238 GB │ │
│  │  FAT32   │  │    ext4        │  │    ext4        │  │   ext4   │ │
│  │          │  │  ← active →    │  │  ← standby →   │  │  /data   │ │
│  └──────────┘  └────────────────┘  └────────────────┘  └──────────┘ │
│       │                ▲                    ▲                        │
│  cmdline.txt      root=PARTUUID=…       written by                   │
│  selects slot     (current boot)        SWUpdate                     │
└──────────────────────────────────────────────────────────────────────┘
```

**A/B rootfs model** — the device always has two complete root filesystems:
- **Slot A** (`/dev/mmcblk0p2`, label `rootfs-a`) — factory-flashed active slot.
- **Slot B** (`/dev/mmcblk0p3`, label `rootfs-b`) — standby; SWUpdate writes the
  new image here while the system keeps running normally.

The `/boot` partition is shared. A single line in `/boot/cmdline.txt` determines
which slot is booted:

```
root=PARTUUID=<uuid-of-active-slot> ...
```

`post-install.sh` atomically rewrites that `root=` parameter to point at the
newly written slot, then the device reboots into it.

The `/data` partition (p4) is **never touched** by an OTA update. Mount it at
`/data` (or add an fstab entry) for anything that must survive updates: config
files, application state, certificates, logs.

---

## SD Card Partition Layout

| # | Label | Size | FS | Mount | Purpose |
|---|-------|------|----|-------|---------|
| p1 | `boot` | 256 MB | FAT32 | `/boot` | Firmware, kernel, DTBs, overlays, `cmdline.txt` |
| p2 | `rootfs-a` | 8192 MB | ext4 | `/` | Root filesystem — Slot A (active after factory flash) |
| p3 | `rootfs-b` | 8192 MB | ext4 | *(none)* | Root filesystem — Slot B (standby, target of next OTA) |
| p4 | `data` | ~238 GB (rest of card) | ext4 | `/data` | Persistent user / application data |

---

## Update Flow — Step by Step

```
Developer workstation                       Raspberry Pi 5
─────────────────────────────────────────────────────────────────────
make swu SWU_VERSION=1.2.3
  → gzip rootfs.ext4 to rootfs.ext4.gz
  → substitute @@VERSION@@ in sw-description
  → cpio-pack → rpi5-1.2.3.swu

Upload rpi5-1.2.3.swu  ──────────────────►  SWUpdate daemon receives .swu
(web UI :8080 or swupdate-client)
                                             1. Verify sw-description signature
                                                (if signing enabled)
                                             2. Run pre-install.sh
                                                • findmnt / to get active device
                                                • derive inactive device
                                                  (p2↔p3)
                                                • ln -sf <inactive> /dev/swupdate-inactive
                                             3. Stream rootfs.ext4.gz → raw write
                                                to /dev/swupdate-inactive
                                             4. Run post-install.sh
                                                • blkid → PARTUUID of new slot
                                                • remount /boot rw
                                                • sed root=PARTUUID in cmdline.txt
                                                • remount /boot ro
                                             5. postupdatecmd = /sbin/reboot
                                                (configured in swupdate.cfg)

                                             ── reboot ──

                                             Bootloader reads /boot/cmdline.txt
                                             → boots new slot

                                             swupdate-bootcheck.service runs
                                             → logs active slot to syslog
                                             → writes /run/swupdate-active-slot
```

---

## File Map

```
meta/meta-custom/
├── swupdate/                          ← .swu packaging sources (host-side)
│   ├── sw-description                 Template; @@VERSION@@ substituted by make swu
│   ├── pre-install.sh                 Copied verbatim into every .swu
│   └── post-install.sh                Copied verbatim into every .swu
│
└── recipes-swupdate/
    └── rpi5-swupdate-config/
        ├── rpi5-swupdate-config.bb    BitBake recipe
        └── files/
            ├── swupdate.cfg           libconfig runtime config (installed to /etc/swupdate/)
            ├── pre-install.sh         Installed to /usr/lib/swupdate/ on target
            ├── post-install.sh        Installed to /usr/lib/swupdate/ on target
            ├── swupdate-bootcheck.sh  Boot-slot logger (runs at sysinit)
            ├── swupdate-bootcheck.service
            └── swupdate-webui.conf    systemd drop-in for swupdate.service
                                       (enables Mongoose web server on :8080)
```

---

## Building an Update Package

### Prerequisites (host)

- A successful `make build` that produced `core-image-full-cmdline-raspberrypi5*.rootfs.ext4`
- `gzip` and `cpio` available on the host (standard on any Linux workstation)

### Commands

```bash
# Use the current timestamp as version (default)
make swu

# Explicit version string
make swu SWU_VERSION=1.2.3

# Override build dir
make swu BUILD_DIR=/opt/rpi5-build SWU_VERSION=2.0.0
```

The output is written to `build/rpi5-<version>.swu`.

### What `make swu` does internally

1. Finds the latest `*.rootfs.ext4` in `build/tmp/deploy/images/raspberrypi5/`.
2. gzip-compresses it to `build/swu/rootfs.ext4.gz`.
3. Substitutes `@@VERSION@@` in `meta/meta-custom/swupdate/sw-description` → `build/swu/sw-description`.
4. Copies `pre-install.sh` and `post-install.sh` into `build/swu/`.
5. Packs the four files in the required cpio order:
   ```
   sw-description   ← must be first — SWUpdate reads it before anything else
   pre-install.sh
   post-install.sh
   rootfs.ext4.gz
   ```
6. Writes `build/rpi5-<version>.swu`.

---

## Delivering an Update

### Web UI

1. Find the device IP: `ping raspberrypi5.local` or check your router DHCP leases.
2. Open `http://<device-ip>:8080` in a browser.
3. The SWUpdate React front-end (`swupdate-www`) loads.
4. Drag-and-drop `build/rpi5-<version>.swu` onto the upload area, or click
   **Select file** and choose it.
5. Click **Start update**.
6. Progress is shown in real time via a WebSocket. When it reaches 100% the
   device reboots automatically (controlled by `postupdatecmd` in `swupdate.cfg`).

### CLI — `swupdate-client` (from the host)

`swupdate-client` is part of the SWUpdate project and can be installed via your
distro package manager or built from source.

```bash
# Basic push
swupdate-client <device-ip> build/rpi5-1.2.3.swu

# Verbose progress
swupdate-client -v <device-ip> build/rpi5-1.2.3.swu

# Custom port (if you changed the Mongoose port)
swupdate-client -p 8080 -v <device-ip> build/rpi5-1.2.3.swu
```

Exit code `0` = success, non-zero = failure (check stderr / device logs).

### curl — direct HTTP multipart POST

If `swupdate-client` is not available you can push with `curl`:

```bash
curl -X POST http://<device-ip>:8080/upload \
     -F "file=@build/rpi5-1.2.3.swu"
```

---

## Web UI Manual

The built-in web interface is served by the Mongoose HTTP server embedded in
`swupdate` (enabled via `PACKAGECONFIG += "webserver"`). The React front-end
(`swupdate-www`) is served from `/usr/share/swupdate/www/`.

| URL | Description |
|-----|-------------|
| `http://<ip>:8080` | Upload page — drag-and-drop or file picker |
| `http://<ip>:8080/api/v1/versioning` | JSON: software + hardware version |
| `http://<ip>:8080/api/v1/sw-components` | JSON: installed SW components |

**Update steps via web UI:**

1. Navigate to `http://<ip>:8080`.
2. The page shows the current installed version (from `swupdate.cfg`).
3. Drop the `.swu` file or use the **Select file** button.
4. Click **Start update**. A progress bar and live log appear.
5. On completion the daemon logs "SUCCESS" and triggers the configured
   `postupdatecmd` (default: `/sbin/reboot`).
6. After reboot, reload the page and verify the version number changed.

**To disable auto-reboot** (for testing):
```bash
# On the device:
sed -i 's|postupdatecmd.*|# postupdatecmd disabled;|' /etc/swupdate/swupdate.cfg
systemctl restart swupdate
```

---

## CLI Manual

### On the device

```bash
# Check running SWUpdate version
swupdate --version

# Read the live progress socket
swupdate-progress

# Apply a local .swu file (e.g. copied via scp)
swupdate -v -i /tmp/rpi5-1.2.3.swu

# Dry-run (parses + validates sw-description but does not flash)
swupdate -v --dry-run -i /tmp/rpi5-1.2.3.swu

# Query active slot (written by swupdate-bootcheck.service at boot)
cat /run/swupdate-active-slot
```

### On the host

```bash
# Send and monitor interactively
swupdate-client -v <ip> build/rpi5-1.2.3.swu

# Non-interactive (scriptable) — exit code reflects success/failure
swupdate-client <ip> build/rpi5-1.2.3.swu && echo OK || echo FAILED

# Check installed version via REST API
curl -s http://<ip>:8080/api/v1/versioning | python3 -m json.tool
```

---

## On-Device Manual

### systemd services

```bash
# Status of the SWUpdate daemon
systemctl status swupdate

# View logs
journalctl -u swupdate -f

# Restart daemon (e.g. after editing swupdate.cfg)
systemctl restart swupdate

# Status of the boot-check service
systemctl status swupdate-bootcheck
journalctl -u swupdate-bootcheck
```

### Inspect partition layout

```bash
# Show partition table
lsblk -o NAME,SIZE,FSTYPE,LABEL,MOUNTPOINT,PARTUUID /dev/mmcblk0

# Show active root device
findmnt -n -o SOURCE /

# Show current cmdline.txt slot selection
cat /boot/cmdline.txt | grep -o 'root=PARTUUID=[^ ]*'
```

### Manually switch slot (emergency)

If you need to revert to the previous slot without an OTA:

```bash
# Identify target slot PARTUUID
lsblk -o NAME,PARTUUID /dev/mmcblk0

# Edit cmdline.txt
mount -o remount,rw /boot
sed -i 's|root=PARTUUID=<current-uuid>|root=PARTUUID=<other-uuid>|' /boot/cmdline.txt
mount -o remount,ro /boot
reboot
```

---

## Rollback

The current implementation does **not** perform automatic rollback (no boot
counter / watchdog integration). Manual rollback procedure:

1. Boot into the previous slot by editing `/boot/cmdline.txt` (see above).
2. From the previous slot, run `make swu` to generate a new package and push it
   via web UI or CLI.

To add automatic rollback, a typical approach is:

1. Store a `boot_tries` counter in a dedicated small FAT partition or in a U-Boot
   environment (requires U-Boot, not the default RPi firmware bootloader).
2. In the initramfs (or early `ExecStartPre` in a high-priority systemd unit),
   decrement the counter; if it reaches zero, run `post-install.sh` pointing back
   at the previous slot's PARTUUID.
3. `swupdate-bootcheck.service` plays the role of "boot confirmed" — set the
   counter back to its initial value here.

---

## Customising the Update Package

### Partial update (config files only, no rootfs flash)

Edit `meta/meta-custom/swupdate/sw-description` — remove the `images:` block,
keep only the `scripts:` block, and add a `files:` section:

```
files: (
    {
        filename    = "my-app.conf";
        path        = "/etc/my-app/my-app.conf";
        type        = "rawfile";
        sha256      = "<sha256sum of the file>";
    }
);
```

### Signing packages (recommended for production)

SWUpdate supports RSA / CMS signatures. High-level steps:

```bash
# Generate key pair (one-time, keep private key offline)
openssl genrsa -out swupdate-priv.pem 4096
openssl req -new -x509 -key swupdate-priv.pem -out swupdate-cert.pem

# Sign the sw-description
openssl smime -sign -in sw-description -out sw-description.sig \
    -signer swupdate-cert.pem -inkey swupdate-priv.pem \
    -nodetach -outform DER

# Add to cpio (sw-description.sig must immediately follow sw-description)
printf 'sw-description\nsw-description.sig\n...' | cpio -ov -H newc > signed.swu
```

On the device, add to `swupdate.cfg`:
```
security: { sigtype = "cms"; certfile = "/etc/swupdate/swupdate-cert.pem"; };
```

Rebuild and deploy the device image with the cert baked in.

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---------|--------------|-----|
| Web UI unreachable | `swupdate` not running | `systemctl start swupdate; journalctl -u swupdate` |
| Upload succeeds but nothing happens | `postupdatecmd` disabled or wrong path | Check `/etc/swupdate/swupdate.cfg` |
| Device boots old slot after update | `post-install.sh` failed to edit `cmdline.txt` | Check `journalctl -u swupdate`; verify `/boot` was mounted rw |
| `do_package` error about `swupdate.service` | Recipe listed foreign unit in `SYSTEMD_SERVICE` | Only list units installed by the recipe itself |
| `cpio: File ... truncated` | `.swu` built with wrong order | `sw-description` must be the **first** file in the archive |
| `swupdate-client: connection refused` | Wrong port or firewall | Default port is `8080`; check `swupdate-webui.conf` |
| `pre-install.sh: unexpected active device` | Running from non-mmcblk0 media (USB boot) | Edit `pre-install.sh` device paths to match your setup |

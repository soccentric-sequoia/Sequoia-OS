# Sequoia-OS

## Project Summary

Sequoia-OS is the Yocto-layer and image-integration repository for Sequoia Intel x86 targets. Its
documented active path customizes a full command-line image, selects the Sequoia WIC layout,
integrates SWUpdate, initializes the persistent home partition on first boot, and installs
connectivity defaults for Ethernet, WiFi, VLAN, and resolver behavior. The image layout uses EFI/GPT
with an active `rootfs-a`, an OTA target `rootfs-b`, and persistent `/home`; update scripts select
slots by filesystem labels rather than fixed device names. The repository includes Make helpers,
configuration and layer metadata, changelog and repository-map documentation, and legacy Raspberry
Pi recipes retained for reference.

The target metadata identifies the scarthgap Yocto series and LattePanda as a reference board. This
is image/build integration, not a complete board support package: successful boot, network
provisioning, partition growth, SWUpdate rollback, and package availability depend on the configured
build environment and hardware. The active Sequoia recipe path should be preferred over legacy
Raspberry Pi material. No automated test files were found in the repository inventory, so the
feature table records command/configuration evidence and leaves runtime behavior for manual review.
Build commands, layer dependencies, machine selection, and artifact inspection should be captured by
future CI.

The repository is the integration point between Yocto metadata and the target's boot/update policy.
It does not replace hardware acceptance work in Sequoia-HAL or the board inventory currently absent
from Sequoia-Hardware. Image reproducibility, bootloader settings, signed update policy, and
power-loss recovery should be documented when they become release requirements.

## Feature Inventory

| # | Name / Description | Implemented? | Test Coverage? | Manual Test |
| --- | --- | --- | --- | --- |
|   1 | Sequoia Yocto layer metadata and image customization   | Implemented  | No automated tests found      | [ ] Manual verification required |
|   2 | Sequoia Intel machine/image path                       | Implemented  | Configuration inspection only | [ ] Manual verification required |
|   3 | EFI/GPT A/B WIC partition layout                       | Implemented  | No automated tests found      | [ ] Manual verification required |
|   4 | SWUpdate runtime configuration and slot helpers        | Implemented  | No automated tests found      | [ ] Manual verification required |
|   5 | First-boot `/home` expansion and initialization        | Implemented  | No automated tests found      | [ ] Manual verification required |
|   6 | Ethernet/WiFi/VLAN/resolver defaults                   | Implemented  | No automated tests found      | [ ] Manual verification required |
|   7 | Persistent `/home` across OTA updates                  | Implemented  | No automated tests found      | [ ] Manual verification required |
|   8 | Legacy Raspberry Pi recipe compatibility               | Partial      | No automated tests found      | [ ] Manual verification required |
|   9 | Reproducible image build and artifact publication      | Unknown      | No CI test found              | [ ] Manual verification required |
|  10 | Boot, OTA rollback, and recovery on reference hardware | Unknown      | No runtime tests found        | [ ] Manual verification required |

## Validation

Use the repository `Makefile` and Yocto/Kas configuration to build the image. Inspect the generated
WIC and SWUpdate artifacts, then exercise first boot, networking, A/B update, rollback, and
persistence on a Sequoia target.

## Primary Target

- Platform: Sequoia Intel x86
- Reference board: LattePanda
- Yocto series: scarthgap

## Key Components

- `recipes-core/images/core-image-full-cmdline.bbappend`
  - Adds Sequoia packages and hardware tooling.
  - Sets Intel x86 WIC file overrides to `sequoia-intel.wks`.
- `recipes-swupdate/sequoia-swupdate-config/`
  - SWUpdate runtime configuration and A/B helper scripts.
- `recipes-core/sequoia-home-init/`
  - First-boot `/home` expansion and user-home initialization.
- `recipes-connectivity/sequoia-connectivity/`
  - systemd-networkd defaults for Ethernet/WiFi VLAN and resolver preset.
- `wic/sequoia-intel.wks`
  - EFI GPT image layout with A/B rootfs and persistent `/home`.

## A/B Layout (Sequoia Intel)

- `p1` `/boot` (EFI FAT32)
- `p2` `/` (`rootfs-a`, active initially)
- `p3` standby (`rootfs-b`, OTA target)
- `p4` `/home` (persistent, grown on first boot)

SWUpdate scripts switch slots using filesystem labels (`rootfs-a`/`rootfs-b`) instead of hardcoded
block device names.

## Notes

Legacy Raspberry Pi 5 recipes are still present in this repository for reference, but the active
image path now uses Sequoia Intel recipes.

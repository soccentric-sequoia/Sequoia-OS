# Sequoia-OS Build and Deployment

## Scope

Sequoia-OS is the Intel x86/LattePanda Yocto image build. The Makefile wraps
the pinned KAS 4.5 container script and `kas/boards/sequoia.yaml`, builds the
`core-image-full-cmdline` image, stages WIC/SDK/eSDK artifacts, creates SWUpdate
OTA packages, and optionally flashes a block device.

## 1. Prerequisites

- Docker, `curl`, `make`, `openssl`, `cpio`, `bmaptool`, and enough disk for
  Yocto downloads/sstate/build output.
- Network access to download the pinned KAS container and Yocto layers on the
  first build. SSH material may be used through `KAS_SSH_DIR`.
- A valid board file. The checked-in default is `BOARD=sequoia`, whose machine
  is derived from `kas/boards/sequoia.yaml`.

```sh
make help
make kas-container-script       # download pinned kas-container if absent
make kas-image                   # build the KAS Docker image
```

## 2. Setup

## 3. Build

```sh
make build                       # same image path as make image
make image sequoia
make rebuild-image sequoia       # cleans the image recipe state first
make shell sequoia               # interactive KAS shell
```

Override `BOARD`, `IMAGE_TARGET`, `BUILD_DIR`, `CACHE_DIR`, `DL_DIR`, or
`SSTATE_DIR` when needed. `make all` is the default alias for `build`.

## 4. Test and lint

There is no test target in this Makefile. Validate image metadata and recipes
through the KAS/BitBake build and perform the manual boot/acceptance checks
listed below. No automated lint command is declared in this leaf.

## 5. Artifacts

```sh
make sdk sequoia                # Yocto SDK installer, staged under deploy/sdk
make esdk sequoia               # extensible SDK, staged under deploy/esdk
make sdk-image sequoia          # SDK plus Docker image and deployment staging
make esdk-image sequoia
make swu sequoia SWU_VERSION=1.2.3
```

Build output is under `build/`; image deployment staging is under
`deploy/images/<board>_<timestamp>/`. SDK/eSDK installers are staged under
`deploy/sdk/` and `deploy/esdk/`. SWU output is
`build/<board>-<version>.swu` and is copied to `deploy/swu/`. SWU signing is
conditional: if `swupdate/keys/swupdate-private.pem` exists, the package is
RSA-signed; otherwise it is explicitly unsigned.

## 6. Deploy, install, and run

```sh
make deploy-images sequoia
make deploy-sdk sequoia
make deploy-esdk sequoia
make deploy-swu sequoia SWU_VERSION=1.2.3
make flash sequoia DEVICE=/dev/sdX  # destructive hardware operation
```

`DEVICE` must be an actual block device and `flash` uses `bmaptool`; verify the
device path carefully. These targets stage local artifacts or write removable
media. No cloud deployment target is defined.

## 7. Cleanup

```sh
make clean                       # remove build/
make clean-docker                # remove KAS, SDK, and eSDK images
make clean-all                   # build plus downloads and sstate cache
```

## 8. Verification caveats

The KAS build targets the Intel `genericx86-64`/LattePanda profile and does not
prove boot, A/B behavior, systemd services, SWUpdate acceptance, or peripheral
operation. `flash` is conditional and potentially destructive; verify media,
checksum, boot mode, console, networking, and OTA rollback manually on real
hardware. Keep the private signing key out of source control.
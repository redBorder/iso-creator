# redBorder NG ISO Creator

This project provides an automated script to generate a customized redBorder ISO based on Rocky Linux 9. The resulting ISO includes a predefined redBorder product type (e.g., manager, IPS, intrusion, or proxy), custom splash images, and a local package repository.

# Examples

![boot](./assets/1.png)
![preinstall](./assets/3.png)
![install](./assets/2.png)

## Author

**Miguel Álvarez**  
<malvarez@redborder.com>

## License

SPDX-License-Identifier: AGPL-3.0-or-later

---

## Features

- Interactive selection of redBorder version and product type.
- Automatic download and installation of required tools.
- Integration of redBorder repository and all required RPMs.
- Custom Kickstart generation.
- Bootloader customization.
- Injection of custom Anaconda splash screen and product info.
- Local repository building.
- Final ISO creation compatible with EFI and legacy boot.

## Requirements

Make sure the following tools are installed (the script attempts to install them automatically via `dnf`):

- `squashfs-tools`
- `xorriso`
- `rsync`
- `createrepo`
- `dnf-plugins-core`
- `xmlstarlet`
- `syslinux`
- `lorax`
- `rpmdevtools`
- `curl`

## Usage

```bash
./build-redborder-iso.sh

#!/bin/bash
# redBorder NG ISO creator
# Author: Miguel Álvarez <malvarez@redborder.com>
#
# SPDX-License-Identifier: AGPL-3.0-or-later

set -euo pipefail

VERSION="${VERSION:-9.3}"
BASE_ISO="Rocky-${VERSION}-x86_64-minimal.iso"
KS_FILE_TEMPLATE="ks.cfg.template"
KS_FILE="ks.cfg"
STAGE1_ISO="custom-ks.iso"
FINAL_ISO="redborder-custom.iso"
LABEL="redBorder"
WORKDIR="$(pwd)"
MNT_DIR="$WORKDIR/mnt"
ISO_DIR="$WORKDIR/iso"
INSTALL_IMG_DIR="$WORKDIR/installimg"
ROOTFS_DIR="$WORKDIR/rootfs"
LOCAL_RPMS_DIR="$WORKDIR/localrepo"
REPO_DIR_REL="RBREPO"
REPO_DIR="$ISO_DIR/$REPO_DIR_REL"
IMAGES_DIR="$WORKDIR/images"
PIXMAPS_PATH="/usr/share/anaconda/pixmaps"
REPO_RPM_URL="https://packages.redborder.com/latest/rhel/9/x86_64/redborder-repo-latest-0.0.2-1.el9.rb.noarch.rpm"
REDBORDER_VERSION="latest"
BASE_URL="https://packages.redborder.com"
RELEASES_PAGE="$BASE_URL/releases/"
ARCH="x86_64"
RHEL_VERSION="9"
RHEL_PATH="rhel/$RHEL_VERSION/$ARCH"
PRODUCT_TYPE="manager"

echo "Fetching redBorder release versions..."
mapfile -t VERSIONS < <(
  curl -s "$RELEASES_PAGE" \
    | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' \
    | sort -V
)

MENU=( latest "${VERSIONS[@]}" )

PS3=$'\nSelect redBorder release version (default is "latest"): '
select CHOICE in "${MENU[@]}"; do
  if [[ -z "$CHOICE" ]]; then
    REDBORDER_VERSION="latest"
  else
    REDBORDER_VERSION="$CHOICE"
  fi
  break
done

if [[ "$REDBORDER_VERSION" != "latest" ]]; then
  echo "Fetching RPM for selected version..."
  RPM_FILENAME=$(curl -s "$BASE_URL/releases/$REDBORDER_VERSION/$RHEL_PATH/" \
                | grep -oE 'redborder-repo-[0-9a-zA-Z\.\-]+\.rpm' \
                | sort -V \
                | tail -n1)

  if [[ -z "$RPM_FILENAME" ]]; then
    echo "ERROR: couldn't find repo RPM for version '$REDBORDER_VERSION'." >&2
    exit 1
  fi

  REPO_RPM_URL="$BASE_URL/releases/$REDBORDER_VERSION/$RHEL_PATH/$RPM_FILENAME"
fi

PRODUCT_TYPES=( manager ips intrusion proxy )
PS3=$'\nSelect product type (default is "manager"): '
select PRODUCT_CHOICE in "${PRODUCT_TYPES[@]}"; do
  if [[ -z "$PRODUCT_CHOICE" ]]; then
    PRODUCT_TYPE="manager"
  else
    PRODUCT_TYPE="$PRODUCT_CHOICE"
  fi
  break
done

echo
echo "Using redBorder version:    $REDBORDER_VERSION"
echo "Repo RPM URL:               $REPO_RPM_URL"
echo "Selected product type:      $PRODUCT_TYPE"
echo

echo "Installing required tools..."
sudo dnf install -y squashfs-tools xorriso rsync createrepo dnf-plugins-core xmlstarlet syslinux lorax rpmdevtools curl > /dev/null

echo "Cleaning working directories..."
sudo rm -rf ./custom-ks.iso > /dev/null 2>&1 || true
sudo umount "$MNT_DIR" > /dev/null 2>&1 || true
sudo umount "$ROOTFS_DIR" > /dev/null 2>&1 || true
rm -rf "$MNT_DIR" "$ISO_DIR" "$INSTALL_IMG_DIR" "$ROOTFS_DIR" "$LOCAL_RPMS_DIR" > /dev/null 2>&1 || true

mkdir -p "$MNT_DIR" "$ISO_DIR" "$INSTALL_IMG_DIR" "$ROOTFS_DIR" "$LOCAL_RPMS_DIR"

echo "Downloading redborder-repo RPM..."
curl -sSL "$REPO_RPM_URL" -o /tmp/redborder-repo.rpm > /dev/null

echo "Downloading redborder-repo RPM..."
curl -sSL "$REPO_RPM_URL" -o /tmp/redborder-repo.rpm

echo "Installing redborder-repo..."
sudo dnf install -y /tmp/redborder-repo.rpm
sudo dnf config-manager --set-enabled redborder-$REDBORDER_VERSION

echo "Downloading all RPMs from redborder repository..."
mkdir -p "$LOCAL_RPMS_DIR"
dnf repoquery \
  --repo=redborder-$REDBORDER_VERSION \
  --location --latest-limit=1 \
| xargs -r -n1 curl -LO --output-dir "$LOCAL_RPMS_DIR"

echo "Disabling redborder repository..."
sudo dnf config-manager --set-disabled redborder-$REDBORDER_VERSION

echo "Building kickstart config..."
sed \
  -e "s/\[\[PRODUCT_TYPE\]\]/$PRODUCT_TYPE/g" \
  -e "s/\[\[VERSION\]\]/$REDBORDER_VERSION/g" \
  "$KS_FILE_TEMPLATE" > $KS_FILE

echo "Creating base ISO with kickstart..."
mkksiso --ks "$KS_FILE" "$BASE_ISO" "$STAGE1_ISO" > /dev/null

echo "Mounting and syncing custom ISO..."
sudo mount -o loop "$STAGE1_ISO" "$MNT_DIR" > /dev/null
rsync -a --exclude=TRANS.TBL "$MNT_DIR/" "$ISO_DIR/" > /dev/null
sudo umount "$MNT_DIR" > /dev/null

echo "Patching bootloader..."
for FILE in \
  "$ISO_DIR/EFI/BOOT/grub.cfg" \
  "$ISO_DIR/isolinux/isolinux.cfg" \
  "$ISO_DIR/isolinux/grub.conf"
do
  if [ -f "$FILE" ]; then
    echo "Patching: $FILE"
    sudo sed -i -E \
      -e "s/Rocky Linux [0-9]+\.[0-9]+/redBorder $PRODUCT_TYPE ($REDBORDER_VERSION)/g" \
      -e "s/Rocky-[0-9]+-[0-9]+-x86_64-dvd/$LABEL/g" \
      -e "s/^\s*echo\s+'.*'/echo 'Welcome to redBorder $PRODUCT_TYPE ($REDBORDER_VERSION)'/" \
      -e "/linux / s/$/ inst.sshd=1/" \
      "$FILE"
  else
    echo "WARNING: File not found - $FILE"
  fi
done

echo "Injecting custom splash images..."
rm -rf "./installimg" > /dev/null 2>&1 || true
unsquashfs -d "$INSTALL_IMG_DIR" "$ISO_DIR/images/install.img" > /dev/null
sudo mount -o loop "$INSTALL_IMG_DIR/LiveOS/rootfs.img" "$ROOTFS_DIR" > /dev/null
sudo mkdir -p "$ROOTFS_DIR$PIXMAPS_PATH" > /dev/null 2>&1 || true
sudo cp "$IMAGES_DIR"/{sidebar-bg.png,sidebar-logo.png,topbar-bg.png} "$ROOTFS_DIR$PIXMAPS_PATH/" > /dev/null 2>&1 || true
sudo cp "$IMAGES_DIR/splash.png" "$ISO_DIR/isolinux/" > /dev/null 2>&1 || true

echo "Patching Anaconda product...."

sed -i "/productVersion = trim_product_version_for_ui(productVersion)/a\\
productVersion = \"$REDBORDER_VERSION\"\\
productName = \"redBorder $PRODUCT_TYPE\"
" "$ROOTFS_DIR/usr/lib64/python3.9/site-packages/pyanaconda/product.py"

echo "Building local repository..."
mkdir -p "$REPO_DIR"
cp -a "$LOCAL_RPMS_DIR"/* "$REPO_DIR/"
createrepo --database "$REPO_DIR" > /dev/null

echo "Repacking install.img..."
sudo mksquashfs "$INSTALL_IMG_DIR" "$ISO_DIR/images/install.img" -comp xz -b 131072 -noappend -no-xattrs > /dev/null

FINAL_ISO="redborder-${PRODUCT_TYPE}-${REDBORDER_VERSION}-${ARCH}.iso"

echo "Creating final ISO..."
xorriso -as mkisofs \
  -o "$FINAL_ISO" \
  -isohybrid-mbr /usr/share/syslinux/isohdpfx.bin \
  -c isolinux/boot.cat \
  -b isolinux/isolinux.bin \
  -no-emul-boot -boot-load-size 4 -boot-info-table \
  -eltorito-alt-boot \
  -e images/efiboot.img \
  -no-emul-boot \
  -V "$LABEL" \
  -J -R -T \
  -m '*.iso' \
  -graft-points "$REPO_DIR_REL"="$REPO_DIR" \
  "$ISO_DIR" > /dev/null

echo
echo "Final patched ISO created:"
echo "   --> $FINAL_ISO"

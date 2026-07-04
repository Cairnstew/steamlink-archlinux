#!/bin/bash
# Determine script directory regardless of how we're invoked
SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"

# Parse arguments
TAILSCALE_KEY=""
DEVICE=""
while [[ $# -gt 0 ]]; do
  case $1 in
    -k|--tailscale-key)
      TAILSCALE_KEY="$2"
      shift 2
      ;;
    --tailscale-key=*)
      TAILSCALE_KEY="${1#*=}"
      shift
      ;;
    -d|--device)
      DEVICE="$2"
      shift 2
      ;;
    --device=*)
      DEVICE="${1#*=}"
      shift
      ;;
    -h|--help)
      echo "Usage: $0 [OPTIONS]"
      echo ""
      echo "Creates a bootable Arch Linux USB for Valve Steam Link."
      echo ""
      echo "Options:"
      echo "  -d, --device DEV        USB partition (e.g. /dev/sdb1). If omitted, prompts interactively."
      echo "  -k, --tailscale-key KEY  Tailscale auth key for automatic mesh VPN setup"
      echo "                           Device will join your tailnet on first boot"
      echo "  -h, --help               Show this help message"
      exit 0
      ;;
    --)
      shift
      break
      ;;
    -*)
      echo "Unknown option: $1"
      echo "Usage: $0 [--tailscale-key KEY]"
      exit 1
      ;;
    *)
      break
      ;;
  esac
done

echo "ArchLinux BootMedium Creator for Steamlink"
echo "Based on https://www.reddit.com/r/Steam_Link/comments/fgew5x/running_archlinux_on_steam_link_revisited/"
echo ""

if [ -z "$DEVICE" ]; then
  sudo blkid
  echo ""
  echo "Please enter /dev/ address of your USB disk from above."
  echo "For example /dev/sdb1"
  echo "CAUTION! That device will be formatted and you will lose any data in there!"
  read devaddress
else
  devaddress="$DEVICE"
fi
sudo umount $devaddress
echo [1/11] formatting $devaddress
sudo mkfs.ext3 $devaddress
echo [2/11] mounting $devaddress to /media/disk
sudo mkdir -p /media/disk/
sudo mount $devaddress /media/disk
echo [3/11] "Downloading and unpacking userspace to /media/disk"
curl -Lo arch_userspace.tar.gz http://os.archlinuxarm.org/os/ArchLinuxARM-armv7-latest.tar.gz
echo "       Extracting (this takes a few minutes)..."
GNU_TAR=$(command -v gnutar 2>/dev/null || command -v gtar 2>/dev/null || echo "tar")
sudo "$GNU_TAR" -xpf arch_userspace.tar.gz -C /media/disk/ 2>/dev/null

# ---------------------------------------------------------------------------
# Tailscale injection (optional)
# ---------------------------------------------------------------------------
if [ -n "$TAILSCALE_KEY" ]; then
  echo [3.5/11] "Installing Tailscale for ARM (armv7)"
  TAILSCALE_URL="https://pkgs.tailscale.com/stable/tailscale_latest_arm.tgz"
  if curl -fSLo /tmp/tailscale.tgz "$TAILSCALE_URL"; then
    tar -xzf /tmp/tailscale.tgz -C /tmp/
    TAILSCALE_DIR=$(ls -d /tmp/tailscale_*/ 2>/dev/null || echo "")
    if [ -n "$TAILSCALE_DIR" ] && [ -f "${TAILSCALE_DIR}tailscale" ]; then
      sudo cp "${TAILSCALE_DIR}tailscale" /media/disk/usr/bin/
      sudo cp "${TAILSCALE_DIR}tailscaled" /media/disk/usr/bin/
      sudo chmod 755 /media/disk/usr/bin/tailscale /media/disk/usr/bin/tailscaled

      # Auth key file (read by autoconnect service)
      sudo mkdir -p /media/disk/var/lib/tailscale
      echo "$TAILSCALE_KEY" | sudo tee /media/disk/var/lib/tailscale/auth.key > /dev/null
      sudo chmod 600 /media/disk/var/lib/tailscale/auth.key

      # Tailscale daemon service
      sudo mkdir -p /media/disk/usr/lib/systemd/system
      sudo tee /media/disk/usr/lib/systemd/system/tailscaled.service > /dev/null << 'SERVICEOF'
[Unit]
Description=Tailscale node agent
Documentation=https://tailscale.com/kb/
After=network.target
Wants=network.target

[Service]
Type=simple
ExecStart=/usr/bin/tailscaled
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
SERVICEOF

      # Oneshot autoconnect service — authenticates on boot using pre-loaded key
      sudo tee /media/disk/usr/lib/systemd/system/tailscale-autoconnect.service > /dev/null << 'AUTOCONNECT'
[Unit]
Description=Tailscale auto-authenticate
After=tailscaled.service
Requires=tailscaled.service

[Service]
Type=oneshot
ExecStart=/bin/sh -c '/usr/bin/tailscale up --auth-key=$(cat /var/lib/tailscale/auth.key) --ssh --accept-dns=true'
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
AUTOCONNECT

      # Enable both services
      sudo mkdir -p /media/disk/etc/systemd/system/multi-user.target.wants/
      sudo ln -sf /usr/lib/systemd/system/tailscaled.service /media/disk/etc/systemd/system/multi-user.target.wants/tailscaled.service
      sudo ln -sf /usr/lib/systemd/system/tailscale-autoconnect.service /media/disk/etc/systemd/system/multi-user.target.wants/tailscale-autoconnect.service

      rm -f /tmp/tailscale.tgz
      rm -rf /tmp/tailscale_*/
    else
      echo "Warning: Tailscale extracted files not found, skipping." >&2
    fi
  else
    echo "Warning: Failed to download Tailscale binary, skipping." >&2
  fi
else
  echo "[3.5/11] Skipping Tailscale (no --tailscale-key provided)"
fi

echo [4/11] "Copying kexec_load.ko"
sudo cp "$SCRIPT_DIR/kexec_load.ko" /media/disk/boot/
echo [5/11] "Copying zImage"
sudo cp "$SCRIPT_DIR/zImage_6_1_66" /media/disk/boot/zImage
echo [6/11] "Copying initramfs"
sudo cp "$SCRIPT_DIR/initramfs-linux-steam_6_1_66.img" /media/disk/boot/initramfs-linux-steam.img
echo [7/11] "Copying berlin2cd-valve-steamlink.dtb"
sudo cp "$SCRIPT_DIR/berlin2cd-valve-steamlink.dtb" /media/disk/boot/
echo [8/11] "Copying  kexec and 755 on kexec"
sudo cp "$SCRIPT_DIR/kexec" /media/disk/usr/bin
sudo chmod 755 /media/disk/usr/bin/kexec
echo [9/11] "Copying 6.1.66-mrvl to modules"
sudo cp -r "$SCRIPT_DIR/6.1.66-mrvl/" /media/disk/lib/modules/
echo [10/11] "Copying run.sh and 755 on it"
sudo mkdir -p /media/disk/steamlink/factory_test/
sudo cp "$SCRIPT_DIR/run.sh" /media/disk/steamlink/factory_test/
sudo chmod 755 /media/disk/steamlink/factory_test/run.sh
echo [11/11] "Finally creating ssh folder"
sudo mkdir -p /media/disk/steamlink/config/system/
sudo echo "True" > /media/disk/steamlink/config/system/enable_ssh.txt
echo "Completed, unmounting disk. This may take a while."
sudo umount -l $devaddress
echo "Cleaning up ... "
sudo rm -rf /media/disk
echo  "Completed. Please remove the USB disk and insert it into steamlink."

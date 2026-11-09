#!/usr/bin/env bash
# pi1-offline-wiki setup script
#
# Turns a Raspberry Pi running Raspberry Pi OS Lite into an offline library
# hotspot: Kiwix serves every .zim file on a USB drive labelled WIKI, over a
# Wi-Fi network the Pi broadcasts itself.
#
# Run once, while the Pi has internet (Ethernet is easiest):
#   sudo bash setup.sh
#
# Then reboot. See README.md for the full guide.

set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
CFG="$REPO_DIR/config"
DRIVER_REPO="https://github.com/AtlasDelta7/rtl8188eus"

say()  { printf '\n\033[1;32m==> %s\033[0m\n' "$*"; }
warn() { printf '\n\033[1;33m!!  %s\033[0m\n' "$*"; }
die()  { printf '\n\033[1;31mxx  %s\033[0m\n' "$*"; exit 1; }

[ "$(id -u)" -eq 0 ] || die "Run with sudo:  sudo bash setup.sh"
PI_USER="${SUDO_USER:-}"
[ -n "$PI_USER" ] && [ "$PI_USER" != "root" ] || die "Run with sudo from your normal user, not as root directly."

# --- Questions -------------------------------------------------------------
say "Hotspot settings"
read -rp "Hotspot name [OfflineWiki]: " SSID
SSID="${SSID:-OfflineWiki}"
while true; do
  read -rsp "Hotspot password (8-63 characters): " PASS; echo
  [ ${#PASS} -ge 8 ] && [ ${#PASS} -le 63 ] && break
  warn "Password must be 8-63 characters."
done
read -rp "Two-letter country code for Wi-Fi rules [GB]: " COUNTRY
COUNTRY="$(echo "${COUNTRY:-GB}" | tr '[:lower:]' '[:upper:]')"

# --- Packages ---------------------------------------------------------------
say "Installing packages (slow on a Pi 1 - make a cup of tea)"
apt-get update
apt-get install -y kiwix-tools hostapd dnsmasq iw curl

# hostapd and dnsmasq start themselves on install; keep them off until configured
systemctl disable --now hostapd dnsmasq 2>/dev/null || true

# --- Wi-Fi country ----------------------------------------------------------
say "Setting Wi-Fi country to $COUNTRY"
raspi-config nonint do_wifi_country "$COUNTRY" || warn "Could not set country via raspi-config"
rfkill unblock wifi || true

# --- Wi-Fi driver -----------------------------------------------------------
# Many cheap Realtek dongles (RTL8188EU/ETV/EUS) can't host a hotspot with the
# kernel's built-in driver. If the dongle already supports AP mode, skip this.
ap_supported() { iw list 2>/dev/null | grep -A 10 "Supported interface modes" | grep -q "\* AP"; }

DRIVER_BUILT=0
if ap_supported; then
  say "Wi-Fi dongle already supports hotspot (AP) mode - no driver needed"
elif lsusb | grep -qiE "0bda:(8179|0179)"; then
  say "Realtek RTL8188EU-family dongle without AP mode found - building patched driver"
  warn "This takes roughly 1-1.5 hours on a Raspberry Pi 1. Don't unplug anything."
  apt-get install -y git build-essential bc "linux-headers-$(uname -r)" \
    || die "Kernel headers for $(uname -r) not found. Run 'sudo apt full-upgrade', reboot, then run this script again."
  BUILD_DIR="/home/$PI_USER/rtl8188eus"
  rm -rf "$BUILD_DIR"
  sudo -u "$PI_USER" git clone --depth 1 "$DRIVER_REPO" "$BUILD_DIR"
  sudo -u "$PI_USER" make -C "$BUILD_DIR" -j"$(nproc)"
  make -C "$BUILD_DIR" install
  cat > /etc/modprobe.d/realtek.conf <<'EOF'
blacklist r8188eu
blacklist rtl8xxxu
EOF
  DRIVER_BUILT=1
else
  warn "Couldn't confirm your dongle supports hotspot mode. Check after reboot with:  iw list"
fi

# --- Hotspot: hostapd + dnsmasq ------------------------------------------------
say "Configuring hotspot \"$SSID\""
# Escape characters that would break sed, then fill in the template
esc() { printf '%s' "$1" | sed -e 's/[\\/&|]/\\&/g'; }
sed -e "s|__SSID__|$(esc "$SSID")|" \
    -e "s|__PASSWORD__|$(esc "$PASS")|" \
    -e "s|__COUNTRY__|$COUNTRY|" \
    "$CFG/hostapd.conf" > /etc/hostapd/hostapd.conf
chmod 600 /etc/hostapd/hostapd.conf

install -Dm644 "$CFG/dnsmasq-wiki.conf"             /etc/dnsmasq.d/wiki.conf
install -Dm644 "$CFG/nm-unmanaged.conf"             /etc/NetworkManager/conf.d/unmanaged.conf
install -Dm644 "$CFG/systemd/hostapd-override.conf" /etc/systemd/system/hostapd.service.d/override.conf
install -Dm644 "$CFG/systemd/dnsmasq-override.conf" /etc/systemd/system/dnsmasq.service.d/override.conf

# --- Drive + Kiwix ------------------------------------------------------------
say "Setting up the WIKI drive mount and Kiwix"
mkdir -p /mnt/wiki
if ! grep -q "/mnt/wiki" /etc/fstab; then
  grep -v '^#' "$CFG/fstab.txt" >> /etc/fstab
fi
sed -e "s|__USER__|$PI_USER|" "$CFG/systemd/kiwix.service" > /etc/systemd/system/kiwix.service

# --- Enable everything --------------------------------------------------------
systemctl daemon-reload
systemctl unmask hostapd
systemctl enable hostapd dnsmasq kiwix

# --- Protect the custom driver from kernel updates ------------------------------
if [ "$DRIVER_BUILT" -eq 1 ]; then
  say "Holding the kernel so updates can't break the custom Wi-Fi driver"
  # Hold the installed kernel metapackages (e.g. linux-image-rpi-v6)
  HOLD=$(dpkg-query -W -f='${db:Status-Abbrev} ${Package}\n' 'linux-image-rpi-*' 'linux-headers-rpi-*' 2>/dev/null | awk '$1=="ii"{print $2}' || true)
  if [ -n "$HOLD" ]; then apt-mark hold $HOLD; fi
fi

say "Done!"
cat <<EOF

Next steps:
  1. Shut down:            sudo shutdown -h now
  2. With the power OFF, plug in the Wi-Fi dongle and the WIKI drive.
  3. Power on and wait ~3 minutes.
  4. Join "$SSID" on your phone and open  http://10.42.0.1
  5. Once everything works, make it safe to switch off at the plug:
       sudo raspi-config  ->  Performance Options  ->  Overlay File System  ->  Yes

Note: the Pi will no longer join your home Wi-Fi with the dongle.
For internet later, plug in an Ethernet cable.
EOF

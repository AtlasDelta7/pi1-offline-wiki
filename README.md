# pi1-offline-wiki

**All of Wikipedia, 60,000+ books and a shelf of university textbooks, served over Wi-Fi from a 2012 Raspberry Pi 1 running on a power bank.**

Switch it on, join its Wi-Fi network from any phone or laptop, and browse — no internet, no app, no SIM. It's built from parts that were lying around, plus a £5 cable.

<!-- Add photos here, e.g. ![The finished box](images/box.jpg) -->

---

## What it does

- Broadcasts its own Wi-Fi hotspot (default name **OfflineWiki**).
- Any device that joins can open **http://10.42.0.1** and browse the library in a normal web browser.
- Runs [Kiwix](https://kiwix.org), which serves compressed `.zim` archives of Wikipedia and other open content.
- Fully offline and battery powered, and safe to switch off at the power bank (read-only system).

### Library on mine (~230 GB)

| Content | Size |
|---|---|
| English Wikipedia, all articles with images (`wikipedia_en_all_maxi`) | 119 GB |
| Project Gutenberg, ~60,000 public-domain books | 72 GB |
| English Wikibooks (text) | 3 GB |
| LibreTexts: engineering, maths, physics, medicine, business, social sciences | a few GB each |

Everything is openly licensed (Creative Commons / public domain). Download from [library.kiwix.org](https://library.kiwix.org) or [download.kiwix.org/zim](https://download.kiwix.org/zim/). Note that Gutenberg's public-domain status is based on US law, so check your local rules if you plan to redistribute it.

---

## Hardware

| Part | Notes |
|---|---|
| Raspberry Pi 1 Model B (rev 2, 512 MB) | Any Pi works. Newer ones are much faster and have built-in Wi-Fi. |
| SD card, 8 GB+ | OS only |
| USB Wi-Fi dongle that can host a hotspot | Mine is a Realtek **RTL8188ETV**, which needed a patched driver (below). An **RT5370** dongle works out of the box. |
| NVMe SSD in a USB enclosure (256 GB) | Any USB drive or SSD works. Format it **exFAT** and label it **WIKI**. |
| USB "Y" power-injector cable | Gives the drive extra power straight from the power bank. Check with a multimeter that the power leg only carries 5 V and ground, not the data pins. |
| Power bank with **two** USB outputs | One port powers the Pi, the other powers the drive. ~20,000 mAh gives roughly 12–17 h. |
| USB-A to micro-USB cable | Powers the Pi |

**Wiring:** power bank port 1 → micro-USB → Pi power. Power bank port 2 → Y-cable power leg. Y-cable data leg → Pi USB. Drive → Y-cable. Wi-Fi dongle → the other Pi USB port.

> ⚠️ **Never plug or unplug USB devices while a Pi 1 is running.** The voltage dip crashes it. Shut down first.

---

## Setup

Most of the work is done by one script. On a Pi 1 the whole process takes about 2 hours of mostly waiting (driver compile and updates), plus however long your downloads take.

### 1. Flash the OS
- Write **Raspberry Pi OS Lite (32-bit)** to the SD card using [Raspberry Pi Imager](https://www.raspberrypi.com/software/) (choose device: Raspberry Pi 1). Rufus also works.
- In Imager's settings, set a username and password, a hostname, and **enable SSH**.

### 2. First boot and update
Plug the Pi into your router **with Ethernet** (simplest: it gives internet and SSH while the dongle is busy being a hotspot), boot it, and SSH in or use a keyboard. Then:

```
sudo apt update && sudo apt full-upgrade -y
```

```
sudo reboot
```

Updating first matters: the Wi-Fi driver must be built for the kernel you'll actually run.

### 3. Run the setup script
Plug in the Wi-Fi dongle (with the Pi off), boot, then:

```
git clone https://github.com/AtlasDelta7/pi1-offline-wiki
```

```
cd pi1-offline-wiki
```

```
sudo bash setup.sh
```

It asks for a hotspot name, password and country, then:
- installs Kiwix, hostapd and dnsmasq
- checks whether your dongle can host a hotspot and, if it's an RTL8188EU-family dongle that can't, builds the [patched driver](https://github.com/AtlasDelta7/rtl8188eus) (≈1–1.5 h on a Pi 1)
- configures the hotspot, DHCP, the drive mount and Kiwix to start on boot
- holds the kernel version so future updates can't break the custom driver

### 4. Prepare the drive (on your PC)
- Format it as a single **exFAT** partition labelled **WIKI**. FAT32 can't hold files over 4 GB.
- Download `.zim` files straight onto it. For big files use the **torrent** links (add `.torrent` to any download.kiwix.org link), as browser downloads tend to fail partway through.
- Eject it safely. Kiwix loads **every** `.zim` on the drive automatically, so adding a library later is just copying a file on.

### 5. Put it together
With the power off, plug in the drive and dongle, power on and wait ~3 minutes. Join the hotspot and open **http://10.42.0.1**.

### 6. Make it safe to switch off at the plug
Once everything works, turn on the read-only overlay, so the SD card can't be corrupted by pulling the power:

```
sudo raspi-config
```

Then go to **Performance Options → Overlay File System → Yes**, and Yes to a write-protected boot partition. To change anything later, turn it off the same way, reboot, make changes, then turn it back on.

---

## Using it

- Power on → wait ~3 min → join the hotspot → open **http://10.42.0.1**.
- **Use Safari / the default browser.** Some browsers (e.g. Brave on iOS) refuse to load anything on a network with no internet.
- Your phone will say "No Internet Connection". That's expected.
- Tip: add the page to your home screen.
- **Speed on a Pi 1:** title search and opening articles take a second or two; full-text search can take 10+ seconds. It's the CPU, not the drive.
- **SSH in without a keyboard:** join the hotspot from a laptop and run `ssh <your-user>@10.42.0.1`.

---

## Troubleshooting

| Problem | Cause / fix |
|---|---|
| `iw list` shows no `* AP` mode | The dongle's built-in driver can't host a hotspot. Use an RT5370 dongle, or (RTL8188EU family) the patched driver the script builds. |
| Driver build fails with `drv_types.h: No such file` | Kernel 6.15+ ignores `EXTRA_CFLAGS`. Use [the patched fork](https://github.com/AtlasDelta7/rtl8188eus), which fixes this and the timer/cfg80211 API changes up to 6.18. |
| Kernel headers not found | Run `sudo apt full-upgrade`, reboot, then re-run the script. |
| NetworkManager hotspot: "802.1X supplicant took too long" / stuck "configuring" | This driver doesn't work with NM's hotspot. The script uses hostapd + dnsmasq instead. |
| Hotspot appears but phones get a `169.254.x.x` address | The hotspot isn't getting its `10.42.0.1` address or dnsmasq isn't running. Check `ip addr show wlan0` and `systemctl status dnsmasq`. (Handled by the hostapd override and `port=0` in this repo.) |
| Hotspot works but the page won't load | Kiwix isn't running: `systemctl status kiwix`. "Dependency failed" means the drive didn't mount. Check `lsblk -f` shows the **WIKI** label. |
| Screen floods with `dwc_otg ... Unexpected IRQ state` | A USB device keeps dropping out, usually from power or a poor cable. Check both power bank leads and reseat the Y-cable. |
| Pi crashes when you plug/unplug USB | Normal for a Pi 1. Always shut down first. |
| Can't SSH in over home Wi-Fi | Many routers block Wi-Fi devices talking to each other. Use Ethernet, or SSH in over the hotspot. |

---

## Files

| File | Installed to | Purpose |
|---|---|---|
| `setup.sh` | — | Does the whole setup |
| `config/hostapd.conf` | `/etc/hostapd/hostapd.conf` | The hotspot |
| `config/dnsmasq-wiki.conf` | `/etc/dnsmasq.d/wiki.conf` | Hands out IP addresses (DHCP only) |
| `config/nm-unmanaged.conf` | `/etc/NetworkManager/conf.d/unmanaged.conf` | Keeps NetworkManager off the dongle |
| `config/systemd/hostapd-override.conf` | `/etc/systemd/system/hostapd.service.d/override.conf` | Sets `10.42.0.1` whenever hostapd starts |
| `config/systemd/dnsmasq-override.conf` | `/etc/systemd/system/dnsmasq.service.d/override.conf` | Starts DHCP after the hotspot |
| `config/systemd/kiwix.service` | `/etc/systemd/system/kiwix.service` | Serves every `.zim` on the drive |
| `config/fstab.txt` | appended to `/etc/fstab` | Mounts the WIKI drive read-only |

---

## Build story

The first version took the best part of two days. Highlights:

- **ESP32 ruled out:** the original ESP32 has no USB host, the S3's USB is far too slow, and neither has the RAM to read ZIM archives.
- **The driver saga:** the dongle I had couldn't host a hotspot with the stock driver. Rather than spend £3 on one that could, I compiled a community driver, which no longer built on kernel 6.18. Several hours and multiple 1.5-hour compiles later, it worked, and those fixes are now in [the fork](https://github.com/AtlasDelta7/rtl8188eus) so nobody else has to do that.
- **Hotspot:** NetworkManager's hotspot wouldn't cooperate with the driver, so it moved to hostapd + dnsmasq. Then phones got no IP address, fixed by having hostapd assign the Pi's address itself and running dnsmasq as DHCP-only.
- **Power:** a Pi 1 can't power an NVMe drive on its own, so the drive gets a second feed from the power bank through a Y-cable.

Total spend: **£5** (the Y-cable). Next time I'd make that myself, too.

---

## Licence

Scripts and configs: [MIT](LICENSE). The patched driver is GPL-2.0 (see its repo). Library content is licensed by its respective publishers.

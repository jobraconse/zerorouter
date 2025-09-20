#!/bin/bash
# Restore zero Pi to normal Wi-Fi client mode
# Stops AP services, restores original network config and DNS

set -e

if [ "$EUID" -ne 0 ]; then
    echo "Please run as root (sudo $0)"
    exit 1
fi

echo "=== Stopping hostapd, dnsmasq and dhcpcd ==="
systemctl stop hostapd || true
systemctl stop dnsmasq || true
systemctl stop dhcpcd || true
systemctl disable hostapd dnsmasq dhcpcd || true

# === Restore original dnsmasq config ===
if [ -f /etc/dnsmasq.conf.orig ]; then
    mv /etc/dnsmasq.conf.orig /etc/dnsmasq.conf
    echo "✅ Restored original /etc/dnsmasq.conf"
fi

echo "" > /etc/rc.local
rm -f /etc/dhcpcd.conf
echo "✅ deleted /etc/dhcpcd.conf"
rm -f /etc/sysctl.conf
echo "✅ deleted /etc/sysctl.conf"
rm -f /etc/default/hostapd
echo "✅ deleted /etc/default/hostapd"
sysctl -p

apt purge dhcpcd dnsmasq iptables-peristent hostapd

echo "✅ Reset complete! Your Pi is back to normal Wi-Fi client mode."
echo "Please reboot for all changes to take effect."

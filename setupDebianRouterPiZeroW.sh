#!/bin/bash
# Raspberry Pi 400 - WiFi Access Point setup (Debian 12)
# wlan0 = internet uplink
# wlan1 = Access Point
# Run as root

set -euo pipefail
shopt -s nullglob

# script must be run by root
if [ "${EUID:-$(id -u)}" -ne 0 ]; then
  echo "Fout: this script must be run as root. Use 'sudo' or login as root." >&2
  exit 1
fi

interfaces=()

# collect physical networkinterfaces
for iface_path in /sys/class/net/*; do
  iface=$(basename "$iface_path")

  # always skip
  [ "$iface" = "lo" ] && continue

  # don't show virtual/bridge/docker-prefixes
  case "$iface" in
    docker*|docker0|veth*|br-*|virbr*|vmnet*|tap*|tun*|ifb*|macvlan* )
      continue
      ;;
  esac

  # only show real devices
  if [ -e "$iface_path/device" ]; then
    interfaces+=("$iface")
  fi
done

if [ ${#interfaces[@]} -eq 0 ]; then
  echo "No physical networkinterfaces found."
  exit 1
fi

# show menu
echo "Available networkinterfaces:"
for i in "${!interfaces[@]}"; do
  echo "  [$i] ${interfaces[$i]}"
done

# ask choice 
read -rp "Choose the interface that is connected to the internet: " choice

if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -ge "${#interfaces[@]}" ]; then
  echo "Choice not valid."
  exit 1
fi

ETH0="${interfaces[$choice]}"

# remove selected from list
unset 'interfaces[$choice]'
interfaces=("${interfaces[@]}")

# choose the other as ETH1
ETH1="${interfaces[0]}"


# Ask user for a SSID and a passphrase
read -rp "Choose prefered SSID in: " SSID
read -rsp "Insert WPA2 passphrase (min. 8 characters): " PASSPHRASE
echo ""

SSID=$SSID
PASSPHRASE=$PASSPHRASE

if [[ -z "$1" ]]; then
	echo "[+] Installing needed packages..."
	apt update
	apt install -y hostapd dnsmasq iptables-persistent dhcpcd
fi

echo "[+] Stop services for configuration..."
systemctl stop hostapd
systemctl stop dnsmasq

# --- dhcpcd configuratie ---
echo "[+] write dhcpcd configuration..."
cat > /etc/dhcpcd.conf <<EOF

interface $ETH1
    static ip_address=192.168.50.1/24
    nohook wpa_supplicant
EOF
systemctl restart dhcpcd

echo "[+] configuration dnsmasq..."
mv /etc/dnsmasq.conf /etc/dnsmasq.conf.orig
cat > /etc/dnsmasq.conf <<EOF
interface=$ETH1
dhcp-range=192.168.50.10,192.168.50.100,255.255.255.0,24h
EOF

echo "[+] starting dnsmasq..."
systemctl enable --now dnsmasq

echo "[+] ipv4 forwarding in /etc/sysctl.conf..."
cat >> /etc/sysctl.conf << EOF
net.ipv4.ip_forward=1
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
net.ipv6.conf.lo.disable_ipv6 = 1
EOF

echo "[+] activating ipv4 forwarding"
sysctl -p

echo "[+] add a masquerade for outbound traffic on eth0"
iptables -t nat -A POSTROUTING -o ETH0 -j MASQUERADE

echo "[+] Saving the iptables rules"
sh -c "iptables-save > /etc/iptables.ipv4.nat"
cat >> /etc/rc.local << EOF
iptables-restore < /etc/iptables.ipv4.nat
EOF
chmod +x /etc/rc.local
ln -sf /etc/rc.local /etc/runit/runsvdir/default/rc.local

echo "[+] Creating the hostapd conf file"
echo ""
echo "##################################"
echo "###                            ###"
echo "###    default = 2.4 Ghz!      ###"
echo "###                            ###"
echo "##################################"
echo ""
read -p "Do you want to use 5 GHz ? <y/N>: " choice
echo ""

if [[ "$choice" == "y" || "$choice" == "Y" ]]; then
    hw_mode="a"
    channel="40"
else
    hw_mode="g"
    channel="7"
fi


cat > /etc/hostapd/hostapd.conf <<EOF
interface=$ETH1
driver=nl80211
ssid=$SSID
hw_mode=$hw_mode
channel=$channel
wmm_enabled=0
macaddr_acl=0
auth_algs=1
ignore_broadcast_ssid=0
wpa=2
wpa_passphrase=$PASSPHRASE
wpa_key_mgmt=WPA-PSK
wpa_pairwise=TKIP
rsn_pairwise=CCMP
EOF

# a = IEEE 802.11a(5 Ghz) -- channel >= 40
# g = IEEE 802.11a(2.4 Ghz) -- channel 0-9
# b = IEEE 802.11a(2.4 Ghz) -- channel 0-9

# link hostapd config
cat >> /etc/default/hostapd << EOF
DAEMON_CONF="/etc/hostapd/hostapd.conf"
EOF


echo "[+] Activating Services..."
systemctl unmask hostapd
systemctl enable --now hostapd
systemctl restart hostapd
systemctl restart dnsmasq

echo "[+] Done!"
echo ""
echo "SSID: $SSID"
echo "Wachtwoord: $PASSPHRASE"
echo ""
echo "Network device connected to the internet: $ETH0"
echo "Network device as Hotspot: $ETH1"
echo ""


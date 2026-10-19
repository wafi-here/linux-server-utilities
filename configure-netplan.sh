#!/bin/bash

# ==========================================================
# ADVANCED TARGETED NETPLAN CONFIGURATOR SCRIPT (OPTIMIZED)
# OS       : Ubuntu Server
# Features : Interface Detection, Dynamic Parameters,
#            Targeted Interface Overwrite, Pristine YAML Formatting
# ==========================================================

set -Eeuo pipefail

# Ensure root privileges
if [ "$(id -u)" -ne 0 ]; then
    echo "Error: Jalankan script menggunakan sudo."
    echo "Contoh: sudo bash ./configure-netplan.sh"
    exit 1
fi

echo "=================================================="
echo " ADVANCED TARGETED NETPLAN CONFIGURATOR"
echo "=================================================="
echo "Tekan Enter untuk menggunakan nilai default atau kosongkan."
echo ""

# 1. Detect network interfaces (excluding loopback 'lo')
echo "[+] Mendeteksi network interface yang tersedia..."
AVAILABLE_INTERFACES=$(ip -o link show | awk -F': ' '{print $2}' | grep -v '^lo$')
DEFAULT_IFACE=$(echo "$AVAILABLE_INTERFACES" | head -n 1)

echo "Interface yang tersedia:"
echo "$AVAILABLE_INTERFACES" | sed 's/^/  - /'
echo ""

# 2. Gather Dynamic Parameters
read -p "Pilih interface target yang akan dikonfigurasi [$DEFAULT_IFACE]: " INTERFACE
INTERFACE="${INTERFACE:-$DEFAULT_IFACE}"

read -p "Aktifkan DHCP (true/false) [false]: " DHCP4
DHCP4="${DHCP4:-false}"

ADDRESSES=""
GATEWAY=""
if [ "$DHCP4" = "false" ]; then
    read -p "Masukkan IP Address & CIDR (pisahkan dengan koma, misal: 10.10.10.2/27) []: " ADDRESSES
    read -p "Masukkan Gateway IP (kosongkan jika tidak ada) []: " GATEWAY
fi

read -p "Masukkan Nameserver IP (pisahkan dengan koma, misal: 8.8.8.8, 1.1.1.1) []: " NS_ADDRESSES
read -p "Masukkan Search Domains (pisahkan dengan koma, misal: localdomain) []: " NS_SEARCH

# 3. Ensure python3 and python3-yaml are installed
if ! python3 -c "import yaml" 2>/dev/null; then
    echo "[+] Menginstal dependensi python3-yaml untuk manipulasi YAML yang aman..."
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq && apt-get install -y -qq python3-yaml
fi

# 4. Find existing Netplan file containing this interface, or default to the first one found
NETPLAN_FILE=""
for f in /etc/netplan/*.yaml; do
    if [ -f "$f" ] && grep -q "$INTERFACE:" "$f"; then
        NETPLAN_FILE="$f"
        break
    fi
done

if [ -z "$NETPLAN_FILE" ]; then
    NETPLAN_FILE=$(ls /etc/netplan/*.yaml 2>/dev/null | head -n 1)
    if [ -z "$NETPLAN_FILE" ]; then
        NETPLAN_FILE="/etc/netplan/01-netcfg.yaml"
    fi
fi

echo "[+] Menggunakan berkas Netplan target: $NETPLAN_FILE"

# 5. Targeted Configuration Update via Embedded Python with Custom IndentedDumper
python3 - "$NETPLAN_FILE" "$INTERFACE" "$DHCP4" "$ADDRESSES" "$GATEWAY" "$NS_ADDRESSES" "$NS_SEARCH" << 'EOF'
import sys
import yaml

yaml_file = sys.argv[1]
iface = sys.argv[2]
dhcp4 = sys.argv[3].lower() == 'true'
addresses_str = sys.argv[4]
gateway = sys.argv[5]
ns_addresses = sys.argv[6]
ns_search = sys.argv[7]

# Custom Dumper to force proper indentation for YAML lists/sequences (matching Netplan standard)
class IndentedDumper(yaml.SafeDumper):
    def increase_indent(self, flow=False, indentless=False):
        return super(IndentedDumper, self).increase_indent(flow, indentless=False)

# Load existing configuration safely
try:
    with open(yaml_file, 'r') as f:
        data = yaml.safe_load(f) or {}
except FileNotFoundError:
    data = {}

# Ensure root netplan structure exists
if 'network' not in data:
    data['network'] = {'version': 2, 'renderer': 'networkd', 'ethernets': {}}
if 'renderer' not in data['network']:
    data['network']['renderer'] = 'networkd'
if 'ethernets' not in data['network']:
    data['network']['ethernets'] = {}

# Ensure target interface dictionary exists
if iface not in data['network']['ethernets']:
    data['network']['ethernets'][iface] = {}

iface_conf = data['network']['ethernets'][iface]
iface_conf['dhcp4'] = dhcp4

# Handle Static IP vs DHCP & Conditional Omission
if not dhcp4:
    if addresses_str:
        iface_conf['addresses'] = [a.strip() for a in addresses_str.split(',') if a.strip()]
    else:
        iface_conf.pop('addresses', None)
    
    # Conditional Gateway / Route omission (Modern Netplan standard uses routes)
    if gateway:
        iface_conf['routes'] = [{'to': 'default', 'via': gateway}]
    else:
        iface_conf.pop('routes', None)
else:
    # Clear static fields if DHCP is enabled
    iface_conf.pop('addresses', None)
    iface_conf.pop('routes', None)

# Handle Nameserver Addresses (Omit if empty)
if ns_addresses:
    if 'nameservers' not in iface_conf:
        iface_conf['nameservers'] = {}
    iface_conf['nameservers']['addresses'] = [n.strip() for n in ns_addresses.split(',') if n.strip()]
else:
    if 'nameservers' in iface_conf:
        iface_conf['nameservers'].pop('addresses', None)
        if not iface_conf['nameservers']:
            iface_conf.pop('nameservers', None)

# Handle Nameserver Search Domains (Omit if empty)
if ns_search:
    if 'nameservers' not in iface_conf:
        iface_conf['nameservers'] = {}
    iface_conf['nameservers']['search'] = [s.strip() for s in ns_search.split(',') if s.strip()]
else:
    if 'nameservers' in iface_conf:
        iface_conf['nameservers'].pop('search', None)
        if not iface_conf['nameservers']:
            iface_conf.pop('nameservers', None)

# Write back updated YAML cleanly using IndentedDumper
with open(yaml_file, 'w') as f:
    yaml.dump(data, f, Dumper=IndentedDumper, sort_keys=False, indent=2)
EOF

# 6. Apply Netplan Configuration with validation check
echo "[+] Memvalidasi dan menerapkan perubahan Netplan..."
if netplan try --timeout 10; then
    echo ""
    echo "=== Netplan Berhasil Dikonfigurasi dan Diterapkan! ==="
else
    echo "[!] Terdeteksi masalah pada konfigurasi, Netplan dikembalikan ke kondisi semula (reverted)."
    exit 1
fi

echo "Interface Target : $INTERFACE"
echo "Berkas YAML      : $NETPLAN_FILE"
echo "Status Interface :"
ip a show "$INTERFACE" | grep -E "inet |UP"

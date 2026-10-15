#!/bin/bash

# ==========================================================
# DYNAMIC BIND9 DNS SERVER SETUP SCRIPT (DNS ONLY)
# OS       : Ubuntu Server 22.04 LTS
# Service  : BIND9 (named)
# ==========================================================

set -Eeuo pipefail

# Check root privilege
if [ "$(id -u)" -ne 0 ]; then
    echo "Error: Jalankan script menggunakan sudo."
    echo "Contoh: sudo bash ./setup-dns.sh"
    exit 1
fi

echo "=================================================="
echo " DYNAMIC BIND9 DNS SERVER SETUP (DNS ONLY)"
echo "=================================================="
echo "Tekan Enter untuk menggunakan nilai default."
echo ""

# Deteksi IP aktif pada sistem secara otomatis sebagai saran default
AUTO_DETECT_IP=$(hostname -I | awk '{print $1}')
AUTO_DETECT_IP="${AUTO_DETECT_IP:-192.168.56.10}"

# -------------------- INPUT DINAMIS -----------------------

read -p "Masukkan Domain Name [pas-paas.local]: " DOMAIN_NAME
DOMAIN_NAME="${DOMAIN_NAME:-pas-paas.local}"

# Jika user mengosongkan nama domain, batalkan proses
if [ -z "$DOMAIN_NAME" ]; then
    echo "Error: Domain Name tidak boleh kosong."
    exit 1
fi

read -p "Masukkan Server IP dengan CIDR (contoh: 192.168.56.10/24) [$AUTO_DETECT_IP/24]: " SERVER_CIDR
SERVER_CIDR="${SERVER_CIDR:-$AUTO_DETECT_IP/24}"

# Ekstrak IP tanpa CIDR
SERVER_IP_ONLY="${SERVER_CIDR%/*}"

# Validasi Format IP
if ! [[ "$SERVER_IP_ONLY" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
    echo "Error: Format IP address tidak valid."
    exit 1
fi

IFS='.' read -r ip1 ip2 ip3 ip4 <<< "$SERVER_IP_ONLY"

DOMAIN_BASE="${DOMAIN_NAME%.}"
REVERSE_ZONE_NAME="${ip3}.${ip2}.${ip1}.in-addr.arpa"
FORWARD_FILE="/etc/bind/db.${DOMAIN_BASE}"
REVERSE_FILE="/etc/bind/db.${ip3}"

echo ""
echo "=================================================="
echo " RINGKASAN KONFIGURASI"
echo "=================================================="
echo "Domain Name  : $DOMAIN_NAME"
echo "Server IP    : $SERVER_IP_ONLY"
echo "Forward DB   : $FORWARD_FILE"
echo "Reverse Zone : $REVERSE_ZONE_NAME"
echo "Reverse DB   : $REVERSE_FILE"
echo "=================================================="
echo ""

# -------------------- 1. INSTALASI BIND9 ---------------------

echo "[1/5] Memeriksa dan Menginstal BIND9..."
export DEBIAN_FRONTEND=noninteractive

if ! dpkg -l | grep -q bind9; then
    apt-get update
    apt-get install -y bind9 bind9-utils bind9-doc
else
    echo "Paket BIND9 sudah terinstal sebelumnya."
fi

# -------------------- 2. BACKUP KONFIGURASI ------------------

echo "[2/5] Membuat backup konfigurasi lama..."
BACKUP_DIR="/root/bind9-backup-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP_DIR"
[ -f /etc/bind/named.conf.local ] && cp -a /etc/bind/named.conf.local "$BACKUP_DIR/" 2>/dev/null || true

# -------------------- 3. KONFIGURASI ZONE --------------------

echo "[3/5] Mengatur deklarasi zone di named.conf.local..."

cat > /etc/bind/named.conf.local <<EOF
// Forward DNS Zone untuk $DOMAIN_NAME
zone "$DOMAIN_NAME" {
    type master;
    file "$FORWARD_FILE";
};

// Reverse DNS Zone untuk $REVERSE_ZONE_NAME
zone "$REVERSE_ZONE_NAME" {
    type master;
    file "$REVERSE_FILE";
};
EOF

# -------------------- 4. FORWARD & REVERSE DNS --------------------------

echo "[4/5] Membuat atau memperbarui file Database Zone..."

# Buat Forward Zone secara manual jika belum ada atau overwrite konfigurasi target
cat > "$FORWARD_FILE" <<EOF
\$TTL    604800
@   IN  SOA ns.$DOMAIN_NAME. root.$DOMAIN_NAME. (
            2026101301 ; Serial
            604800     ; Refresh
            86400      ; Retry
            2419200    ; Expire
            604800 )   ; Negative Cache TTL

@   IN  NS  ns.$DOMAIN_NAME.
@   IN  A   $SERVER_IP_ONLY
ns  IN  A   $SERVER_IP_ONLY
www IN  A   $SERVER_IP_ONLY
EOF

# Buat Reverse Zone secara manual jika belum ada atau overwrite konfigurasi target
cat > "$REVERSE_FILE" <<EOF
\$TTL    604800
@   IN  SOA ns.$DOMAIN_NAME. root.$DOMAIN_NAME. (
            1          ; Serial
            604800     ; Refresh
            86400      ; Retry
            2419200    ; Expire
            604800 )   ; Negative Cache TTL

@   IN  NS  ns.$DOMAIN_NAME.
$ip4 IN PTR ns.$DOMAIN_NAME.
EOF

# -------------------- 5. VALIDASI & AKTIFKAN SERVICE ---------------------

echo "[5/5] Memeriksa konfigurasi DNS dan mengaktifkan service..."

named-checkconf
named-checkzone "$DOMAIN_NAME" "$FORWARD_FILE"
named-checkzone "$REVERSE_ZONE_NAME" "$REVERSE_FILE"

systemctl enable --now bind9
systemctl restart bind9

echo ""
echo "=================================================="
echo " BIND9 DNS SERVER BERHASIL DIKONFIGURASI"
echo "=================================================="

systemctl --no-pager --full status bind9

echo ""
echo "Pengujian DNS lokal:"
dig @127.0.0.1 "$DOMAIN_NAME" +short
dig @127.0.0.1 "ns.$DOMAIN_NAME" +short
dig @127.0.0.1 -x "$SERVER_IP_ONLY" +short

echo "=================================================="

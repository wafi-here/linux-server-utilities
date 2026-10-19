#!/bin/bash

# ==========================================================
# INTERACTIVE DNS SERVER SETUP - BIND9 (NAMED)
# OS       : Ubuntu Server
# Service  : named
# ==========================================================

set -Eeuo pipefail

if [ "$(id -u)" -ne 0 ]; then
    echo "Error: Jalankan script menggunakan sudo."
    echo "Contoh: sudo ./setup-dns.sh"
    exit 1
fi

echo "=================================================="
echo " INTERACTIVE DNS SERVER SETUP (NAMED)"
echo "=================================================="

# -------------------- USER INPUTS -------------------------

read -p "Masukkan Domain Name [default: pas-paas.local]: " input_domain
DOMAIN_NAME="${input_domain:-pas-paas.local}"

read -p "Masukkan Server IP [default: 192.168.56.102]: " input_ip
SERVER_IP="${input_ip:-192.168.56.102}"

echo
echo "Pilih Mode Record DNS:"
echo "  1) standard (Record lengkap standar: server, host, client, www, ns1, admin)"
echo "  2) custom   (Masukkan hostname/subdomain tambahan secara dinamis)"
read -p "Pilihan Mode [1/2, default: 1]: " input_mode

DNS_RECORD_MODE="standard"
CUSTOM_HOSTS=""
if [ "$input_mode" = "2" ]; then
    DNS_RECORD_MODE="custom"
    read -p "Masukkan daftar hostname tambahan (pisahkan dengan spasi, cth: admin api app): " CUSTOM_HOSTS
fi

# -------------------- VALIDASI INPUT ----------------------

if ! [[ "$SERVER_IP" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
    echo "Error: Format IP address tidak valid."
    exit 1
fi

IFS='.' read -r ip1 ip2 ip3 ip4 <<< "$SERVER_IP"

for octet in "$ip1" "$ip2" "$ip3" "$ip4"; do
    if (( 10#$octet > 255 )); then
        echo "Error: IP address tidak valid."
        exit 1
    fi
done

if (( 10#$ip4 == 0 || 10#$ip4 == 255 )); then
    echo "Error: Gunakan IP host yang valid."
    exit 1
fi

if ! [[ "$DOMAIN_NAME" =~ ^[a-zA-Z0-9.-]+$ ]]; then
    echo "Error: Format domain tidak valid."
    exit 1
fi

DOMAIN_BASE="${DOMAIN_NAME%.}"
REVERSE_ZONE_NAME="${ip3}.${ip2}.${ip1}.in-addr.arpa"

FORWARD_FILE="/etc/bind/forward.${DOMAIN_BASE}"
REVERSE_FILE="/etc/bind/reverse.${DOMAIN_BASE}"

echo "=================================================="
echo " RINGKASAN KONFIGURASI:"
echo "=================================================="
echo "Domain       : $DOMAIN_NAME"
echo "Server IP    : $SERVER_IP"
echo "Record Mode  : $DNS_RECORD_MODE"
[ -n "$CUSTOM_HOSTS" ] && echo "Custom Hosts : $CUSTOM_HOSTS"
echo "Forward DB   : $FORWARD_FILE"
echo "Reverse zone : $REVERSE_ZONE_NAME"
echo "Reverse DB   : $REVERSE_FILE"
echo "=================================================="
read -p "Lanjutkan instalasi dan konfigurasi? (y/N): " confirm
if [[ ! "$confirm" =~ ^[yY]$ ]]; then
    echo "Instalasi dibatalkan oleh pengguna."
    exit 0
fi

# -------------------- INSTALASI BIND9 ---------------------

echo "[1/7] Menginstal BIND9..."[cite: 2]

export DEBIAN_FRONTEND=noninteractive

apt-get update
apt-get install -y bind9 bind9utils bind9-doc

# -------------------- BACKUP KONFIGURASI ------------------

echo "[2/7] Membuat backup konfigurasi..."[cite: 2]

BACKUP_DIR="/root/bind9-backup-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP_DIR"

cp -a /etc/bind/named.conf.local "$BACKUP_DIR/" 2>/dev/null || true
cp -a /etc/resolv.conf "$BACKUP_DIR/resolv.conf.bak" 2>/dev/null || true

# -------------------- KONFIGURASI ZONE --------------------

echo "[3/7] Mengatur named.conf.local..."[cite: 2]

cat > /etc/bind/named.conf.local <<EOF
// Forward DNS Zone
zone "$DOMAIN_NAME" IN {
    type master;
    file "$FORWARD_FILE";
};

// Reverse DNS Zone
zone "$REVERSE_ZONE_NAME" IN {
    type master;
    file "$REVERSE_FILE";
};
EOF

# -------------------- FORWARD DNS --------------------------

echo "[4/7] Membuat forward zone..."[cite: 2]

if [ "$DNS_RECORD_MODE" = "custom" ]; then
    # Mode Custom dengan dynamic host entries
    cat > "$FORWARD_FILE" <<EOF
\$TTL    604800
@       IN      SOA     ns.$DOMAIN_NAME. root.$DOMAIN_NAME. (
                              2         ; Serial
                         604800         ; Refresh
                          86400         ; Retry
                        2419200         ; Expire
                         604800 )       ; Negative Cache TTL

@       IN      NS      ns.$DOMAIN_NAME.
@       IN      A       $SERVER_IP
ns      IN      A       $SERVER_IP
www     IN      A       $SERVER_IP
EOF

    for host in $CUSTOM_HOSTS; do
        echo "$host    IN      A       $SERVER_IP" >> "$FORWARD_FILE"
    done
else
    # Mode Standard (lengkap sesuai panduan)
    cat > "$FORWARD_FILE" <<EOF
\$TTL    604800
@       IN      SOA     server.$DOMAIN_NAME. root.server.$DOMAIN_NAME. (
                              2         ; Serial
                         604800         ; Refresh
                          86400         ; Retry
                        2419200         ; Expire
                         604800 )       ; Negative Cache TTL

@       IN      NS      server.$DOMAIN_NAME.
@       IN      A       $SERVER_IP
server  IN      A       $SERVER_IP
host    IN      A       $SERVER_IP
client  IN      A       $SERVER_IP
www     IN      A       $SERVER_IP

@       IN      NS      ns1.$DOMAIN_NAME.
@       IN      A       $SERVER_IP
ns1     IN      A       $SERVER_IP

@       IN      MX      10 admin.$DOMAIN_NAME.
@       IN      A       $SERVER_IP
admin   IN      A       $SERVER_IP
EOF
fi

# -------------------- REVERSE DNS -------------------------

echo "[5/7] Membuat reverse zone..."[cite: 2]

if [ "$DNS_RECORD_MODE" = "custom" ]; then
    cat > "$REVERSE_FILE" <<EOF
\$TTL    604800
@       IN      SOA     ns.$DOMAIN_NAME. root.$DOMAIN_NAME. (
                              2         ; Serial
                         604800         ; Refresh
                          86400         ; Retry
                        2419200         ; Expire
                         604800 )       ; Negative Cache TTL

@       IN      NS      ns.$DOMAIN_NAME.
$ip4    IN      PTR     ns.$DOMAIN_NAME.
EOF
    for host in $CUSTOM_HOSTS; do
        echo "$ip4    IN      PTR     $host.$DOMAIN_NAME." >> "$REVERSE_FILE"
    done
else
    cat > "$REVERSE_FILE" <<EOF
\$TTL    604800
@       IN      SOA     server.$DOMAIN_NAME. root.server.$DOMAIN_NAME. (
                              2         ; Serial
                         604800         ; Refresh
                          86400         ; Retry
                        2419200         ; Expire
                         604800 )       ; Negative Cache TTL

@       IN      NS      server.$DOMAIN_NAME.
@       IN      PTR     $DOMAIN_NAME.
server  IN      A       $SERVER_IP
host    IN      A       $SERVER_IP
client  IN      A       $SERVER_IP
www     IN      A       $SERVER_IP
$ip4    IN      PTR     server.$DOMAIN_NAME.

@       IN      NS      ns1.$DOMAIN_NAME.
ns1     IN      A       $SERVER_IP
$ip4    IN      PTR     ns1.$DOMAIN_NAME.

@       IN      MX      10 admin.$DOMAIN_NAME.
admin   IN      A       $SERVER_IP
$ip4    IN      PTR     admin.$DOMAIN_NAME.
EOF
fi

# -------------------- PERMISSIONS & FIREWALL --------------

echo "Mengatur izin file dan firewall..."[cite: 2]

chown -R bind:bind /etc/bind
chmod -R 755 /etc/bind

if command -v ufw &> /dev/null; then
    ufw allow bind9
    ufw allow 53
    ufw allow 53/tcp
    ufw allow 53/udp
fi

# -------------------- RESOLV.CONF CONFIGURATION -----------

echo "[6/7] Mengonfigurasi /etc/resolv.conf..."[cite: 2]

cat > /etc/resolv.conf <<EOF
nameserver $SERVER_IP
search $DOMAIN_NAME
EOF

# -------------------- VALIDASI & SERVICE ------------------

echo "[7/7] Memeriksa konfigurasi dan memulai named..."[cite: 2]

named-checkconf -z /etc/bind/named.conf.local
named-checkzone "$DOMAIN_NAME" "$FORWARD_FILE"
named-checkzone "$REVERSE_ZONE_NAME" "$REVERSE_FILE"

systemctl enable --now named
systemctl restart named

echo
echo "=================================================="
echo " DNS SERVER BERHASIL DIKONFIGURASI"
echo "=================================================="

systemctl --no-pager --full status named

echo
echo "Pengujian DNS (ping / nslookup / dig):"[cite: 2]
if [ "$DNS_RECORD_MODE" = "custom" ]; then
    TEST_HOST="ns.$DOMAIN_NAME"
else
    TEST_HOST="server.$DOMAIN_NAME"
fi

echo "--- Testing Nslookup ---"
nslookup "$DOMAIN_NAME" || true
nslookup "$TEST_HOST" || true

echo
echo "DNS Server IP : $SERVER_IP"
echo "Domain        : $DOMAIN_NAME"
echo "Record Mode   : $DNS_RECORD_MODE"
[ -n "$CUSTOM_HOSTS" ] && echo "Custom Hosts : $CUSTOM_HOSTS"
echo "=================================================="

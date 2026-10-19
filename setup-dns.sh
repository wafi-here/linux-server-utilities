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
FQDN="${DOMAIN_NAME}"

FORWARD_FILE="/etc/bind/forward.${DOMAIN_BASE}"
REVERSE_FILE="/etc/bind/reverse.${DOMAIN_BASE}"

echo "=================================================="
echo " RINGKASAN KONFIGURASI:"
echo "=================================================="
echo "Domain       : $DOMAIN_NAME"
echo "FQDN Host    : $FQDN"
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

# -------------------- HOSTNAME & HOSTS SETUP --------------

echo "[1/9] Mengatur hostname dan /etc/hosts..."

hostnamectl set-hostname "$FQDN"

if ! grep -q "$FQDN" /etc/hosts; then
    cat >> /etc/hosts <<EOF

127.0.0.1   $FQDN server
$SERVER_IP  $FQDN server
EOF
fi

# -------------------- INSTALASI BIND9 ---------------------

echo "[2/9] Menginstal BIND9..."

export DEBIAN_FRONTEND=noninteractive

apt-get update
apt-get install -y bind9 bind9-utils bind9-doc

# -------------------- BACKUP KONFIGURASI ------------------

echo "[3/9] Membuat backup konfigurasi..."

BACKUP_DIR="/root/bind9-backup-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP_DIR"

cp -a /etc/bind/named.conf.options "$BACKUP_DIR/" 2>/dev/null || true
cp -a /etc/bind/named.conf.local "$BACKUP_DIR/" 2>/dev/null || true
cp -a /etc/resolv.conf "$BACKUP_DIR/resolv.conf.bak" 2>/dev/null || true

# -------------------- KONFIGURASI OPTIONS -----------------

echo "[4/9] Mengatur /etc/bind/named.conf.options..."

cat > /etc/bind/named.conf.options <<EOF
options {
    directory "/var/cache/bind";

    forwarders {
        $SERVER_IP;
    };

    dnssec-validation auto;
    listen-on { any; };
    allow-query { any; };
    allow-recursion { any; };
};
EOF

# -------------------- KONFIGURASI ZONE --------------------

echo "[5/9] Mengatur named.conf.local..."

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

echo "[6/9] Membuat forward zone..."

if [ "$DNS_RECORD_MODE" = "custom" ]; then
    cat > "$FORWARD_FILE" <<EOF
\$TTL    604800
@       IN      SOA     $FQDN. root.$FQDN. (
                              2         ; Serial
                         604800         ; Refresh
                          86400         ; Retry
                        2419200         ; Expire
                         604800 )       ; Negative Cache TTL

@       IN      NS      $FQDN.
@       IN      A       $SERVER_IP
server  IN      A       $SERVER_IP
www     IN      A       $SERVER_IP
EOF

    for host in $CUSTOM_HOSTS; do
        echo "$host    IN      A       $SERVER_IP" >> "$FORWARD_FILE"
    done
else
    cat > "$FORWARD_FILE" <<EOF
\$TTL    604800
@       IN      SOA     $FQDN. root.$FQDN. (
                              2         ; Serial
                         604800         ; Refresh
                          86400         ; Retry
                        2419200         ; Expire
                         604800 )       ; Negative Cache TTL

@       IN      NS      $FQDN.
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

echo "[7/9] Membuat reverse zone..."

if [ "$DNS_RECORD_MODE" = "custom" ]; then
    cat > "$REVERSE_FILE" <<EOF
\$TTL    604800
@       IN      SOA     $FQDN. root.$FQDN. (
                              2         ; Serial
                         604800         ; Refresh
                          86400         ; Retry
                        2419200         ; Expire
                         604800 )       ; Negative Cache TTL

@       IN      NS      $FQDN.
@       IN      PTR     $DOMAIN_NAME.
server  IN      A       $SERVER_IP
$ip4    IN      PTR     $FQDN.
EOF
    for host in $CUSTOM_HOSTS; do
        echo "$ip4    IN      PTR     $host.$DOMAIN_NAME." >> "$REVERSE_FILE"
    done
else
    cat > "$REVERSE_FILE" <<EOF
\$TTL    604800
@       IN      SOA     $FQDN. root.$FQDN. (
                              2         ; Serial
                         604800         ; Refresh
                          86400         ; Retry
                        2419200         ; Expire
                         604800 )       ; Negative Cache TTL

@       IN      NS      $FQDN.
@       IN      PTR     $DOMAIN_NAME.
server  IN      A       $SERVER_IP
host    IN      A       $SERVER_IP
client  IN      A       $SERVER_IP
www     IN      A       $SERVER_IP
$ip4    IN      PTR     $FQDN.

@       IN      NS      ns1.$DOMAIN_NAME.
ns1     IN      A       $SERVER_IP
$ip4    IN      PTR     ns1.$DOMAIN_NAME.

@       IN      MX      10 admin.$DOMAIN_NAME.
admin   IN      A       $SERVER_IP
$ip4    IN      PTR     admin.$DOMAIN_NAME.
EOF
fi

# -------------------- PERMISSIONS & FIREWALL --------------

echo "Mengatur izin file dan firewall..."

chown -R bind:bind /etc/bind
chmod -R 755 /etc/bind

if command -v ufw &> /dev/null; then
    ufw allow bind9
    ufw allow 53
    ufw allow 53/tcp
    ufw allow 53/udp
fi

# -------------------- RESOLV.CONF CONFIGURATION -----------

echo "[8/9] Mengonfigurasi /etc/resolv.conf..."

cat > /etc/resolv.conf <<EOF
nameserver 127.0.0.53
options edns0 trust-ad
nameserver $SERVER_IP
search $DOMAIN_NAME
EOF

# -------------------- VALIDASI & SERVICE ------------------

echo "[9/9] Memeriksa konfigurasi dan memulai named..."

named-checkconf
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
echo "Pengujian DNS (dig / nslookup):"
TEST_HOST="$FQDN"

echo "--- Testing Dig ---"
dig @127.0.0.1 "$DOMAIN_NAME" +short
dig @127.0.0.1 "$TEST_HOST" +short

echo "--- Testing Nslookup ---"
nslookup "$DOMAIN_NAME" || true
nslookup "$TEST_HOST" || true

echo
echo "Hostname      : $(hostname)"
echo "DNS Server IP : $SERVER_IP"
echo "Domain        : $DOMAIN_NAME"
echo "Record Mode   : $DNS_RECORD_MODE"
[ -n "$CUSTOM_HOSTS" ] && echo "Custom Hosts : $CUSTOM_HOSTS"
echo "=================================================="

#!/bin/bash

# Pastikan skrip dijalankan sebagai root (sudo)
if [ "$EUID" -ne 0 ]; then
  echo "[!] Harap jalankan skrip ini menggunakan sudo atau sebagai root."
  exit 1
fi

echo "=========================================================="
echo "  OTOMATISASI KONFIGURASI DHCP & NTP SERVER (UBUNTU 22.04)"
echo "=========================================================="

# 1. Direktori Backup untuk Mekanisme Rollback
BACKUP_DIR="/var/backups/dhcp_ntp_setup_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR"

# Fungsi Rollback jika terjadi kesalahan (Exception Handling)
rollback() {
    echo ""
    echo "[!] Terjadi kesalahan saat eksekusi perintah!"
    echo "[!] Melakukan pemulihan (rollback) berkas konfigurasi ke kondisi semula..."
    
    if [ -f "$BACKUP_DIR/isc-dhcp-server" ]; then
        cp "$BACKUP_DIR/isc-dhcp-server" /etc/default/isc-dhcp-server
    fi
    if [ -f "$BACKUP_DIR/dhcpd.conf" ]; then
        cp "$BACKUP_DIR/dhcpd.conf" /etc/dhcp/dhcpd.conf
    fi
    if [ -f "$BACKUP_DIR/chrony.conf" ]; then
        cp "$BACKUP_DIR/chrony.conf" /etc/chrony/chrony.conf
    fi
    
    echo "[!] Rollback selesai. Sistem dikembalikan seperti semula."
    exit 1
}

# Tangkap error (exit code != 0) untuk memicu rollback
trap rollback ERR

# 2. Deteksi Interface dan IP Jaringan yang Tersedia
echo ""
echo "[-] Mendeteksi interface jaringan yang tersedia..."
ip -o -4 addr show | awk '{print "    -> Interface: " $2 " | IP Address: " $4}'
echo ""

# 3. Input Parameter Dinamis dari Pengguna
read -p "Masukkan nama interface jaringan yang akan digunakan (contoh: enp0s3 / enp0s8): " INTERFACESV4
read -p "Masukkan alamat Network Subnet (contoh: 192.168.56.0): " SUBNET
read -p "Masukkan Netmask (contoh: 255.255.255.0): " NETMASK
read -p "Masukkan IP Range awal (contoh: 192.168.56.10): " RANGE_START
read -p "Masukkan IP Range akhir (contoh: 192.168.56.50): " RANGE_END
read -p "Masukkan IP Router / Gateway (contoh: 192.168.56.1): " ROUTER
read -p "Masukkan IP DNS Server (contoh: 8.8.8.8 atau IP Server): " DNS
read -p "Masukkan Network/CIDR untuk izin NTP Chrony (contoh: 192.168.56.0/24): " NTP_ALLOW

echo ""
echo "[-] Memulai proses instalasi dan konfigurasi..."

# 4. Backup Berkas Asli Sebelum Diubah
[ -f /etc/default/isc-dhcp-server ] && cp /etc/default/isc-dhcp-server "$BACKUP_DIR/"
[ -f /etc/dhcp/dhcpd.conf ] && cp /etc/dhcp/dhcpd.conf "$BACKUP_DIR/"
[ -f /etc/chrony/chrony.conf ] && cp /etc/chrony/chrony.conf "$BACKUP_DIR/"

# 5. Tantangan A: Instalasi Paket Layanan (apt update, isc-dhcp-server, chrony)
echo "[-] Memperbarui repositori paket..."
apt update -y

echo "[-] Menginstal isc-dhcp-server dan chrony..."
apt install -y isc-dhcp-server chrony

# 6. Tantangan B: Deklarasi Interface DHCP (Partial Overwrite pada /etc/default/isc-dhcp-server)[cite: 1]
echo "[-] Mengonfigurasi interface DHCPv4..."
if grep -q "^INTERFACESv4=" /etc/default/isc-dhcp-server; then
    sed -i 's/^INTERFACESv4=.*/INTERFACESv4="'"$INTERFACESV4"'"/' /etc/default/isc-dhcp-server
else
    echo 'INTERFACESv4="'$INTERFACESV4'"' >> /etc/default/isc-dhcp-server
fi

# 7. Tantangan C: Konfigurasi Subnet DHCP (Append Blok Subnet ke /etc/dhcp/dhcpd.conf)[cite: 1]
echo "[-] Menambahkan blok konfigurasi subnet ke dhcpd.conf..."
cat <<EOF >> /etc/dhcp/dhcpd.conf

# Konfigurasi Subnet Otomatis oleh Skrip Setup
subnet $SUBNET netmask $NETMASK {
  range $RANGE_START $RANGE_END;
  option routers $ROUTER;
  option domain-name-servers $DNS;
}
EOF

# 8. Tantangan D: Konfigurasi Akses NTP Chrony (Partial Overwrite / Append pada /etc/chrony/chrony.conf)[cite: 1]
echo "[-] Mengonfigurasi akses izin NTP pada chrony.conf..."
if grep -q "^allow " /etc/chrony/chrony.conf; then
    sed -i 's#^allow .*#allow '"$NTP_ALLOW"'#' /etc/chrony/chrony.conf
else
    echo "allow $NTP_ALLOW" >> /etc/chrony/chrony.conf
fi

# 9. Tantangan E: Aktivasi Layanan (Restart dan Cek Status)[cite: 1]
echo "[-] Merestart dan mengaktifkan layanan isc-dhcp-server dan chrony..."
systemctl restart isc-dhcp-server
systemctl enable isc-dhcp-server

systemctl restart chrony
systemctl enable chrony

# Matikan trap error karena seluruh proses berhasil
trap - ERR

echo ""
echo "=========================================================="
echo "  KONFIGURASI BERHASIL DITERAPKAN!"
echo "=========================================================="
echo "Status Layanan isc-dhcp-server:"
systemctl status isc-dhcp-server --no-pager | grep "Active:"
echo ""
echo "Status Layanan chrony:"
systemctl status chrony --no-pager | grep "Active:"
echo "=========================================================="

#!/bin/bash

# Pastikan script dijalankan sebagai root atau dengan hak akses sudo
if [ "$EUID" -ne 0 ]; then
  echo "[-] Harap jalankan skrip ini menggunakan sudo atau sebagai root."
  exit 1
fi

# Fungsi untuk menampilkan panduan penggunaan (Help)
usage() {
    echo "=================================================="
    echo "  AUTOMASI SETUP WEB SERVER & FTP SERVER (IaaS)  "
    echo "=================================================="
    echo "Penggunaan: sudo $0 [OPTIONS]"
    echo ""
    echo "Opsi Wajib:"
    echo "  -U, --user <username>       Username FTP / Sistem (Contoh: yolanda)"
    echo ""
    echo "Opsi Opsional:"
    echo "  -w, --webroot <path>        Direktori Web Root [Default: /var/www/html]"
    echo "  -u, --upgrade               Lakukan 'apt upgrade' (Pembaruan seluruh paket)"
    echo "  -h, --help                  Tampilkan panduan penggunaan ini"
    echo ""
    echo "Contoh Penggunaan:"
    echo "  sudo $0 -U yolanda"
    echo "  sudo $0 -U yolanda -w /var/www/html -u"
    exit 1
}

# Inisialisasi variabel
FTP_USER=""
WEB_ROOT="/var/www/html"
DO_UPGRADE="N"

# Parsing command-line arguments
while [[ "$#" -gt 0 ]]; do
    case $1 in
        -U|--user) FTP_USER="$2"; shift ;;
        -w|--webroot) WEB_ROOT="$2"; shift ;;
        -u|--upgrade) DO_UPGRADE="Y" ;;
        -h|--help) usage ;;
        *) 
            echo "[-] Peringatan: Argumen tidak dikenal: $1"
            echo "[!] Gunakan opsi '-h' atau '--help' untuk melihat cara penggunaan skrip yang benar."
            exit 1 
            ;;
    esac
    shift
done

# Validasi jika argumen wajib (FTP_USER) tidak diisi
if [ -z "$FTP_USER" ]; then
    echo ""
    echo "=================================================="
    echo " [!] PERINGATAN: Parameter Username Wajib Diisi!  "
    echo "=================================================="
    echo " Anda belum menentukan username untuk setup sistem."
    echo " Silakan gunakan opsi -U atau --user."
    echo ""
    echo " Contoh: sudo $0 -U yolanda"
    echo " Ketik 'sudo $0 --help' untuk informasi lengkap."
    echo "--------------------------------------------------"
    exit 1
fi

echo "=================================================="
echo "  AUTOMASI SETUP WEB SERVER & FTP SERVER (IaaS)  "
echo "=================================================="
echo "[+] Konfigurasi aktif menggunakan:"
echo "    - Username : $FTP_USER"
echo "    - Web Root : $WEB_ROOT"
echo "    - Upgrade  : $DO_UPGRADE"
echo "--------------------------------------------------"

# 1. Pembaruan Database Paket
echo "[1/9] Memperbarui database paket sistem..."
apt update -y

# 2. Pemasangan Web Server Apache2
echo "[2/9] Memasang engine Web Server (Apache2)..."[cite: 7]
apt install apache2 -y

# 3. Pembukaan Port Firewall UFW untuk Apache
echo "[3/9] Membuka izin port firewall untuk Apache..."[cite: 8]
ufw allow 'Apache'

# 4. Pengaktifan Firewall Sistem
echo "[4/9] Mengaktifkan proteksi firewall (UFW)..."[cite: 9]
ufw --force enable

# 5. Validasi Status Apache2
echo "[5/9] Memeriksa status layanan Apache2..."[cite: 10]
systemctl status apache2 --no-pager

# 6. Penyegaran dan Upgrade Sistem Utama (Opsional berdasarkan flag -u)
if [ "$DO_UPGRADE" = "Y" ]; then
    echo "[6/9] Melakukan pembaruan seluruh paket sistem operasi (apt upgrade)..."[cite: 11]
    apt upgrade -y
else
    echo "[6/9] Melewati proses apt upgrade (Gunakan flag -u jika ingin melakukan upgrade)."
fi

# 7. Penginstalan Service FTP (vsftpd)
echo "[7/9] Memasang peranti lunak FTP (vsftpd)..."[cite: 12]
apt install vsftpd -y

# 8. Registrasi Auto-Start Service vsftpd
echo "[8/9] Mengatur agar vsftpd berjalan otomatis saat booting..."[cite: 13]
systemctl enable vsftpd

# 9. Modifikasi Konfigurasi FTP dan Struktur Direktori
echo "[9/9] Mengonfigurasi vsftpd dan menyiapkan direktori chroot..."

# Cadangkan konfigurasi asli jika file backup belum ada
if [ ! -f /etc/vsftpd.conf.orig ]; then
    cp /etc/vsftpd.conf /etc/vsftpd.conf.orig
    echo "[+] Berhasil membuat backup konfigurasi ke /etc/vsftpd.conf.orig"
fi

# Mengaktifkan parameter konfigurasi vsftpd
sed -i 's/^#write_enable=YES/write_enable=YES/' /etc/vsftpd.conf
sed -i 's/^write_enable=NO/write_enable=YES/' /etc/vsftpd.conf
grep -q "^write_enable=YES" /etc/vsftpd.conf || echo "write_enable=YES" >> /etc/vsftpd.conf

sed -i 's/^#local_umask=022/local_umask=022/' /etc/vsftpd.conf
grep -q "^local_umask=022" /etc/vsftpd.conf || echo "local_umask=022" >> /etc/vsftpd.conf

sed -i 's/^#chroot_local_user=YES/chroot_local_user=YES/' /etc/vsftpd.conf
grep -q "^chroot_local_user=YES" /etc/vsftpd.conf || echo "chroot_local_user=YES" >> /etc/vsftpd.conf

# Menambahkan allow_writeable_chroot jika belum ada
grep -q "^allow_writeable_chroot=YES" /etc/vsftpd.conf || echo "allow_writeable_chroot=YES" >> /etc/vsftpd.conf

# Menambahkan konfigurasi tambahan di akhir file jika belum ada
grep -q "^user_sub_token=" /etc/vsftpd.conf || echo "user_sub_token=\$USER" >> /etc/vsftpd.conf
grep -q "^local_root=" /etc/vsftpd.conf || echo "local_root=/home/\$USER/ftp" >> /etc/vsftpd.conf
grep -q "^pasv_min_port=" /etc/vsftpd.conf || echo "pasv_min_port=4000" >> /etc/vsftpd.conf
grep -q "^pasv_max_port=" /etc/vsftpd.conf || echo "pasv_max_port=5000" >> /etc/vsftpd.conf

# Cek dan buat sistem user jika belum terdaftar
if id "$FTP_USER" &>/dev/null; then
    echo "[+] User sistem '$FTP_USER' sudah tersedia."
else
    echo "[+] Membuat user baru dengan nama: $FTP_USER"
    useradd -m -s /bin/bash "$FTP_USER"
    echo "Masukkan password untuk akun FTP ($FTP_USER):"
    passwd "$FTP_USER"
fi

# Penyusunan Struktur Folder Utama FTP
echo "[+] Menata direktori dan hak akses FTP untuk user: $FTP_USER..."
mkdir -p /home/$FTP_USER/ftp[cite: 15]
chown nobody:nogroup /home/$FTP_USER/ftp[cite: 16]
chmod a-w /home/$FTP_USER/ftp[cite: 17]

mkdir -p /home/$FTP_USER/ftp/upload[cite: 18]
chown $FTP_USER:$FTP_USER /home/$FTP_USER/ftp/upload/[cite: 19]
chmod 755 /home/$FTP_USER/ftp/upload[cite: 20]

# Memuat ulang layanan vsftpd
echo "[+] Me-restart layanan vsftpd..."
systemctl restart vsftpd && systemctl status vsftpd --no-pager[cite: 21]

echo "=================================================="
echo "  SETUP SELESAI DENGAN SUKSES!                   "
echo "=================================================="
echo "Informasi Alamat IP Server (Gunakan untuk akses Client):"
ip a | grep inet
echo "--------------------------------------------------"

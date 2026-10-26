#!/bin/bash

# Fungsi untuk menampilkan panduan bantuan (-h / --help)
show_help() {
  echo "===================================================="
  echo "  BANTUAN: OTOMATISASI KONFIGURASI FTP & SFTP SERVER"
  echo "===================================================="
  echo "Penggunaan:"
  echo "  sudo ./setup-ftp-server.sh [FTP_USER] [FTP_SUBDIR] [OWNER_USER]"
  echo "  sudo ./setup-ftp-server.sh -h | --help"
  echo ""
  echo "Argumen Wajib:"
  echo "  1. FTP_USER    : Nama user FTP/SFTP yang akan dibuat"
  echo "  2. FTP_SUBDIR  : Nama sub-direktori kerja di dalam direktori home"
  echo "  3. OWNER_USER  : Nama pemilik utama (owner) dari direktori tersebut"
  echo ""
  echo "Contoh Penggunaan:"
  echo "  sudo ./setup-ftp-server.sh iaas www yolanda"
  echo "===================================================="
  exit 0
}

# Cek argumen bantuan
if [[ "$1" == "-h" || "$1" == "--help" ]]; then
  show_help
fi

# Pastikan skrip dijalankan sebagai root (Superuser)[cite: 7]
if [ "$EUID" -ne 0 ]; then
  echo "[-] Error: Skrip ini harus dijalankan sebagai root! Gunakan 'sudo -s' atau 'sudo bash'."
  exit 1
fi

# Validasi: Jika argumen kurang dari 3, tampilkan alert/peringatan
if [ "$#" -lt 3 ]; then
  echo "===================================================="
  echo "[-] PERINGATAN: Argumen belum lengkap atau kosong!"
  echo "===================================================="
  echo "Anda harus memasukkan 3 parameter yang dibutuhkan."
  echo "Silakan gunakan opsi '-h' atau '--help' untuk melihat panduan."
  echo ""
  echo "Contoh cara menjalankan:"
  echo "  sudo ./setup-ftp-server.sh iaas www yolanda"
  echo "===================================================="
  exit 1
fi

# Tangkap parameter dari Command Line Arguments
FTP_USER="$1"
FTP_SUBDIR="$2"
OWNER_USER="$3"

echo "===================================================="
echo "  OTOMATISASI KONFIGURASI FTP & SFTP SERVER (IAAS)  "
echo "===================================================="
echo "[+] Konfigurasi Parameter Terpilih:"
echo "    - Target FTP User      : $FTP_USER"
echo "    - Target Sub-direktori : $FTP_SUBDIR"
echo "    - Pemilik Utama (Owner): $OWNER_USER"
echo ""

read -p "Apakah parameter di atas sudah benar? (y/n): " confirm
if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
  echo "Dibatalkan oleh pengguna."
  exit 0
fi

# 1. Update dan Instalasi vsftpd[cite: 8]
echo "[*] Menginstal paket vsftpd..."
apt update && apt install -y vsftpd

# 2. Penataan Konfigurasi VSFTPD[cite: 9]
echo "[*] Mengonfigurasi /etc/vsftpd.conf..."
VSFTPD_CONF="/etc/vsftpd.conf"
if [ -f "$VSFTPD_CONF" ]; then
  cp "$VSFTPD_CONF" "${VSFTPD_CONF}.bak"
fi

# Memastikan parameter konfigurasi disesuaikan
sed -i 's/^#*anonymous_enable=.*/anonymous_enable=NO/' "$VSFTPD_CONF"
sed -i 's/^#*local_enable=.*/local_enable=YES/' "$VSFTPD_CONF"
sed -i 's/^#*write_enable=.*/write_enable=YES/' "$VSFTPD_CONF"
sed -i 's/^#*local_umask=.*/local_umask=022/' "$VSFTPD_CONF"

# 3. Instalasi OpenSSH Server[cite: 10]
echo "[*] Menginstal openssh-server..."
apt install -y openssh-server

# 4. Pengaturan Subsistem SFTP di /etc/ssh/sshd_config[cite: 11]
echo "[*] Mengonfigurasi /etc/ssh/sshd_config untuk SFTP Chroot..."
SSHD_CONFIG="/etc/ssh/sshd_config"
cp "$SSHD_CONFIG" "${SSHD_CONFIG}.bak"

# Hapus konfigurasi match ftpaccess sebelumnya jika ada untuk menghindari duplikasi
sed -i '/# --- SFTP Config Start ---/,/# --- SFTP Config End ---/d' "$SSHD_CONFIG"

cat << 'EOF' >> "$SSHD_CONFIG"

# --- SFTP Config Start ---
Subsystem sftp internal-sftp
Match group ftpaccess
    ChrootDirectory %h
    X11Forwarding no
    AllowTcpForwarding no
    ForceCommand internal-sftp
# --- SFTP Config End ---
EOF

# 5. Pembaruan Layanan SSH[cite: 12]
echo "[*] Merestart layanan SSH..."
systemctl restart ssh

# 6. Pembuatan Grup Pengguna[cite: 13]
if ! getent group ftpaccess > /dev/null; then
  echo "[*] Membuat grup 'ftpaccess'..."
  groupadd ftpaccess
else
  echo "[*] Grup 'ftpaccess' sudah ada."
fi

# 7. Pembuatan Akun Pengguna Baru[cite: 14]
if ! id "$FTP_USER" &>/dev/null; then
  echo "[*] Membuat user baru '$FTP_USER'..."
  useradd -m "$FTP_USER" -g ftpaccess -s /usr/sbin/nologin
else
  echo "[*] User '$FTP_USER' sudah ada, menyesuaikan grup dan shell..."
  usermod -aG ftpaccess "$FTP_USER"
  usermod -s /usr/sbin/nologin "$FTP_USER"
fi

# 8. Penetapan Kata Sandi Pengguna[cite: 15]
echo "[*] Silakan tetapkan kata sandi untuk user '$FTP_USER':"
passwd "$FTP_USER"

# 9. Pengaturan Pemilik Direktori Utama[cite: 16]
echo "[*] Mengubah hak kepemilikan /home/$FTP_USER menjadi milik '$OWNER_USER'..."
chown "$OWNER_USER" "/home/$FTP_USER"

# 10. Pembuatan Sub-folder Kerja dan Pengaturan Hak Akses[cite: 17, 18, 20]
TARGET_DIR="/home/$FTP_USER/$FTP_SUBDIR"
echo "[*] Membuat sub-folder kerja: $TARGET_DIR..."
mkdir -p "$TARGET_DIR"

echo "[*] Mengatur ownership dan permissions..."
chown "$OWNER_USER:ftpaccess" "$TARGET_DIR"
chmod +rwx "/home/$FTP_USER"
chmod +rwx "$TARGET_DIR"

# Deteksi Alamat IP Server yang tersedia
SERVER_IPS=$(hostname -I)

echo "===================================================="
echo "  KONFIGURASI SELESAI DENGAN SUKSES!                "
echo "===================================================="
echo "Informasi Koneksi Klien (FileZilla):"
echo " - Alamat IP Server : ${SERVER_IPS:-Tidak dapat mendeteksi IP (Gunakan 'ip a' atau 'ifconfig')}"
echo " - Protokol         : SFTP (Port 22)"
echo " - Owner            : $OWNER_USER"
echo " - Password         : (Password yang baru saja Anda buat)"
echo " - Direktori        : $TARGET_DIR"
echo "===================================================="

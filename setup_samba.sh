#!/bin/bash

# ==============================================================================
# Nama Skrip    : setup_samba.sh
# Deskripsi     : Skrip otomatisasi setup Samba File Server (IaaS) dengan 
#                 validasi argumen wajib dan panduan bantuan (-h/--help).
# Syarat        : Harus dijalankan sebagai root atau menggunakan sudo.
# ==============================================================================

# Fungsi untuk menampilkan panduan bantuan (help)
show_help() {
  echo "=================================================="
  echo "      PANDUAN PENGGUNAAN - SETUP SAMBA SERVER     "
  echo "=================================================="
  echo "Penggunaan: sudo ./setup_samba.sh [OPSI]"
  echo ""
  echo "Opsi yang Wajib/Tersedia:"
  echo "  -u, --user <username>   Menentukan nama pengguna Samba & sistem"
  echo "  -g, --group <group>     Menentukan nama grup sistem"
  echo "  -s, --share <share>     Menentukan nama folder share / direktori"
  echo "  -h, --help              Menampilkan halaman bantuan ini"
  echo ""
  echo "Contoh Penggunaan:"
  echo "  sudo ./setup_samba.sh -u yolan -g yolan -s datakantor"
  echo "  sudo ./setup_samba.sh --user=admin --group=admin --share=public"
  echo "=================================================="
  exit 0
}

# Periksa jika pengguna tidak memasukkan argumen sama sekali
if [[ "$#" -eq 0 ]]; then
  echo "=================================================="
  echo "[-] PERINGATAN: Tidak ada argumen yang diberikan!" >&2
  echo "=================================================="
  echo "Skrip ini memerlukan parameter dinamis untuk konfigurasi." >&2
  echo "Silakan gunakan opsi '-h' atau '--help' untuk melihat panduan." >&2
  echo "" >&2
  echo "Contoh cara menjalankan:" >&2
  echo "  sudo ./setup_samba.sh -u <username> -g <group> -s <share_name>" >&2
  echo "  sudo ./setup_samba.sh --help" >&2
  echo "=================================================="
  exit 1
fi

# Inisialisasi variabel kosong
SAMBA_USER=""
SAMBA_GROUP=""
SHARE_NAME=""

# Parsing Argumen Baris Perintah
while [[ "$#" -gt 0 ]]; do
  case $1 in
    -u|--user) 
      SAMBA_USER="$2"
      shift 2 
      ;;
    -g|--group) 
      SAMBA_GROUP="$2"
      shift 2 
      ;;
    -s|--share) 
      SHARE_NAME="$2"
      shift 2 
      ;;
    -h|-help|--help) 
      show_help 
      ;;
    *) 
      echo "[-] Kesalahan: Opsi tidak dikenal '$1'." >&2
      echo "Gunakan opsi '--help' untuk melihat panduan penggunaan." >&2
      exit 1 
      ;;
  esac
done

# Validasi jika parameter penting terlewatkan saat pemanggilan
if [[ -z "$SAMBA_USER" || -z "$SAMBA_GROUP" || -z "$SHARE_NAME" ]]; then
  echo "[-] Kesalahan: Parameter -u (user), -g (group), dan -s (share) harus diisi lengkap!" >&2
  echo "Gunakan opsi '--help' untuk melihat panduan penggunaan." >&2
  exit 1
fi

TARGET_DIR="/home/$SHARE_NAME"

# Memeriksa apakah dijalankan sebagai hak akses root
if [ "$EUID" -ne 0 ]; then
  echo "[-] Kesalahan: Skrip ini harus dijalankan dengan hak akses root (sudo)." >&2
  exit 1
fi

echo "=================================================="
echo "      OTOMATISASI SETUP SAMBA FILE SERVER         "
echo "=================================================="
echo "[+] Ringkasan Parameter Konfigurasi:"
echo "    - Username    : $SAMBA_USER"
echo "    - Grup        : $SAMBA_GROUP"
echo "    - Nama Share  : [$SHARE_NAME]"
echo "    - Direktori   : $TARGET_DIR"
echo "=================================================="

# 1. Update dan Instalasi Paket Samba
echo "[1/8] Memperbarui repositori dan menginstal Samba..."
apt update && apt install -y samba
if [ $? -ne 0 ]; then
  echo "[-] Gagal menginstal paket Samba."
  exit 1
fi

# 2. Konfigurasi smb.conf
echo "[2/8] Menambahkan konfigurasi ke /etc/samba/smb.conf..."
if grep -q "\[$SHARE_NAME\]" /etc/samba/smb.conf; then
  echo "[!] Peringatan: Blok share [$SHARE_NAME] sudah ada di /etc/samba/smb.conf."
else
  cat << EOF >> /etc/samba/smb.conf

[$SHARE_NAME]
path = $TARGET_DIR
browseable = yes
writeable = yes
guest ok = yes
read only = no
EOF
  echo "[+] Konfigurasi berhasil ditambahkan ke smb.conf."
fi

# 3. Membuat Grup dan Pengguna Baru
echo "[3/8] Membuat grup dan pengguna sistem..."
if ! getent group "$SAMBA_GROUP" >/dev/null; then
  groupadd "$SAMBA_GROUP"
  echo "[+] Grup '$SAMBA_GROUP' berhasil dibuat."
else
  echo "[!] Grup '$SAMBA_GROUP' sudah ada."
fi

if ! id "$SAMBA_USER" &>/dev/null; then
  useradd -m "$SAMBA_USER" -g "$SAMBA_GROUP" -s /bin/bash
  echo "[+] Pengguna '$SAMBA_USER' berhasil dibuat."
else
  echo "[!] Pengguna '$SAMBA_USER' sudah ada."
fi

# 4. Mengatur Kata Sandi Sistem dan Samba
echo "[4/8] Mengatur kata sandi Linux untuk pengguna '$SAMBA_USER'..."
passwd "$SAMBA_USER"

echo "[+] Mengatur kata sandi Samba untuk pengguna '$SAMBA_USER'..."
smbpasswd -a "$SAMBA_USER"

# 5. Menyiapkan Folder Berbagi dan Hak Akses
echo "[5/8] Membuat direktori dan mengatur hak akses (permissions)..."
mkdir -p "$TARGET_DIR"
chmod 777 "$TARGET_DIR"
chown "$SAMBA_USER:$SAMBA_GROUP" "$TARGET_DIR"
echo "[+] Direktori $TARGET_DIR berhasil disiapkan dengan izin 777."

# 6. Konfigurasi Firewall (UFW) - Membuka Port Samba (139 & 445)
echo "[6/8] Mengonfigurasi UFW (membuka port 139 dan 445)..."
if command -v ufw &> /dev/null; then
  ufw allow 139/tcp
  ufw allow 445/tcp
  echo "[+] Aturan UFW untuk port Samba berhasil ditambahkan."
else
  echo "[!] UFW tidak terpasang atau tidak aktif, melewati konfigurasi firewall."
fi

# 7. Memuat Ulang Layanan Samba
echo "[7/8] Merestart layanan Samba (smbd)..."
systemctl restart smbd
if [ $? -eq 0 ]; then
  echo "[+] Layanan Samba berhasil direstart."
else
  echo "[-] Gagal merestart layanan Samba."
  exit 1
fi

# 8. Informasi Alamat IP Server
echo "[8/8] Memeriksa alamat IP Server..."
echo "--------------------------------------------------"
ip -c a || ifconfig
echo "--------------------------------------------------"

echo ""
echo "=================================================="
echo "       SETUP SAMBA FILE SERVER SELESAI!           "
echo "=================================================="
echo "Cara Akses dari Klien Windows:"
echo "  Buka File Explorer -> \\<IP_SERVER>\\$SHARE_NAME"
echo ""
echo "Cara Akses dari Klien Linux:"
echo "  sudo mkdir -p /mnt/share"
echo "  sudo mount -t cifs -o username=$SAMBA_USER //<IP_SERVER>/$SHARE_NAME /mnt/share"
echo "=================================================="

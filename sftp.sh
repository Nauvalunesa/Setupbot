#!/bin/bash

# =================================================================
# SFTP PRO MANAGER - WITH FILE PICKER & PASSWORD CACHEING
# =================================================================

# Warna UI
R='\033[0;31m'; G='\033[0;32m'; Y='\033[1;33m'; B='\033[0;34m'; P='\033[0;35m'; C='\033[0;36m'; NC='\033[0m'

# Variabel Sesi (Cache)
IP=""; USER=""; PORT="22"; PASS=""
REMOTE_CWD="/root"
LOCAL_CWD=$(pwd)

check_requirements() {
    if ! command -v sshpass &> /dev/null; then
        apt update && apt install sshpass -y
    fi
}

header() {
    clear
    echo -e "${C}=======================================================${NC}"
    echo -e "${C}      SFTP PRO MANAGER - BY NAUVAL.                    ${NC}"
    echo -e "${C}=======================================================${NC}"
    if [ ! -z "$IP" ]; then
        echo -e "${G} TARGET : $USER@$IP:$PORT ${NC}"
        echo -e "${B} REMOTE : $REMOTE_CWD ${NC}"
        echo -e "${B} LOCAL  : $LOCAL_CWD ${NC}"
    fi
    echo ""
}

setup() {
    header
    echo -e "${Y}[!] Masukkan Detail Koneksi VPS${NC}"
    read -p " Host/IP VPS : " IP
    read -p " User VPS    : " USER
    read -p " Port (22)   : " PORT
    PORT=${PORT:-22}
    echo -ne "${Y} Password    : ${NC}"
    read -s PASS
    echo ""

    echo -e "${Y}[*] Memvalidasi koneksi...${NC}"
    if sshpass -p "$PASS" ssh -p $PORT -o StrictHostKeyChecking=no -o ConnectTimeout=5 $USER@$IP "exit" 2>/dev/null; then
        echo -e "${G}[OK] Koneksi Berhasil!${NC}"
        sleep 1
    else
        echo -e "${R}[ERROR] Gagal Konek!${NC}"
        PASS=""; IP=""
        read -p "Tekan Enter untuk coba lagi..."
        setup
    fi
}

run_ssh() { sshpass -p "$PASS" ssh -p $PORT -o StrictHostKeyChecking=no $USER@$IP "$1"; }
run_scp_up() { sshpass -p "$PASS" scp -r -P $PORT -o StrictHostKeyChecking=no "$1" $USER@$IP:"$2"; }
run_scp_dl() { sshpass -p "$PASS" scp -r -P $PORT -o StrictHostKeyChecking=no $USER@$IP:"$1" "$2"; }

# --- FILE PICKERS ---

pick_remote() {
    while true; do
        header
        echo -e "${Y}Pilih File/Folder di Remote (VPS):${NC}"
        echo -e "0. [ KONFIRMASI / GUNAKAN FOLDER INI ]"
        echo -e ".. (Kembali ke folder atas)"
        
        # Ambil list file
        files=($(run_ssh "ls -1 $REMOTE_CWD"))
        
        i=1
        for f in "${files[@]}"; do
            echo -e "$i. $f"
            ((i++))
        done
        echo ""
        read -p "Pilih nomor atau ketik nama folder: " choice

        if [[ "$choice" == "0" ]]; then
            PICKED_REMOTE="$REMOTE_CWD"
            return
        elif [[ "$choice" == ".." ]]; then
            REMOTE_CWD=$(dirname "$REMOTE_CWD")
        elif [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -le "${#files[@]}" ]; then
            file="${files[$((choice-1))]}"
            PICKED_REMOTE="$REMOTE_CWD/$file"
            # Cek apakah itu direktori
            if run_ssh "[ -d '$PICKED_REMOTE' ]"; then
                REMOTE_CWD="$PICKED_REMOTE"
            else
                return # File terpilih
            fi
        else
            echo -e "${R}Pilihan tidak valid!${NC}"
            sleep 1
        fi
    done
}

pick_local() {
    while true; do
        header
        echo -e "${Y}Pilih File/Folder di Lokal:${NC}"
        echo -e "0. [ KONFIRMASI / GUNAKAN FOLDER INI ]"
        echo -e ".. (Kembali ke folder atas)"
        
        files=($(ls -1 $LOCAL_CWD))
        
        i=1
        for f in "${files[@]}"; do
            echo -e "$i. $f"
            ((i++))
        done
        echo ""
        read -p "Pilih nomor atau ketik nama folder: " choice

        if [[ "$choice" == "0" ]]; then
            PICKED_LOCAL="$LOCAL_CWD"
            return
        elif [[ "$choice" == ".." ]]; then
            LOCAL_CWD=$(dirname "$LOCAL_CWD")
        elif [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -le "${#files[@]}" ]; then
            file="${files[$((choice-1))]}"
            PICKED_LOCAL="$LOCAL_CWD/$file"
            if [ -d "$PICKED_LOCAL" ]; then
                LOCAL_CWD="$PICKED_LOCAL"
            else
                return # File terpilih
            fi
        else
            echo -e "${R}Pilihan tidak valid!${NC}"
            sleep 1
        fi
    done
}

# --- MAIN MENU ---

menu() {
    while true; do
        header
        echo -e "${B}--- MANAJEMEN ---${NC}          ${B}--- TRANSFER ---${NC}"
        echo -e "1.  ${C}LS${NC}    - List File     8.  ${G}UPLOAD${NC}   (Pilih File)"
        echo -e "2.  ${C}VIEW${NC}  - Baca File     9.  ${G}DOWNLOAD${NC} (Pilih File)"
        echo -e "3.  ${C}EDIT${NC}  - Edit (Nano)   10. ${G}V2V${NC}      (VPS to VPS)"
        echo -e "4.  ${C}CP${NC}    - Salin         --------------------------"
        echo -e "5.  ${C}MV${NC}    - Pindah/Rename 11. ${P}CHDIR${NC}    (Ganti Folder)"
        echo -e "6.  ${C}RM${NC}    - Hapus         12. ${P}RECON${NC}    (Ganti VPS)"
        echo -e "7.  ${C}MKDIR${NC} - Buat Folder   0.  ${R}EXIT${NC}     (Keluar)"
        echo ""
        read -p "Pilih menu [0-12]: " opt

        case $opt in
            1) run_ssh "ls -lah $REMOTE_CWD"; read -p "Enter...";;
            2) pick_remote; run_ssh "cat $PICKED_REMOTE"; echo ""; read -p "Enter...";;
            3) pick_remote; tmp="/tmp/edit_sftp"; run_scp_dl "$PICKED_REMOTE" "$tmp"; nano "$tmp"; run_scp_up "$tmp" "$PICKED_REMOTE"; rm "$tmp"; echo -e "${G}Update OK!${NC}"; sleep 1;;
            4) pick_remote; src=$PICKED_REMOTE; read -p "Tujuan (Full Path): " dst; run_ssh "cp -r $src $dst";;
            5) pick_remote; src=$PICKED_REMOTE; read -p "Nama Baru: " dst; run_ssh "mv $src $dst";;
            6) pick_remote; read -p "Yakin hapus $PICKED_REMOTE? (y/n): " conf; [[ "$conf" == "y" ]] && run_ssh "rm -rf $PICKED_REMOTE";;
            7) read -p "Nama Folder: " folder; run_ssh "mkdir -p $REMOTE_CWD/$folder";;
            8) # UPLOAD
                pick_local; L_FILE=$PICKED_LOCAL
                echo -e "${Y}File terpilih: $L_FILE${NC}"
                read -p "Kirim ke folder remote aktif? (y/n): " c_up
                if [[ "$c_up" == "y" ]]; then
                    run_scp_up "$L_FILE" "$REMOTE_CWD/"
                else
                    pick_remote; run_scp_up "$L_FILE" "$PICKED_REMOTE/"
                fi
                echo -e "${G}Upload Selesai!${NC}"; sleep 1;;
            9) # DOWNLOAD
                pick_remote; R_FILE=$PICKED_REMOTE
                echo -e "${Y}File terpilih: $R_FILE${NC}"
                read -p "Simpan di folder lokal aktif? (y/n): " c_dl
                if [[ "$c_dl" == "y" ]]; then
                    run_scp_dl "$R_FILE" "$LOCAL_CWD/"
                else
                    pick_local; run_scp_dl "$R_FILE" "$PICKED_LOCAL/"
                fi
                echo -e "${G}Download Selesai!${NC}"; sleep 1;;
            10) pick_remote; v1=$PICKED_REMOTE; read -p "User@IP Target: " target; read -p "Tujuan VPS Target: " v2; run_ssh "scp -r $v1 $target:$v2";;
            11) echo "1. Ganti Folder Remote  2. Ganti Folder Lokal"
                read -p "Pilihan: " c_dir
                [[ "$c_dir" == "1" ]] && pick_remote
                [[ "$c_dir" == "2" ]] && pick_local;;
            12) setup;;
            0) exit 0;;
        esac
    done
}

check_requirements
setup
menu


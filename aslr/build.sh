#!/bin/bash
set -e

# ================================
# LAB 별 변경 사항
#   1) NAME
#   2) COMMON/ON/OFF_OPT
#   3) ASLR 안내
# ================================

NAME="aslr"
LAB_NAME="$NAME-lab"
TMP_DIR="/tmp/$LAB_NAME"
SRC="sample.c"
BIN="$NAME"

# =====================
# 1. 디렉터리 준비
# =====================
echo "[*] build $LAB_NAME"

rm -rf "$TMP_DIR"
mkdir -p "$TMP_DIR"

# =====================
# 2. 소스코드 복사
# =====================
if [[ ! -f "$SRC" ]]; then
    echo "[!] source file not found: $SRC"
    exit 1
fi

cp "$SRC" "$TMP_DIR/"
echo "[+] source copied"

# =====================
# 3. 컴파일
# =====================
echo "[*] compiling binaries"

gcc -m32 "$TMP_DIR/$SRC" -o "$TMP_DIR/$BIN" \
    -O0 \
    -fno-stack-protector \
    -fno-omit-frame-pointer \
    -z noexecstack \
    -fno-pie -no-pie

echo "[+] build complete"

# =====================
# 4. 권한 설정
# =====================
if [[ $EUID -ne 0 ]]; then
    echo "[!] Not running as root. Skipping setuid setup."
else
    chown root:root "$TMP_DIR/$BIN"
    chmod 4755 "$TMP_DIR/$BIN"
fi

# =====================
# 5. 정보 출력
# =====================
echo ""
echo "[+] binary: $TMP_DIR/$BIN"
file "$TMP_DIR/$BIN"
checksec --file="$TMP_DIR/$BIN"

echo ""
echo "[!] Set ASLR if needed:"
echo "    echo 0 | sudo tee /proc/sys/kernel/randomize_va_space"
echo "    echo 2 | sudo tee /proc/sys/kernel/randomize_va_space"

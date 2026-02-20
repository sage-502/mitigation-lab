#!/bin/bash
set -e

# ================================
# LAB 별 변경 사항
#   1) NAME
#   2) COMMON/ON/OFF_OPT
#   3) ASLR 안내
# ================================

NAME="stack-canary"
LAB_NAME="$NAME-lab"
TMP_DIR="/tmp/$LAB_NAME"
SRC="sample.c"
BIN1="$NAME-off"
BIN2="$NAME-on"

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

# 공통 옵션
COMMON_OPT=(
    -m32
    -O0
    -fno-omit-frame-pointer
    -fno-pie
    -no-pie
    -z noexecstack
)

# 개별 옵션
OFF_OPT=(
    -fno-stack-protector
)

ON_OPT=(
    -fstack-protector-all
)

# OFF build
gcc "${COMMON_OPT[@]}" "${OFF_OPT[@]}" \
    "$TMP_DIR/$SRC" -o "$TMP_DIR/$BIN1"

# ON build
gcc "${COMMON_OPT[@]}" "${ON_OPT[@]}" \
    "$TMP_DIR/$SRC" -o "$TMP_DIR/$BIN2"

echo "[+] build complete"

# =====================
# 4. 권한 설정
# =====================
if [[ $EUID -ne 0 ]]; then
    echo "[!] Not running as root. Skipping setuid setup."
else
    chown root:root "$TMP_DIR/$BIN1" "$TMP_DIR/$BIN2"
    chmod 4755 "$TMP_DIR/$BIN1" "$TMP_DIR/$BIN2"
fi

# =====================
# 5. 정보 출력
# =====================
echo ""
echo "[+] $NAME disabled binary: $TMP_DIR/$BIN1"
file "$TMP_DIR/$BIN1"
checksec --file="$TMP_DIR/$BIN1"

echo ""
echo "[+] $NAME enabled binary: $TMP_DIR/$BIN2"
file "$TMP_DIR/$BIN2"
checksec --file="$TMP_DIR/$BIN2"

echo ""
echo "[!] Disable ASLR if needed:"
echo "    echo 0 | sudo tee /proc/sys/kernel/randomize_va_space"

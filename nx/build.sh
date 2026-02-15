#!/bin/bash
set -e

NAME="nx"
LAB_NAME="$NAME-lab"
TMP_DIR="/tmp/$LAB_NAME"
SRC="sample.c"
BIN1="$NAME-off"
BIN2="$NAME-on"

echo "[*] build $LAB_NAME"

# ---------------------------
# 1. /tmp 디렉터리 준비
# ---------------------------
echo "[*] preparing $TMP_DIR"
rm -rf "$TMP_DIR"
mkdir -p "$TMP_DIR"


# ---------------------------
# 2. 소스코드 복사
# ---------------------------
cp "$SRC" "$TMP_DIR/"
echo "[+] source copied"

# ---------------------------
# 3. 컴파일 (32bit)
# ---------------------------
echo "[*] compiling binary"

gcc -m32 "$TMP_DIR/$SRC" -o "$TMP_DIR/$BIN1" \
    -O0 \
    -fno-stack-protector \
    -z execstack \
    -no-pie \

gcc -m32 "$TMP_DIR/$SRC" -o "$TMP_DIR/$BIN2" \
    -O0
    -fno-stack-protector \
    -z noexecstack \ 
    -no-pie

echo "[+] build complete"

# ---------------------------
# 4. 권한 설정
# ---------------------------
chown root:root "$TMP_DIR/$BIN1" "$TMP_DIR/$BIN2"
chmod 2755 "$TMP_DIR/$BIN1" "$TMP_DIR/$BIN2"



# ---------------------------
# 5. 출력
# ---------------------------

echo "[+] mitigation disabled binary: $TMP_DIR/$BIN1"
echo ""
file $TMP_DIR/$BIN
echo ""
checksec --file=$TMP_DIR/$BIN

echo "[+] mitigation enabled binary: $TMP_DIR/$BIN2"
echo ""
file $TMP_DIR/$BIN
echo ""
checksec --file=$TMP_DIR/$BIN

echo ""
file $TMP_DIR/$BIN
echo ""
checksec --file=$TMP_DIR/$BIN

echo ""
echo "[!] Run this manually if needed:"
echo "    echo 0 | sudo tee /proc/sys/kernel/randomize_va_space"

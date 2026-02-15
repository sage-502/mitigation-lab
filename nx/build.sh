#!/bin/bash
set -e

NAME="nx"
LAB_NAME="$NAME-lab"
TMP_DIR="/tmp/$LAB_NAME"
SRC="sample.c"
BIN1="$NAME-off"
BIN2="$NAME-on"

echo "[*] build $LAB_NAME"

# 1. 디렉터리 준비
rm -rf "$TMP_DIR"
mkdir -p "$TMP_DIR"

# 2. 소스 복사
cp "$SRC" "$TMP_DIR/"
echo "[+] source copied"

# 3. 컴파일
echo "[*] compiling binaries"

# OFF
gcc -m32 "$TMP_DIR/$SRC" -o "$TMP_DIR/$BIN1" \
    -O0 \
    -fno-stack-protector \
    -fno-omit-frame-pointer \
    -z execstack \
    -fno-pie -fno-pic -no-pie

# ON
gcc -m32 "$TMP_DIR/$SRC" -o "$TMP_DIR/$BIN2" \
    -O0 \
    -fno-stack-protector \
    -fno-omit-frame-pointer \
    -z noexecstack \
    -fno-pie -fno-pic -no-pie


echo "[+] build complete"

# 4. 권한 설정
sudo chown root:root "$TMP_DIR/$BIN1" "$TMP_DIR/$BIN2"
sudo chmod 4755 "$TMP_DIR/$BIN1" "$TMP_DIR/$BIN2"

# 5. 출력
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

#!/bin/bash
set -e

echo "[*] mitigation-lab setup start"

# ---------------------------
# 1. 기본 패키지 설치
# ---------------------------
echo "[*] 기본 패키지 설치 시작"
apt update
apt install -y \
    gcc gdb make \
    git vim \
    checksec \
    file \
    binutils \
    strace ltrace
echo "[+] 기본 패키지 설치 완료"

# ---------------------------
# 2. 32bit 환경 지원
# ---------------------------
echo "[*] 32bit 환경 구성"
dpkg --add-architecture i386
apt update
apt install -y \
    libc6:i386 \
    libc6-dbg:i386 \
    gcc-multilib
echo "[+] 32bit 환경 구성 완료"

# ---------------------------
# 3. 분석용 계정 생성 (최소 권한)
# ---------------------------
echo "[*] baby 유저 생성 시작"
if id "baby" &>/dev/null; then
    echo "[+] user 'baby' already exists"
else
    echo "[*] baby 계정 생성..."
    adduser --disabled-password --gecos "" baby
fi

# sudo 그룹에서 제거
deluser baby sudo &>/dev/null || true
echo "[+] baby 유저 생성 완료"

# ---------------------------
# 4. ASLR 상태 안내
# ---------------------------
echo "[*] ASLR 현재 상태:"
cat /proc/sys/kernel/randomize_va_space

echo
echo "[!] ASLR on/off은 실습별로 직접 제어하세요."
echo "    예: echo 0 | sudo tee /proc/sys/kernel/randomize_va_space"

echo "[+] setup complete"

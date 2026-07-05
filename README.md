# mitigation-lab

바이너리 보호기법 공부 기록 모음집
</br>([pwnable-lab](https://github.com/sage-502/pwnable-lab)의 후속 실습)

이 레포는 각종 **바이너리 보호기법(mitigations)** 이 실제로 **어디에서 공격을 차단하는지**를 코드, 컴파일 옵션, 디버깅을 통해 확인하는 것을 목표로 한다.

- mitigation의 도입 배경, 구현 방식 및 작동 방식, 실습으로 구성
- 실습으로는 mitigation on/off 시의 바이너리를 동일 페이로드로 비교  
- 공격 실패가 정상, 익스플로잇보다는 **실패 원인 분석**에 집중
- gdb, readelf, objdump 기반 실습
- ubuntu 24.04, 32bit 환경 기준

※ 가상머신에서만 사용할 것을 추천.

---

## 구성

```
mitigation-lab/
├── setup.sh               // 실습 환경 세팅 스크립트
├── env.md                 // 공통 환경, ABI, 호출 규약 등
├── nx/
│   ├── sample.c           // 실습 소스코드
│   ├── build.sh           // 소스 빌드 스크립트
│   ├── payload.py         // 보호기법 동작 확인용 페이로드 (혹은 exploit.py)
│   └── README.md          // 보호기법 설명, 바이너리 분석
├── stack-canary/
├── aslr/
├── pie/
├── relro/
├── combo/
├── memo.md                // 메모
└── images/                // VM 스샷
```

---

## 학습 순서
1. [nx](https://github.com/sage-502/mitigation-lab/tree/main/nx)
2. [stack-canary](https://github.com/sage-502/mitigation-lab/tree/main/stack-canary)
3. [aslr](https://github.com/sage-502/mitigation-lab/tree/main/aslr)
4. [pie](https://github.com/sage-502/mitigation-lab/tree/main/pie)
5. [relro](https://github.com/sage-502/mitigation-lab/tree/main/relro)

---

## 사용법

### 1. 환경 설정 (setup.sh)

사용: `sudo bash setup.sh`

* 실습에 필요한 패키지, 툴, 32bit 환경 설치

### 2. 실습 바이너리 빌드 (build.sh)

사용: `sudo bash build.sh`

* 실습용 디렉터리 `/tmp/(보호기법)-lab` 생성
* 실습용 디렉터리에 `sample.c` 복사, `sample.c` 컴파일, 권한 설정</br>
  → 보호기법 ON, OFF 버전으로 총 2개의 바이너리가 생성됨
* `file`, `checksec` 결과가 함께 출력됨
* root권한으로 실행하지 않을 시 익스플로잇 성공 확인에서 루트(혹은 루트 그룹 쉘) 획득 확인이 어려움
* ASLR은 마지막에 출력되는 안내 문구에 따라 수동으로 설정

### 3. 실행 예시

```
git clone https://github.com/sage-502/mitigation-lab
cd mitigation-lab
sudo bash setup.sh    # 최초 1회만 실행

cd nx
sudo bash build.sh
```

실습 환경 세팅 완료, 분석 가능.

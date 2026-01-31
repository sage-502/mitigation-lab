# mitigation-lab

바이너리 보호기법 공부 기록 모음집
</br>([pwnable-lab](https://github.com/sage-502/pwnable-lab)의 후속 실습)

이 레포는 각종 **바이너리 보호기법(mitigations)** 이 실제로 **어디에서 공격을 차단하는지**를 코드, 컴파일 옵션, 디버깅을 통해 확인하는 것을 목표로 한다.

- 공격 실패가 정상
- 익스플로잇보다는 **실패 원인 분석**에 집중
- gdb, readelf, objdump 기반 실습
- ubuntu 24.04, 32bit 환경 기준

※ 가상머신에서만 사용할 것을 추천.

---

## 구성

```
mitigation-lab/
├── setup.sh               // 실습 환경 세팅 스크립트
├── env.md                 // 공통 환경, ABI, 호출 규약 등
├── stack-canary/
│   ├── vuln.c
│   ├── build.sh
│   ├── gdb.md             // 브레이크포인트, 관찰 포인트
│   └── notes.md           // 왜 막히는지
├── nx/
├── aslr/
├── pie/
├── relro/
└── combo/
    ├── canary+aslr/
    └── full-mitigations/
```

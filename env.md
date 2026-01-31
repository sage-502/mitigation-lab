# 실습 환경

이 문서는 mitigation-lab 전체에서 공통으로 사용하는
**실습 환경과 전제 조건**을 정리한 문서다.

각 실습 디렉터리에서는
이 문서의 내용을 기본 전제로 하며,
개별 실습에서 달라지는 설정은 별도로 명시한다.

---

## 1. 기본 환경

- OS: Ubuntu 24.04 LTS
- Architecture: x86 (32-bit)
- Compiler: gcc (multilib)
- Debugger: gdb

본 레포의 모든 실습은 **32bit 환경**을 기준으로 진행한다.

---

## 2. ABI / 호출 규약

- System V ABI
- x86 (32-bit), cdecl 호출 규약 사용

특징:
- 함수 인자는 **스택을 통해 전달**
- return address는 **스택에 저장**
- 호출자가 스택 정리 (caller cleanup)

따라서 스택 프레임, saved RET, local variable 분석이 용이하다.

---

## 3. 컴파일 관련 전제

별도 언급이 없는 한,
실습용 바이너리는 다음 옵션을 전제로 컴파일한다.

- `-O0`
- `-fno-omit-frame-pointer`

이는:
- 컴파일러 최적화로 인한 코드 변형을 최소화하고
- gdb에서 예측 가능한 스택 프레임 구조를 보기 위함이다.

---

## 4. 보호기법(Mitigations)에 대한 전제

이 레포는 **바이너리 보호기법이 실제로 공격을 어떻게 차단하는지**
확인하는 것을 목표로 한다.

다루는 보호기법:
- Stack Canary
- NX
- PIE
- ASLR
- RELRO

각 실습 디렉터리에는
어떤 보호기법이 켜져 있는지 / 꺼져 있는지를 명시한다.

※ 이 레포에서는 익스플로잇이 실패하는 것이 정상적인 결과일 수 있다.

---

## 5. ASLR 제어 방식

ASLR은 setup 스크립트에서 자동으로 변경하지 않는다.

실습 중 필요에 따라 직접 제어한다.

- ASLR ON
```

echo 2 | sudo tee /proc/sys/kernel/randomize_va_space

```

- ASLR OFF
```

echo 0 | sudo tee /proc/sys/kernel/randomize_va_space

```

각 실습에서는 ASLR 상태를 명확히 확인한 뒤 진행한다.

---

## 6. 디버깅 방식

- 모든 실습은 gdb를 사용하여 분석한다.
- 스택 프레임, 레지스터, 메모리 레이아웃을 직접 관찰한다.
- 자동화된 익스플로잇보다 **동작 원리 이해**에 초점을 둔다.

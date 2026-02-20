# Stack Canary

**Stack Canary**란 ret overwrite를 감지하기 위한 보호기법이다.</br>
이는 컴파일러의 코드 삽입으로 구현된다.

이 파트에서는 Stack Canary의 동작 방식에 대해 알아보고,</br>
실제 Stack Canary의 동작을 확인하는 것을 목표로 한다.

---

## 1. 등장 배경

### 1.1 RET overwrite 공격

Stack Canary가 등장하기 이전,
가장 대표적인 메모리 공격은 **Stack Buffer Overflow를 통한 RET overwrite**였다.

32-bit 기준 스택 프레임은 다음과 같다.

```
높은 주소
+----------------+
| saved RET      |
+----------------+
| saved EBP      |
+----------------+
| local buffer   |
| local buffer   |
+----------------+
낮은 주소
```

지역 버퍼(`buf`)를 넘쳐 쓰면,
결국 **saved RET까지 덮을 수 있다.**

공격자는 이 return address를 원하는 주소로 덮어
함수 종료 시점에 **control flow를 탈취**한다.

이 방식은 단순하면서도 강력했고,
오랫동안 가장 기본적인 exploit 기법으로 사용되었다.


### 1.2 Canary는 무엇을 막는가?

Stack Canary는
**saved RET이 덮이는 상황을 감지하기 위한 보호기법**이다.

핵심은 막는 것이 아니라
**RET이 사용되기 전에 이상을 감지하고 프로그램을 종료하는 것**이다.

즉,

* 버퍼 오버플로우 자체를 막는 것이 아니라
* **control flow가 변경되기 직전**에 프로그램을 강제 종료한다.

Stack Canary는
saved RET overwrite를 탐지하는 **센서 역할**을 한다.


### 1.3 Canary 도입 이후 공격의 변화

Canary가 도입된 이후,
단순한 BOF만으로는 RET hijacking이 어려워졌다.

공격자는 이제:

* Canary 값을 **알아내거나(leak)**
* Canary를 **우회하거나**
* Canary를 건드리지 않는 방식으로 공격

해야 한다.

즉, 공격은 단순 overwrite에서
**정보 유출 + 제어 흐름 탈취의 결합 구조**로 진화했다.

---

## 2. Canary 동작 방식 ── 컴파일러가 추가하는 것

Stack Canary는 하드웨어 기능이 아니다.

이 보호기법은
**컴파일러가 함수에 코드를 추가하는 방식으로 구현된다.**

`-fstack-protector` 계열 옵션이 활성화되면,
컴파일러는 각 함수의 prologue / epilogue에 canary 관련 코드를 삽입한다.


### 2.1 Prologue

함수 진입 시,
TLS에 저장된 canary 원본 값을 스택에 복사한다.

32-bit Linux 기준:

```asm
mov eax, gs:0x14
mov [ebp-0xc], eax
```

의미:

* `gs:0x14` → 현재 스레드의 TLS에 있는 canary 원본
* `[ebp-0xc]` → 스택 프레임 내 canary 복사본 저장 위치

즉, **원본은 TLS**에 보관하고, 함수마다 **스택에 복사본**을 둔다.


### 2.2 Epilogue

함수 종료 직전,
스택의 canary 복사본과 TLS의 원본을 비교한다.

```asm
mov eax, [ebp-0xc]
xor eax, gs:0x14
jne __stack_chk_fail
```

* 두 값이 같으면 → 정상 return
* 다르면 → `__stack_chk_fail()` 호출

이로 인해, **canary가 변조된 상태에서는 saved RET이 사용되지 않는다**.

프로그램은 다음과 같이 종료된다.

```
*** stack smashing detected ***: terminated
Aborted (core dumped)
```

> **노트 ── Canary 변조 확인 방식**
>
> 컴파일 옵션에 따라 `xor`, `sub`, `cmp` 등을 사용할 수 있다.

---

## 3. Canary의 위치

### 3.1 스택 배치 (32-bit 기준)

Canary가 활성화된 함수의 스택 구조:

```
높은 주소
+----------------+
| saved RET      |
+----------------+
| saved EBP      |
+----------------+
| canary 🐤      |
+----------------+
| local buffer   |
| local buffer   |
+----------------+
낮은 주소
```

지역 버퍼가 넘치면
saved RET에 도달하기 전에 **canary가 먼저 손상된다.**


### 3.2 스레드

운영체제에서 실제 실행 단위는 프로세스가 아니라 **스레드**이다.

스레드마다 다음이 독립적이다:

* Stack
* 레지스터 상태
* TLS

Stack Canary는 **스택을 보호하는 값**이므로
각 스레드마다 서로 다른 canary 값을 가진다.


### 3.3 TLS (Thread Local Storage)

Canary의 **원본 값**은 스택이 아니라
TLS(Thread Local Storage)에 저장된다.

이유:

* 스택은 공격자가 덮을 수 있음
* 원본은 안전한 위치에 있어야 함
* 스레드마다 독립적인 값이 필요함

32-bit Linux에서:

```
TLS + 0x14 → __stack_chk_guard
```

`gs` 세그먼트 레지스터는
현재 스레드의 TLS 베이스를 가리킨다.

따라서:

```asm
mov eax, gs:0x14
```

은 "현재 스레드의 canary 원본 값을 읽는다" 라는 의미다.


### 3.4 메모리 배치 개념도

프로세스 하나의 가상 메모리 구조:

```
높은 주소
+------------------------+
| Stack (thread별)       |
+------------------------+
| TLS (thread별)         |
+------------------------+
| Heap (공유)            |
+------------------------+
| .data / .bss (공유)    |
+------------------------+
| .text (공유)           |
+------------------------+
낮은 주소
```

스레드가 여러 개인 경우:

```
프로세스
 ├─ Thread 1
 │    ├─ Stack 1
 │    └─ TLS 1 (canary A)
 └─ Thread 2
      ├─ Stack 2
      └─ TLS 2 (canary B)
```

각 스레드는 서로 다른 canary 값을 가진다.

이를 풀어서 메모리 개념도로 보면:
```
높은 주소
+------------------------+
|  Stack (thread 1)      |
|                        |
|   [ saved RET ]        |
|   [ saved EBP ]        |
|   [ canary copy ] 🐤   |
|   [ local buf ]        |
+------------------------+
|  TLS (thread 1)        |
|   [ canary 원본 ] 🐤   | ← gs:0x14
+------------------------+
|  Heap                  |
+------------------------+
|  .data / .bss          |
+------------------------+
|  .text                 |
+------------------------+
낮은 주소
```

※ 본 그림은 개념 이해를 위한 논리적 배치도이며,
실제 가상 메모리 주소 공간은 연속적으로 배치되지 않을 수 있다.

---

## 4. Canary에 관여하는 주체

Stack Canary는 하나의 구성 요소가 아니라,
여러 단계가 협력하여 동작한다.


### 4.1 컴파일러

* Prologue / Epilogue에 canary 코드 삽입
* `__stack_chk_fail` 호출 코드 생성

→ Canary 로직을 **직접 삽입하는 주체**


### 4.2 링커

* `__stack_chk_fail`
* `__stack_chk_guard`

심볼을 libc와 연결한다.

→ 필요한 외부 심볼을 연결


### 4.3 로더 (ld-linux)

프로그램 시작 시:

* canary 값을 난수로 생성
* TLS에 저장

→ Canary 원본 초기화


### 4.4 커널

* 스레드 생성 시 TLS 영역 설정
* `gs` 레지스터 세팅

→ TLS 기반 접근이 가능하도록 환경 구성

---

## 5. 실습 구성

### 5.1 취약 코드

### 5.2 컴파일 옵션

### 5.3 보호기법 상태

---

## 6. Canary off 바이너리 분석

---

## 7. Canary on 바이너리 분석

---

## 8. 정리

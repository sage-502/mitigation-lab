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

※ 전작 pwnable-lab 레포지토리의 [fsb-canary-leak](https://github.com/sage-502/pwnable-lab/tree/main/fsb-canary-leak), [bof-fsb-canary-bypass](https://github.com/sage-502/pwnable-lab/tree/main/bof-fsb-canary-bypass) 참고

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
> 컴파일러 버전이나 옵션에 따라 `xor`, `sub`, `cmp` 등을 canary 변조 확인에 사용할 수 있다.</br>
> ※ 추측. `sub` 외에는 아직 확인 못함.

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

본 실습에서는 동일한 소스코드를 두 가지 방식으로 컴파일하여,
Stack Canary의 유무에 따른 동작 차이를 비교한다.

* Canary OFF 바이너리
* Canary ON 바이너리

두 바이너리는 Canary 유무만 다르고,
그 외 조건(NX, PIE 등)은 동일하게 유지한다.

이를 통해 동일한 payload가 왜 한쪽에서는 성공하고, 다른 쪽에서는 실패하는지 분석한다.

### 5.1 취약 코드

실습에 사용한 코드는 다음과 같다.

```c
#include<stdio.h>
#include<stdlib.h>
#include <unistd.h>

void win(){
    setreuid(geteuid(), geteuid());
    setregid(getegid(), getegid());
    system("/bin/sh");
}

void vuln(int value){
    char buf[16];

    puts("input:");
    read(0, buf, 64);

    printf("value: %d\n", value);
}

int main(){
    int num = 5;
    vuln(num);
}
```

#### 코드 특징

* `char buf[16]`
  → 고정 길이 버퍼

* `read(0, buf, 64)`
  → 16바이트 버퍼에 64바이트 입력 가능
  → **Stack Buffer Overflow 발생**

* `win()` 함수 존재
  → RET overwrite 성공 시 control flow 탈취 지점

이 구조는 전형적인 **ret2win 실습 형태**이다.


### 5.2 컴파일 옵션

동일한 소스코드를 다음 두 가지 방식으로 컴파일한다.

#### 1) Canary OFF

```bash
gcc -m32 sample.c -o stack-canary-off \
    -O0 \
    -fno-stack-protector \
    -fno-omit-frame-pointer \
    -no-pie \
    -z noexecstack
```

#### 2) Canary ON

```bash
gcc -m32 sample.c -o stack-canary-on \
    -O0 \
    -fstack-protector-all \
    -fno-omit-frame-pointer \
    -no-pie \
    -z noexecstack
```

#### 옵션 설명

| 옵션                        | 목적                    |
| ------------------------- | --------------------- |
| `-m32`                    | 32-bit 환경에서 컴파일       |
| `-O0`                     | 최적화 비활성화 (디스어셈 분석 용이) |
| `-fno-omit-frame-pointer` | EBP 유지 (스택 구조 확인 용이)  |
| `-no-pie`                 | 고정 주소 (ret2win 실습 편의) |
| `-z noexecstack`          | NX 유지                 |
| `-fstack-protector-all`   | 모든 함수에 Canary 삽입      |

두 바이너리의 차이는:

```
-fno-stack-protector
vs
-fstack-protector-all
```

이다.


### 5.3 보호기법 상태

`checksec` 결과는 다음과 같다.

#### Canary OFF

```
Canary: No canary found
NX:     Enabled
PIE:    No PIE
RELRO:  Partial
```

#### Canary ON

```
Canary: Canary found
NX:     Enabled
PIE:    No PIE
RELRO:  Partial
```

---


## 6. Canary off 바이너리 분석

Canary가 비활성화된 바이너리에서
Stack Buffer Overflow를 이용한 RET overwrite가 가능한지 확인한다.


### 6.1 Prologue 분석

`vuln()`의 디스어셈블 결과는 다음과 같다.

```asm
0x080491ec <+0>:  push   ebp
0x080491ed <+1>:  mov    ebp,esp
0x080491ef <+3>:  sub    esp,0x18
```

해석:

* 새로운 스택 프레임 생성
* 로컬 변수 영역으로 **0x18 (24 bytes)** 확보

`read()` 호출 부분:

```asm
0x08049207 <+27>: lea    eax,[ebp-0x18]
```

따라서:

* `buf` 시작 주소 → `[ebp-0x18]`

---

스택 구조 (Canary OFF):

```
높은 주소
+----------------+
| saved RET      |  
+----------------+ ← [ebp+4]
| saved EBP      |  
+----------------+ ← [ebp]
|                |
| local space    |
|                |
+----------------+
| buf[16]        |  
+----------------+ ← [ebp-0x18]
낮은 주소
```

이 상태에서는
`buf`와 `saved RET` 사이에 보호 장치가 존재하지 않는다.



### 6.2 Epilogue 분석

```asm
0x08049229 <+61>: leave
0x0804922a <+62>: ret
```

Canary 검증 코드가 존재하지 않는다.

즉, 함수 종료 시 아무런 무결성 검사가 수행되지 않는다.

따라서 `saved RET`이 덮여 있다면,
`ret` 명령은 그 값을 그대로 EIP에 로드한다.


### 6.3 Offset 계산

`buf` 시작:

```
[ebp-0x18]
```

`saved RET`:

```
[ebp+0x4]
```

거리 계산:

```
0x18 (buf → saved EBP)
+ 0x4 (saved EBP → saved RET)
= 0x1c
```

따라서: offset = 0x1c (28 bytes)


### 6.4 페이로드 작성

`win()` 함수 주소:

```
(gdb) info addr win
Symbol "win" is at 0x80491c6 in a file compiled without debugging.
```

최종 payload:

```
"A" * offset + win_addr
```

Python 스크립트:

```python
payload = b"A" * 0x1c
payload += struct.pack("<I", 0x080491c6)
```


## 6.5 페이로드 입력 결과

`ret` 직전에 브레이크를 설정한다.

```gdb
(gdb) b *0x0804922a
(gdb) r < <(python3 payload.py 0x080491c6)
```

한 단계 실행:

```gdb
(gdb) ni
```

결과:

```text
0x080491c6 in win ()
```

해석:

* `saved RET`이 `0x080491c6`으로 덮였다.
* `ret` 명령 실행 후 EIP가 `win()`으로 변경되었다.
* Control Flow Hijack 성공.

즉, Canary가 비활성화된 상태에서는:

* `buf` overflow를 통해 `saved RET`을 직접 덮을 수 있으며
* 함수 종료 시 별도의 무결성 검사가 없으므로
* 제어 흐름 탈취가 가능하다.

터미널에서 확인 시:
```
$ (python3 payload.py 0x80491b6;cat) | /tmp/stack-canary-lab/stack-canary-off
input:
value: 5
id
uid=0(root) gid=1000(name) groups=1000(name),4(adm),24(cdrom),27(sudo),30(dip),46(plugdev),100(users),114(lpadmin
```

---

## 7. Canary on 바이너리 분석

Canary가 활성화된 바이너리에서
동일한 payload가 왜 실패하는지 분석한다.


### 7.1 Prologue 분석

`vuln()`의 디스어셈블 결과:

```asm
0x08049218 <+0>:  push   ebp
0x08049219 <+1>:  mov    ebp,esp
0x0804921b <+3>:  sub    esp,0x38
0x08049224 <+12>: mov    eax,gs:0x14
0x0804922a <+18>: mov    DWORD PTR [ebp-0xc],eax
```

해석:

1. 로컬 변수 공간 0x38 (56 bytes) 확보
   → Canary 및 추가 로컬 변수 포함

2. `gs:0x14`에서 **canary 원본 값**을 읽어옴

3. 해당 값을 `[ebp-0xc]`에 저장
   → 스택 프레임에 **canary 복사본 생성**

스택 구조 (Canary ON): 

```text
높은 주소
+----------------+
| saved RET      |  
+----------------+ ← [ebp+4]
| saved EBP      |  
+----------------+ ← [ebp]
| canary 🐤      |  
+----------------+ ← [ebp-0xc]
| buf[16]        |  
+----------------+ ← [ebp-0x1c]
낮은 주소
```

이제 `buf`와 `saved RET` 사이에
**4바이트 canary가 삽입되었다.**

> **노트 ── `-O0`에서의 eax**
>
> Stack Canary가 추가되며 레지스터의 역할이 변경됨에 따라
> prologue에서 eax에 함수의 인자를 복사하는 줄이 추가되었다.
>
> 이는 -O0에서 레지스터 재사용 최적화가 수행되지 않기 때문에 나타난다.</br>
> ※ [appendix.md](https://github.com/sage-502/mitigation-lab/blob/main/stack-canary/appendix.md) 참조

### 7.2 Epilogue 분석

함수 종료 직전:

```asm
0x08049266 <+78>: mov    eax,DWORD PTR [ebp-0xc]
0x08049269 <+81>: sub    eax,DWORD PTR gs:0x14
0x08049270 <+88>: je     0x8049277 <vuln+95>
0x08049272 <+90>: call   0x8049060 <__stack_chk_fail@plt>
0x08049277 <+95>: leave
0x08049278 <+96>: ret
```

해석:

1. 스택의 canary 복사본을 읽음
2. TLS의 원본과 비교
3. 같으면 → 정상 `leave; ret`
4. 다르면 → `__stack_chk_fail()` 호출

즉, RET을 사용하기 직전에 무결성 검사를 수행한다.


### 7.3 동일 페이로드 입력

Canary OFF에서 사용한 동일 payload:

```text
"A" * offset + win_addr
```

를 Canary ON 바이너리에 입력한다.

※ canary가 삽입되어 스택 구조가 변경됨에 따라 offset 또한 0x20으로 변경되었다.

Canary ON 상태에서는 buf와 saved RET 사이에 4바이트 canary가 삽입되므로,
기존 offset(0x1c)으로 작성한 payload는 canary를 먼저 손상시킨다.

#### 입력 전 canary 값:

```gdb
x/wx $ebp-0xc
```

예:

```
0xffffcedc:  0xcdabbc00
```

#### 입력 후 canary 값:

```gdb
x/wx $ebp-0xc
```

결과:

```
0xffffcedc:  0x41414141
```

→ buffer overflow로 인해 canary가 손상됨.


### 7.4 실패 지점 확인

`__stack_chk_fail`에 브레이크 설정:

```gdb
b *__stack_chk_fail
r < <(python3 payload.py 0x080491c6)
```

실행 결과:

```text
*** stack smashing detected ***: terminated
Program received signal SIGABRT
```

Backtrace:

```text
#7  __stack_chk_fail ()
#8  0x08049277 in vuln ()
```

해석:

* `vuln()`의 epilogue에서 canary 비교 실패
* `__stack_chk_fail()` 호출
* 프로그램 즉시 종료
* `ret` 명령까지 도달하지 못함

---

## 8. 정리

| 항목                  | Canary OFF | Canary ON        |
| ------------------- | ---------- | ---------------- |
| buf → RET overwrite | 가능         | 가능               |
| RET 사용              | 수행됨        | 수행되지 않음          |
| win() 진입            | 성공         | 실패               |
| 종료 지점               | win()      | __stack_chk_fail |

Canary는:

* RET overwrite 자체를 막지 않는다.
* 하지만 RET이 사용되기 직전에 무결성 검사를 수행하여,
* 변조가 감지되면 프로그램을 종료한다.

즉, Canary는 **제어 흐름 변경을 감지하는 보호기법**이다.

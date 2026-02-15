# NX (No-eXecute)

**NX(No-eXecute)** 란 메모리 영역에 **실행 금지** 속성을 붙이는 보호기법이다.

이번 실습에서는 NX(No-eXecute)에 대해 알아보고, </br>
NX 활성 상태와 비활성 상태의 바이너리를 비교한다.

# 1. 등장 배경

## 1.1 과거의 스택 기반 공격

초기 Linux/x86 환경에서는 스택이 실행 가능(`rwx`)했다.

전형적인 공격 흐름:

1. 버퍼 오버플로우 발생
2. 스택 버퍼에 쉘코드 삽입
3. return address를 해당 쉘코드 주소로 덮음
4. 함수 리턴 → 스택의 쉘코드 실행

이 방식은 “코드 삽입(Code Injection)” 공격의 대표 사례였다.

---

## 1.2 왜 실행 권한 분리가 필요했나

스택과 힙은 **데이터 저장 영역**이다.
그런데 이 영역이 실행 가능하면:

* 사용자 입력이 그대로 “코드”가 될 수 있다.
* 데이터와 코드의 구분이 무너진다.

이를 해결하기 위해 등장한 개념이:

> **W^X (Write XOR Execute)**
> → 쓰기 가능하면 실행 불가
> → 실행 가능하면 쓰기 불가

NX는 이 정책을 하드웨어 수준에서 지원하는 기능이다.

---

## 1.3 NX 도입 이후 공격의 변화

NX 도입 이후:

* 스택 쉘코드 실행 ❌
* 힙 쉘코드 실행 ❌

하지만 이미 메모리에 존재하는 실행 가능한 코드(예: libc)는 여전히 실행 가능하다.

따라서 공격은 다음과 같이 변화했다:

* ret2libc
* ROP (Return Oriented Programming)
* syscall ROP

즉,

> NX는 “코드 삽입”을 막지만
> “코드 재사용”은 막지 못한다.

---

# 2. NX 동작 방식

## 2.1 메모리 권한과 페이지 단위 관리

리눅스에서 프로세스 메모리는 보통 다음과 같이 나뉜다:

| 영역                  | 일반적인 권한 |
| ------------------- | ------- |
| text                | r-x     |
| rodata              | r--     |
| data                | rw-     |
| bss                 | rw-     |
| heap                | rw-     |
| stack               | rw-     |
| shared library code | r-x     |

중요한 점:

> 권한은 “영역” 단위가 아니라 **페이지(page) 단위**로 설정된다.
> (보통 4KB)

`/proc/<pid>/maps`에서 보이는 예시:

```
08048000-08049000 r-xp  vuln
08049000-0804a000 r--p  vuln
0804a000-0804b000 rw-p  vuln
f7e00000-f7f00000 r-xp  libc.so
ffbdf000-ffc00000 rw-p  [stack]
```

여기서:

* r = read
* w = write
* x = execute
* p = private mapping (Copy-On-Write)

NX가 활성화되면:

* stack → `rw-`
* heap → `rw-`

즉, 실행 권한(`x`)이 없다.

---

## 2.2 CPU 내부 동작

NX는 CPU가 제공하는 기능이다.

페이지 테이블 엔트리(PTE)에는 실행 금지 비트(NX bit 또는 XD bit)가 존재한다.

CPU의 instruction fetch 과정:

1. RIP/EIP가 가리키는 주소의 페이지 확인
2. 해당 페이지의 실행 권한 확인
3. 실행 권한이 없으면 예외 발생

결과:

* Page Fault
* Linux에서는 보통 SIGSEGV 발생

즉,

> NX는 “실행 시점”에 CPU가 직접 차단하는 하드웨어 기반 보호기법이다.

---

## 2.3 권한을 정하는 주체

NX 동작에는 여러 구성 요소가 관여한다.

### 1) 컴파일러 / 링커

ELF 파일에는 `GNU_STACK` 세그먼트가 존재한다.

`readelf -l` 예시:

```
GNU_STACK      0x000000 0x000000 0x000000 0x000000 0x000000 RW  0x10
```

* RW  → 실행 불가 (NX 활성)
* RWE → 실행 가능 (NX 비활성)

컴파일 옵션:

```
-z noexecstack   // NX 활성
-z execstack     // 스택 실행 가능
```

---

### 2) 로더 (ld-linux)

프로그램 실행 시:

* ELF의 `PT_LOAD` 세그먼트 정보 확인
* `mmap` 호출로 각 세그먼트 매핑
* 해당 권한(r/w/x)으로 설정

---

### 3) 커널

커널은:

* 최종적으로 페이지 테이블에 R/W/X 비트를 설정
* CPU가 이를 기반으로 실행 여부 판단

---

### 4) 런타임 변경 (예외)

`mprotect()` 시스템 콜을 사용하면:

* 실행 중에도 페이지 권한 변경 가능

예:

```c
mprotect(addr, size, PROT_READ | PROT_WRITE | PROT_EXEC);
```

이 경우 NX가 켜져 있어도 해당 페이지는 실행 가능해진다.

이 지점은 NX 우회 실험에서 중요한 관찰 포인트가 된다.

---

# 3. NX 확인 방법

## 3.1 정적 분석 (바이너리 기준)

### checksec

```bash
checksec ./vuln
```

출력 예:

```
NX enabled
```

---

### readelf

```bash
readelf -l ./vuln | grep GNU_STACK
```

출력:

```
GNU_STACK      ...  RW
```

* RW  → NX 활성
* RWE → NX 비활성

---

## 3.2 동적 확인 (실행 중 프로세스 기준)

### /proc/<pid>/maps

```bash
cat /proc/<pid>/maps
```

stack 영역이:

```
rw-p  [stack]
```

이면 실행 불가.

만약:

```
rwxp
```

이면 실행 가능.

---

### gdb

```bash
info proc mappings
```

각 매핑의 권한을 직접 확인할 수 있다.

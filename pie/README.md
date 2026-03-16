# PIE (Position Independent Executable)

**PIE**는 실행 파일의 코드 영역(text)을 랜덤 주소에 로드할 수 있게 만드는 보호기법이다.</br>
즉, 실행 파일 자체의 base 주소가 실행마다 바뀐다.

이 파트에서는 PIE의 등장 배경과 동작 방식을 알아보고, PIE on/off 시의 바이너리를 비교해본다.

---

## 1. 등장 배경

### 1.1 코드 재사용 공격

NX가 도입되고 코드 주입 공격이 막히자, </br>
이미 메모리 어딘가에 존재하는 코드를 재활용하는 코드 재사용 공격이 등장했다.

대표적인 공격으로는 ret2libc, ROP 등이 있다.

예:
```
RET → system("/bin/sh")
```

이런 공격을 어렵게 하고자 ASLR 등장했다.

### 1.2 ASLR의 한계

ASLR은 stack, heap, 라이브러리의 base 주소를 랜덤화한다. </br>
하지만 프로그램의 코드 주소는 랜덤화하지 않아 항상 동일하다.

그래서 바이너리 내의 코드 주소를 알면
```
win() = 0x080491c6
RET → win()
```
과 같은 공격이 가능해진다.

PIE는 이러한 프로그램 내의 코드를 재사용하는 것을 어렵게 하기 위해 등장했다.

### 1.3 PIE가 막는 것

PIE가 적용된 바이너리는 ASLR 적용 시 실행 파일 코드의 주소 base도 랜덤화한다.</br>
정확히는 ASLR이 실행 파일 코드에도 적용되도록 만드는 보호기법이다.

PIE는 실행 파일을 shared library와 같은 ET_DYN 형태로 만들고,
ASLR 적용 시 실행 파일의 base 주소도 랜덤화되도록 한다. 

### 1.3 PIE 도입 이후 공격의 변화

PIE 도입 이후에는 base를 알아낸 후 공격을 수행하게 되었다. </br>
즉, PIE의 base를 leak하는 과정을 거쳐 exploit을 수행한다.

1. 주소 leak
2. base 계산
3. exploit

---

## 2. ELF header의 e_type

ELF header의 `e_type`은 로더와 커널이 해당 ELF를 어떻게 다룰지를 알려주는 정보를 담은 필드이다.</br>
PIE 적용 여부에 따라 해당 필드 값이 달라지므로 먼저 정리할 필요가 있다.

### 2.1 ELF header

이미 ASLR에서 구조는 보았으니, 대략적으로 보도록 하겠다.

#### ELF 파일의 기본 구조:

```
+---------------------------+
| ELF Header                |
+---------------------------+
| Program Header Table      |
+---------------------------+
| Section Header Table      |
+---------------------------+
| Section Data (.text 등)   |
+---------------------------+
```

#### ELF Header 구조:

```
+---------------------------+
| e_ident (매직 넘버 등)    |
| e_type (ET_EXEC / ET_DYN) |
| e_entry (entry point)     |
| e_phoff (PH 위치)         |
| e_shoff (SH 위치)         |
| e_phnum (PH 개수)         |
| e_shnum (SH 개수)         |
+---------------------------+
```

실제 구현 코드는 사용자 공간의 `/usr/include/elf.h` 에서 확인 가능하다.

``` c
typedef struct
{
  unsigned char	e_ident[EI_NIDENT];	/* Magic number and other info */
  Elf32_Half	e_type;			/* Object file type */
  ...
} Elf32_Ehdr;
```

### 2.2 e_type

ELF header에 있는 `e_type`은 이 파일이 어떤 종류의 ELF인가를 나타낸다.

대표적인 값:
| e_type      | 의미               | 용도            |
| ----------- | ---------------- | ------------ |
| **ET_REL**  | Relocatable file | `.o` 오브젝트 파일 |
| **ET_EXEC** | Executable file  | 일반 실행파일      |
| **ET_DYN**  | Shared object    | `.so`, PIE   |
| **ET_CORE** | Core dump        | 프로그램 크래시 덤프  |


`e_type`에 따라 Program Header의 `p_vaddr`가
**절대 주소로 해석되는지, base-relative 주소로 해석되는지**가 달라진다.

Program Header 코드 역시 `/usr/include/elf.h` 에서 확인 가능하다.

``` c
typedef struct
{
  Elf32_Word	p_type;			/* Segment type */
  Elf32_Off	p_offset;		/* Segment file offset */
  Elf32_Addr	p_vaddr;		/* Segment virtual address */
  ...
  Elf32_Word	p_align;		/* Segment alignment */
} Elf32_Phdr;
```

그리고 파일의 타입은 다음과 같이 확인 가능하다:

```
readelf -h filename
```

### 2.3 ET_REL (Relocatable file)

ET_REL은 relocatable object file을 의미하며,
주로 컴파일 단계에서 생성되는 `.o` 파일이 이에 해당한다.

이 타입의 ELF는 아직 메모리 주소가 확정되지 않았으며,
링커가 relocation을 수행하여 최종 실행 파일을 생성한다.


### 2.4 ET_EXEC (Executable file)

**non-PIE** 바이너리가 이 값을 `e_type`으로 가진다.</br>
이 경우 `p_vaddr`은 **실제 가상 주소**이다.

예:
```
Program Header: p_vaddr = 0x08048000
커널: mmap(0x08048000, ...)
결과: text = 0x08048000
```
커널이 `p_vaddr`을 그대로 매핑하여, `p_vaddr` 이 실제 가상 주소가 된다.

### 2.5 ET_DYN (Shared object)

**shared library 혹은 PIE**가 이 값을 e_type으로 가진다.</br>
이 경우 `p_vaddr`은 **offset**처럼 동작한다.

예:
```
Program Header: p_vaddr = 0x00001000
커널: base = 0x56555000
      real_address = base + p_vaddr
결과: text = 0x56556000
```
커널이 base를 정하고, base에 p_vaddr을 더하여 매핑한다.</br>
그래서 `p_vaddr`이 base 기준 offset 처럼 사용된다.

### 2.6 ET_CORE (Core dump)

이 타입은 프로그램이 크래시했을 때 생성되는 덤프 파일이다.

예: 
```
Segmentation fault (core dumped)
```
이때 생성되는 core 파일이 ET_CORE이다.

---

## 3. PIE 동작 방식

### 3.1 전체 흐름

PIE의 적용은 ASLR 적용 과정에서 함께 일어난다.

전체 흐름:
```
프로그램 실행 (`execve()`)
  ↓
커널이 ELF 로딩 (`load_elf_binary()`)
  ↓
ELF Header 읽기
  ↓
ELF Header의 e_type 확인
(ET_EXEC / ET_DYN 분기)
  ↓
Program Header 기반 mmap
  ↓
(이 단계에서 binary base 결정)
ET_EXEC → p_vaddr 그대로 매핑
ET_DYN  → load_bias + p_vaddr
  ↓
(ASLR 적용)
stack 랜덤화
libc 랜덤화
heap 랜덤화
```

ELF Header에서 e_type을 확인 후, ET_EXEC/ET_DYN로 분기가 생긴다.</br>
그리고 섹션 2에서 알아본 것과 같이 mmap을 수행하며 PIE가 적용된다. 

```
ET_EXEC → p_vaddr 그대로 사용
ET_DYN  → load_bias + p_vaddr
```

### 3.2 `static int load_elf_binary(struct linux_binprm *bprm)`

프로그램이 실행되면, 커널은 대략 다음과 같은 과정을 거쳐 `load_elf_binary` 호출한다.
```
sys_execve
  ↓
do_execveat_common
  ↓
exec_binprm
  ↓
search_binary_handler
  ↓
load_elf_binary
```

`load_elf_binary()`는 ELF 로딩 전체를 담당하는 함수이다.</br>
주요 동작은 다음과 같다.

1. ELF header 읽기
2. ELF 검증
3. Program Header 읽기
4. PT_LOAD 세그먼트 mmap
5. stack 설정
6. ld-linux 실행

이 함수에서 e_type에 따른 조건 분기 코드 확인이 가능하다.

### 3.3 실제 코드 발췌 (from [Linux kernel lfs/binfmt_elf.c](https://github.com/torvalds/linux/blob/master/fs/binfmt_elf.c), GPLv2)

e_type이 ET_EXEC 혹은 ET_DYN이 아니라면 out:
``` c
if (elf_ex->e_type != ET_EXEC && elf_ex->e_type != ET_DYN)
    goto out;
}
```

e_type에 따른 로딩:
``` c
if (!first_pt_load) {
    /* 첫 LOAD segment 처리 */
} else if (elf_ex->e_type == ET_EXEC) {
    /* non-PIE 로딩 */
} else if (elf_ex->e_type == ET_DYN) {
    /* PIE / shared object 로딩 */
}
```

ET_DYN 실행파일(PIE)의 경우 커널은 먼저 load_bias를 결정한다.

``` c
load_bias = ELF_ET_DYN_BASE;
```
ELF_ET_DYN_BASE는 커널이 PIE 프로그램을 로드할 기본 주소로,
일반적으로 0x555555554000 근처의 값이다.

load_bias는 ELF_ET_DYN_BASE를 기준으로 설정되며,
ASLR이 활성화된 경우 arch_mmap_rnd()를 통해 생성된
랜덤 오프셋이 추가된다.

``` c
if (current->flags & PF_RANDOMIZE)
    load_bias += arch_mmap_rnd();
```

이렇게 결정된 `load_bias`가 PIE의 base로 사용된다.

이후 Program Header의 p_vaddr는 실제 주소가 아닌 offset으로 해석되며, 
최종 매핑 주소는 다음과 같이 계산된다.

```
real_address = load_bias + p_vaddr
```

> **노트 ── PIC**
> 
> 이처럼 프로그램이 임의의 주소에서 실행되기 위해서는 코드가 특정 주소에 의존하지 않아야 한다.</br>
> 이를 위해 컴파일러는 Position Independent Code(PIC)를 생성한다.</br>
> PIC는 코드의 절대주소를 사용하지 않고, 현재 코드 위치 기준으로 주소를 계산한다.</br>
> 그래서 "위치 독립 코드"라고 부른다. </br>
> PIE는 이러한 PIC 방식으로 컴파일된 실행파일이다.

> **노트  ── 사용자 공간에서 확인법**
> 
> 실제 주소는 `/proc/<pid>/maps` 에서 확인 가능하다.
> 
> 예:
> ```
> /proc/<pid>/maps
> 
> 555555554000-555555556000 r--p vuln
> 555555556000-555555558000 r-xp vuln
> ```

---

## 4. 실습 구성

이번 실습에서는 간단한 BOF 취약점이 존재하는 소스코드를 
PIE on/off의 2가지 버전으로 빌드하여 동작을 비교한다. 

두 바이너리에 ret2win 기법을 사용한 동일 페이로드를 사용하여
왜 공격이 성공 혹은 실패하는지 확인하는 것을 목표로 한다.

### 4.1 취약 코드

``` c
// filename: sample.c
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

void win(){
    setregid(getegid(), getegid());
    system("/bin/sh");
}

void vuln(){
    char buf[24];
    puts("input:");
    gets(buf);
}

int main(){
    vuln();
}
```

#### 코드 특징

* `char buf[24]` : 고정 길이 버퍼
* `gets(buf)` : 입력 크기 제한 없음 → **Stack Buffer Overflow** 발생
* `win()` 함수 존재 → RET overwrite 성공 시 control flow 탈취 지점

### 4.2 컴파일 옵션

#### 1) PIE off

| 옵션         | 역할                  |
| ---------- | ------------------- |
| `-fno-pie` | 컴파일러 (PIC 코드 생성 안함) |
| `-no-pie`  | 링커 (ET_EXEC 생성)     |

#### 2) PIE on

| 옵션      | 역할             |
| ------- | -------------- |
| `-fPIE` | PIC 코드 생성      |
| `-pie`  | ET_DYN 실행파일 생성 |

#### 3) 공통

* `-m32`
* `-O0`
* `-fno-omit-frame-pointer`
* `-z noexecstack` : NX on
* `-fno-stack-protector` : Canary off
* `-Wl,-z,relro` / `-Wl,-z,lazy` : Partial RELRO

---

## 5. PIE off

### 5.1 vuln() 스택 프레임

프롤로그:

``` gdb
   0x080491dc <+0>:	push   ebp
   0x080491dd <+1>:	mov    ebp,esp
   0x080491df <+3>:	sub    esp,0x28
```

buf 주소:

``` gdb
   0x080491f5 <+25>:	lea    eax,[ebp-0x20]
   0x080491f8 <+28>:	push   eax
   0x080491f9 <+29>:	call   0x8049040 <gets@plt>
```

스택 레이아웃:

```
높은 주소
+--------------------+
|     saved RET      |
+--------------------+
|     saved EBP      |
+--------------------+ ← ebp
|         ...        |
+--------------------+
|                    | buf
+--------------------+ [ebp-0x20]
낮은 주소
```

### 5.2 익스플로잇

`vuln()`의 saved RET를 `win()` 주소로 overwrite하여 control flow를 변경한다.

#### offset

&buf가 ebp-0x20 이므로</br>
offset = 0x20 + 0x4(saved EBP size) = 0x24 (36bytes)

#### win() 주소

``` gdb
(gdb) info address win
Symbol "win" is at 0x80491a6 in a file compiled without debugging.
```

`win()` 함수 시작 주소 = 0x080491a6

#### 페이로드 구조

페이로드 구조는 다음과 같다.
```
payload = [padding] + [win() addr]
```

### 5.3 결과

`vuln()` 종료 후 `win()`함수로 점프된다:
```
$ (python3 payload.py;cat) | /tmp/pie-lab/pie-off
input:

id
uid=0(root) gid=1000(name) groups=1000(name),4(adm),24(cdrom),27(sudo),30(dip),46(plugdev),100(users),114(lpadmin)
```

payload 주입 전 gdb 확인:
```
(gdb) r
Starting program: /tmp/pie-lab/pie-off 
[Thread debugging using libthread_db enabled]
Using host libthread_db library "/lib/x86_64-linux-gnu/libthread_db.so.1".
input:
AAAA

Breakpoint 1, 0x08049203 in vuln ()
(gdb) x/wx $esp
0xffb8831c:	0x0804920f
(gdb) ni
0x0804920f in main ()
```
* saved RET로 `main()` 내부 주소
* `vuln()` 종료 후 `main()` 내부로 점프

payload 주입 후 gdb 확인:
```
(gdb) r < <(python3 payload.py)
The program being debugged has been started already.
Start it from the beginning? (y or n) y
Starting program: /tmp/pie-lab/pie-off < <(python3 payload.py)
[Thread debugging using libthread_db enabled]
Using host libthread_db library "/lib/x86_64-linux-gnu/libthread_db.so.1".
input:

Breakpoint 1, 0x08049203 in vuln ()
(gdb) x/wx $esp
0xff88957c:	0x080491a6
(gdb) ni
0x080491a6 in win ()
(gdb) 
```
* saved RET로 `win()` 내부 주소
* `vuln()` 종료 후 `win()` 내부로 점프

---

## 6. PIE on

---

## 7. 정리

PIE는 실행 파일을 `ET_DYN` 형태로 만들어 **실행 파일의 base 주소도 ASLR의 영향을 받도록 하는 보호기법**이다.

non-PIE(`ET_EXEC`)의 경우 Program Header의 `p_vaddr`가 **실제 가상 주소**로 사용되지만,
PIE(`ET_DYN`)에서는 `p_vaddr`가 **base 기준 offset**으로 해석된다.

커널은 실행 시 `load_bias`(PIE base)를 먼저 결정한 뒤 다음과 같이 실제 매핑 주소를 계산한다.

```
real_address = load_bias + p_vaddr
```

이 때문에 PIE가 적용된 환경에서는 실행 파일의 base 주소가 실행마다 달라지며,
공격자는 먼저 주소 leak을 통해 base를 계산한 후 exploit을 수행해야 한다.

```
1. 주소 leak
2. base 계산
3. exploit
```

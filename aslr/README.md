# ASLR

**ASLR (Address Space Layout Randomization)** 은
프로세스가 실행될 때마다 주요 메모리 영역의 주소를 랜덤화하는 보호기법이다.

이는 커널 수준에서 구현되며,
주소 예측에 기반한 공격을 어렵게 만드는 것을 목표로 한다.

이 파트에서는 ASLR의 등장 배경과 동작 방식,
그리고 ASLR이 공격에 어떤 영향을 주는지 확인한다.

---

## 1. 등장 배경

### 1.1 코드 재사용 공격

NX 도입 이전에는 스택에 쉘코드를 삽입하여 실행하는
코드 삽입(Code Injection) 공격이 일반적이었다.

그러나 NX가 도입되면서 스택/힙에서의 코드 실행이 차단되었다.

이에 따라 공격 방식은 다음과 같이 변화하였다.

```
코드 삽입 → 코드 재사용
```

대표적인 코드 재사용 공격은 다음과 같다.

* ret2libc
* ROP (Return Oriented Programming)

ret2libc는 saved return address를
libc 내부 함수의 주소로 덮어써 원하는 함수를 실행시키는 기법이다.

예를 들어:

```
[padding][system addr][fake RET]["/bin/sh"]
```

즉,

```
return address → system("/bin/sh")
```

이 방식은 이미 메모리에 존재하는 libc 코드를 재사용하므로
NX로 막을 수 없다.


### 1.2 ASLR이 막는 것

ret2libc가 가능하려면 전제가 하나 있다 :

공격자가 libc 내부 함수의 **정확한 주소를 알고 있어야 한다.**

ASLR이 비활성화된 환경에서는
libc base 주소가 고정되어 있다.

따라서:

```
system_addr = libc_base + offset_of_system
```

이 값이 항상 동일하다.

공격자는 이를 하드코딩하여 페이로드를 작성할 수 있다.

이를 어렵게 하기 위해 도입된 것이 ASLR이다.

ASLR은 다음과 같은 영역의 base 주소를 랜덤화한다.

* stack
* heap
* libc (mmap 영역)
* PIE 바이너리의 text 영역

즉, 
ASLR은 코드 재사용 자체를 막는 것이 아니라
코드 재사용에 필요한 **주소 예측을 어렵게 만든다.**


### 1.3 ASLR 도입 이후 공격의 변화

ASLR이 도입되자 단순한 ret2libc는 더 이상 안정적으로 동작하지 않게 되었다.

그러나 공격은 다음과 같이 진화하였다.

```
1. 정보 유출(leak)
2. base 계산
3. ret2libc 수행
```

예를 들어:

```
puts(puts@GOT) → 실제 libc puts 주소 유출
```

이 주소를 통해 libc base를 계산한 후
system 주소를 구해 다시 제어 흐름을 탈취한다.

즉, ASLR 이후 공격은
**정보 유출 + 제어 흐름 탈취** 구조로 발전하였다.

---

## 2. ASLR 동작 방식

ASLR은 실행 중에 적용되는 것이 아니라,
프로세스가 생성되는 시점에 적용된다.

전체 흐름은 다음과 같다.

```
execve()
  ↓
커널이 ELF 읽음
  ↓
Program Header 기반 mmap
  ↓  (이 시점에 ASLR 적용)
stack 랜덤화
libc 랜덤화
heap 랜덤화
  ↓
ld-linux가 relocation 수행
  ↓
main() 진입
```


### 2.1 사용자가 프로그램 실행

```
./vuln
```

내부적으로는 `execve()` 시스템 콜이 호출된다.


### 2.2 커널이 ELF 파일 읽기

커널은 ELF 파일의 전체 구조를 사용하는 것이 아니라,
실행에 필요한 최소한의 정보만을 읽는다.

특히 다음 두 구조가 중요하다:

* ELF Header
* Program Header Table

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
| e_ident (매직 넘버 등)     |
| e_type (ET_EXEC / ET_DYN) |
| e_entry (entry point)     |
| e_phoff (PH 위치)         |
| e_shoff (SH 위치)         |
| e_phnum (PH 개수)         |
| e_shnum (SH 개수)         |
+---------------------------+
```

커널은 이 중에서 특히:

* e_entry : 프로그램이 시작될 가상 주소(Entry Point) = CPU가 처음 점프할 주소
* e_phoff : ELF 파일 내에서 Program Header Table이 시작하는 파일 오프셋
* e_phnum : Program Header의 개수

을 사용한다.

#### Program Header Table 구조:

```
+--------------------------------------+
| Type (PT_LOAD 등)                   |
| Offset                               |
| Virtual Address (VirtAddr)           |
| File Size                            |
| Memory Size                          |
| Flags (R/W/X)                        |
+--------------------------------------+
```

커널은 Program Header의 `PT_LOAD` 항목을 기준으로
각 세그먼트를 `mmap()` 한다.

※ Section Header는 실행 시 사용되지 않는다.


실행 흐름:
```
execve()
  ↓
커널이 ELF Header 읽음
  ↓
e_phoff 확인
  ↓
e_phnum 만큼 Program Header 읽음
  ↓
PT_LOAD 세그먼트 mmap
  ↓
e_entry로 점프
```

### 2.3 커널이 메모리 배치 (ASLR 적용 시점)

커널은 Program Header의 `PT_LOAD` 세그먼트를 기준으로
각 영역을 `mmap()` 한다.

#### mmap()

`mmap()`은 파일이나 메모리 영역을 프로세스 가상 주소 공간에 연결(mapping)하는 시스템 콜이다.

mmap의 실제 호출 형태는 다음과 같다:

``` c
void *mmap(
    void *addr,
    size_t length,
    int prot,
    int flags,
    int fd,
    off_t offset
);
```

예시:

커널이 ELF를 실행할 때, 커널은 Program Header에서 다음과 같은 정보를 읽는다.
```
Type: PT_LOAD
Offset: 0x000000
VirtAddr: 0x08048000
FileSize: 0x1000
MemSize: 0x2000
Flags: R E
```

커널은 이걸 읽고 다음과 같이 매핑한다.
``` c
mmap(0x08048000,
     0x2000,
     PROT_READ|PROT_EXEC,
     MAP_PRIVATE|MAP_FIXED,
     fd,
     0x000000);
```

이것이 ELF 로딩에서의 mmap의 의미이다.

정리하자면 mmap은 다음과 같이 메모리를 할당한다.

1. 가상 메모리 영역(VMA) 생성
2. 페이지 테이블 설정
3. 실제 페이지는 접근 시 할당(lazy allocation)

#### 1) non-PIE (ET_EXEC)

* 고정 VirtAddr 사용
* base 고정

``` c
mmap(0x08048000, ...)
```

#### 2) PIE / 공유 라이브러리 (ET_DYN)

* VirtAddr가 0 기반
* 어느 위치에든 매핑 가능
* 커널이 랜덤 base 선택

``` c
mmap(NULL, ...)
```

이때 생성된 base 주소는
커널의 VMA 구조에 기록되며
`/proc/<pid>/maps`에서 확인할 수 있다.


### 2.4 stack 배치

커널은 스택 상단 주소를 랜덤화하고
초기 ESP를 해당 위치로 설정한다.

즉, 프로세스 생성 시

1. 커널이 stack용 VMA 생성
2. 랜덤 top 주소 설정

stack 배치는 전부 커널이 처리한다.

### 2.5 ld-linux(동적 링커)

#### 1) libc를 mmap

동적 링크 바이너리의 경우,
ld-linux(동적 링커)가 ELF 안에 있는 동적 섹션(.dynamic)을 보고 libc 등을 `mmap()` 한다.

이때 보는 것은 

* `PT_DYNAMIC`
* 그 안의 `DT_*` 엔트리들

이다.

실제 동작 흐름은 다음과 같다:

1. ld-linux가 main의 Program Header 읽음 : `PT_DYNAMIC` 위치 확인
2. dynamic section 파싱
3. DT_NEEDED 처리 : 필요한 라이브러리 정보 확인</br>
   해당 파일을 찾아 → open() → mmap() 호출</br>
   이때 커널이 랜덤 base 반환(ASLR 적용)</br>

즉, ld-linux가 필요한 라이브러리를 확인하고 mmap을 요청하면,
커널이 ASLR 정책에 따라 랜덤 base를 결정하여 반환한다.

#### 2) relocation

libc가 mmap되면 ld-linux는 각 라이브러리의 base를 기준으로
GOT, PLT 등의 실제 주소를 계산하여 채운다.

#### 3) main() 진입

이 시점에서 프로세스의 주소 공간은
이미 랜덤화가 완료된 상태이다.

ASLR은 프로세스 lifetime 동안 유지된다.

> **노트 ── ASLR의 주체**
>
> ASLR의 구현 주체는 커널이며, ld-linux는 ASLR을 활용하는 사용자 공간 프로그이다.
>
> 커널이 하는 일:
> 
> * `execve()` 처리
> * `mmap()` 처리
> * VMA 생성
> * 랜덤 base 선택
> * stack top 랜덤화
>
> ld-linux가 하는 일:
>
> * `DT_NEEDED` 확인
> * 라이브러리 파일 open
> * `mmap()` 요청 

---

## 3. base

### 3.1 랜덤 생성 방법

커널은 내부 난수 생성기인 CRNG (Cryptographically Secure RNG)를 사용하여
mmap base에 오프셋을 더한다.


| 개념            | 의미                        |
| ------------- | ------------------------- |
| mmap_base     | mmap 영역 시작 기준 주소          |
| random_offset | ASLR 난수                   |
| 최종 base       | mmap_base + random_offset |

CPU와 커널은 메모리를 페이지 단위로 관리하므로, 매핑 주소도 페이지 경계에 맞아야 한다. </br>
따라서 랜덤 값은 페이지 단위(보통 4KB)로 정렬된다.


### 3.2 base 저장 위치

#### 커널 메모리

리눅스 커널은 `mm_struct` 라는 memory descriptor를 만들어 각 프로세스에 할당하여 메모리를 관리한다.</br>
그리고 `mm_struct` 내부에는 각 영역 별로 `vm_area_struct`라는 구조체가 존재하며, 
그 구조체에 해당 영역의 정보들이 기록되어 있다. 

대략적인 구조:
```
struct task_struct
    └── struct mm_struct *mm
            ├── mmap        → VMA 연결 리스트(또는 트리)
            ├── mmap_base   → mmap 기준 주소
            ├── start_brk   → heap 시작
            ├── brk         → 현재 heap 끝
            ├── start_stack → 스택 시작 주소
            └── ...
```

그리고 우리가 base라고 부르는 것은 각 `vm_area_struct`의 `vm_start`로 저장되어 있는 값이다.

대략적인 구조:
```
struct vm_area_struct {
    unsigned long vm_start;   // 시작 주소
    unsigned long vm_end;     // 끝 주소
    unsigned long vm_flags;   // r/w/x
    struct file *vm_file;     // 파일 기반이면 파일 정보
    ...
};
```

즉, ASLR은 base 값을 따로 변수에 저장하는 것이 아니라, </br>
각 영역의 VMA를 생성할 때, `vm_start` 값을 랜덤하게 설정하는 것이다.

#### 사용자 공간

앞서 서술한 `mm_struct`는 커널 메모리에 있기 때문에 사용자 공간에서는 접근이 불가능하다.</br>
대신, `/proc` 인터페이스가 일부 정보를 노출하여 간접적으로 확인할 수 있다.

사용자 공간에서는 다음과 같은 방법으로 확인 가능하다.

| 확인 방법                    | 의미         |
| ------------------------ | ---------- |
| `/proc/<pid>/maps`       | VMA 목록     |
| `/proc/<pid>/smaps`      | VMA 상세 정보  |
| `gdb info proc mappings` | maps 기반 출력 |
| `/proc/<pid>/stat`       | 일부 mm 정보   |

---

## 4. 엔트로피 (Entropy)

엔트로피란 랜덤화된 주소가 가질 수 있는 비트 수를 의미한다.

즉, 가능한 경우의 수의 크기이다.

### 4.1 범위 제한 원인

ASLR이 완전 무작위가 아닌 이유는 다음과 같다.

* 32bit 주소 공간 한계
* 페이지 정렬 (하위 12비트 고정)
* mmap 영역 범위 제한

이로 인해 랜덤화 범위는 제한적이다.

### 4.2 32bit Linux ASLR 엔트로피

32bit 환경에서는 엔트로피가 비교적 낮다.

대략:

* stack: 약 16~19비트
* heap: 약 13~17비트
* mmap/libc: 약 8~16비트

### 4.3 brute force

엔트로피가 낮으면
brute force 공격이 가능해진다.

예를 들어 16비트라면:

```
2^16 = 65,536
```

fork 서버 환경에서는
현실적으로 시도 가능한 횟수이다.

---

## 5. 실습 구성

---

## 6. ASLR off 상태 바이너리 분석

---

## 7. ASLR on 상태 바이너리 분석

---

## 8. 정리

ASLR은:

* 코드 재사용을 막는 것이 아니라
* 주소 예측을 어렵게 만드는 보호기법이다.

NX, Canary와 비교하면 다음과 같다.

| 보호기법   | 역할        |
| ------ | --------- |
| NX     | 코드 삽입 차단  |
| Canary | RET 변조 감지 |
| ASLR   | 주소 예측 차단  |

ASLR 이후 공격은
정보 유출을 동반하는 형태로 진화하였다.

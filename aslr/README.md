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

커널은 ELF Header와 Program Header를 읽는다.

※ Section Header는 실행에 사용되지 않는다.



### 2.3 커널이 메모리 배치 (ASLR 적용 시점)

Program Header의 `PT_LOAD` 세그먼트를 기준으로
각 영역을 `mmap()` 한다.

#### 1) non-PIE (ET_EXEC)

* 고정 VirtAddr 사용
* base 고정

#### 2) PIE / 공유 라이브러리 (ET_DYN)

* VirtAddr가 0 기반
* 어느 위치에든 매핑 가능
* 커널이 랜덤 base 선택

이때 생성된 base 주소는
커널의 VMA 구조에 기록되며
`/proc/<pid>/maps`에서 확인할 수 있다.


### 2.4 stack 배치

커널은 스택 상단 주소를 랜덤화하고
초기 ESP를 해당 위치로 설정한다.


### 2.5 ld-linux 실행

동적 링크 바이너리의 경우,
ld-linux가 libc 등을 `mmap()` 한다.

이때도 커널이 랜덤 base를 반환한다.


### 2.6 relocation

ld-linux는 각 라이브러리의 base를 기준으로
GOT, PLT 등의 실제 주소를 계산하여 채운다.


### 2.7 main() 진입

이 시점에서 프로세스의 주소 공간은
이미 랜덤화가 완료된 상태이다.

ASLR은 프로세스 lifetime 동안 유지된다.

---

## 3. base

### 3.1 랜덤 생성 방법

커널은 내부 난수 생성기를 사용하여
mmap base에 오프셋을 더한다.

랜덤 값은 페이지 단위(보통 4KB)로 정렬된다.


### 3.2 base 저장 위치

랜덤화된 base 주소는:

* 커널의 VMA (Virtual Memory Area)
* mm_struct 내부 구조

에 저장된다.

사용자 공간에서는:

```
/proc/<pid>/maps
```

를 통해 확인 가능하다.

---

## 4. 엔트로피 (Entropy)

엔트로피란
랜덤화된 주소가 가질 수 있는 비트 수를 의미한다.

즉, 가능한 경우의 수의 크기이다.

---

### 4.1 범위 제한 원인

ASLR이 완전 무작위가 아닌 이유는 다음과 같다.

* 32bit 주소 공간 한계
* 페이지 정렬 (하위 12비트 고정)
* mmap 영역 범위 제한

이로 인해 랜덤화 범위는 제한적이다.

---

### 4.2 32bit Linux ASLR 엔트로피

32bit 환경에서는 엔트로피가 비교적 낮다.

대략:

* stack: 약 16~19비트
* heap: 약 13~17비트
* mmap/libc: 약 8~16비트

---

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

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

정적 링크는 필요한 라이브러리 코드를 실행 파일에 포함하는 방식이며,</br>
동적 링크는 실행 중 공유 라이브러리의 함수를 연결하여 사용하는 방식이다.

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

### 4.1 ELF 생성 시점

### 4.2 ELF 실행 시점

### 4.3 정리

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

---

## 5. RELRO의 종류

### 5.1 Full RELRO

### 5.2 Partial RELRO

---

## 6. 실습 구성

---

## 7. Full RELRO

---

## 8. Rartial RELRO

---

## 9. 정리

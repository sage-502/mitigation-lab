# Appendix ── 최적화 옵션에 따른 Stack Canary 코드 비교

본 부록에서는 동일한 소스코드를 `-fstack-protector-all` 옵션과 함께
서로 다른 최적화 옵션(`-O0`, `-O2`)으로 컴파일했을 때
Canary 관련 코드가 어떻게 달라지는지 비교한다.

### 소스코드

sample.c를 변경하지 않고, 최적화 옵션만 변경하여 컴파일 결과를 비교한다.

``` c
#include<stdio.h>
#include<stdlib.h>
#include <unistd.h>

void win(){
    setreuid(geteuid(), geteuid());
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

---

## A.1 -O0 vuln disassembly

```
gcc -m32 sample.c -O0 -fstack-protector-all -no-pie -o canary_O0
objdump -d -Mintel canary_O0 > O0.txt
```

### 1) Prologue

```asm
8049228: 55                push   ebp
8049229: 89 e5             mov    ebp,esp
804922b: 53                push   ebx
804922c: 83 ec 34          sub    esp,0x34
```

* 스택 프레임에서 로컬 영역 0x34 (52 bytes) 확보
* `push ebx` 때문에 4바이트 추가 사용


### 2) 함수 인자 복사

```asm
804923a: 8b 45 08          mov    eax,[ebp+0x8]
804923d: 89 45 d4          mov    [ebp-0x2c],eax
```

* `[ebp+8]` = 함수 인자 value
* `[ebp-0x2c]` = 로컬 복사본
* `-O0`라서 발생한 코드 생성 특징


### 3) Canary 복사

```asm
8049240: 65 a1 14 00 00 00 mov    eax,gs:0x14
8049246: 89 45 f4          mov    [ebp-0xc],eax
```

* `gs:0x14` → TLS에 저장된 canary 원본
* `[ebp-0xc]` → 스택에 복사본 저장


### 4) buf 위치

```asm
8049262: 8d 45 e4          lea    eax,[ebp-0x1c]
```

* `buf` 시작 = `[ebp-0x1c]`

### 5) `read`

``` asm
 8049260:	6a 40                	push   0x40
 8049262:	8d 45 e4             	lea    eax,[ebp-0x1c]
 8049265:	50                   	push   eax
 8049266:	6a 00                	push   0x0
 8049268:	e8 d3 fd ff ff       	call   8049040 <read@plt>
```

### 6) `printf`

```asm
 8049273:	ff 75 d4             	push   DWORD PTR [ebp-0x2c]
 8049276:	8d 83 23 e0 ff ff    	lea    eax,[ebx-0x1fdd]
 804927c:	50                   	push   eax
 804927d:	e8 ce fd ff ff       	call   8049050 <printf@plt>
```


### 7) Canary 검사

```asm
 8049286:	8b 45 f4             	mov    eax,DWORD PTR [ebp-0xc]
 8049289:	65 2b 05 14 00 00 00 	sub    eax,DWORD PTR gs:0x14
 8049290:	74 05                	je     8049297 <vuln+0x6f>
 8049292:	e8 69 00 00 00       	call   8049300 <__stack_chk_fail_local>
 8049297:	8b 5d fc             	mov    ebx,DWORD PTR [ebp-0x4]
 804929a:	c9                   	leave
 804929b:	c3                   	ret
```

의미:

1. 스택 canary 복사본 읽음
2. TLS 원본과 비교
3. je → 같으면 정상 리턴으로 점프, 다르면 fail 진행



---

## A.2 -O2 vuln disassembly

```
gcc -m32 sample.c -O2 -fstack-protector-all -no-pie -o canary_O2
objdump -d -Mintel canary_O2 > O2.txt
```

### 1) Prologue

```asm
 8049280:	56                   	push   esi
 8049281:	53                   	push   ebx
 8049282:	e8 c9 fe ff ff       	call   8049150 <__x86.get_pc_thunk.bx>
 8049287:	81 c3 6d 2d 00 00    	add    ebx,0x2d6d
 804928d:	83 ec 30             	sub    esp,0x30
```

* 기존 esi 백업 
* frame pointer(ebp) 생략
* 스택 프레임 0x30 (48 bytes) 확보
* `push ebx` 때문에 4바이트 추가 사용

### 2) Canary 복사

```asm
 8049290:	65 a1 14 00 00 00    	mov    eax,gs:0x14
 8049296:	89 44 24 28          	mov    DWORD PTR [esp+0x28],eax
```

* `gs:0x14` → TLS에 저장된 canary 원본
* `[esp+0x28]` → 스택에 복사본 저장
* ebp가 생략됨에 따라 esp를 기준으로 접근

frame pointer가 제거되었기 때문에,
함수 전체에서 esp를 기준으로 상대 오프셋을 계산한다.


### 3) 함수 인자 복사

```asm
 804929c:	8b 74 24 3c          	mov    esi,DWORD PTR [esp+0x3c]
```

* `[esp+0x3c]` = 함수 인자 value
* esi에 함수 인자를 저장하여 사용
* `-O2`라서 발생한 코드 생성 특징


### 4) buf 위치

```asm
 80492b0:	8d 44 24 24          	lea    eax,[esp+0x24]
```

* `buf` 시작 = `[esp+0x24]`

### 5) `__read_chk`

```asm
 80492ac:	6a 10                	push   0x10            ; buf size
 80492ae:	6a 40                	push   0x40            ; read size
 80492b0:	8d 44 24 24          	lea    eax,[esp+0x24]
 80492b4:	50                   	push   eax             ; buf
 80492b5:	6a 00                	push   0x0             ; fd
 80492b7:	e8 84 fd ff ff       	call   8049040 <__read_chk@plt>
```

* FORTIFY_SOURCE: canary와 별개로 gcc와 glibc 제공하는 보안 강화 기능
* `__read_chk(fd, buf, len, bufsize)` 형태로 호출됨
* 컴파일러가 버퍼 크기 초과 감지 코드 추가

이는 Stack Canary와는 별개로,
glibc의 _FORTIFY_SOURCE 강화 기능에 의해 삽입된 보호 코드이다.

### 6) `__printf_chk`

```asm
 80492bf:	8d 83 23 e0 ff ff    	lea    eax,[ebx-0x1fdd]
 80492c5:	56                   	push   esi
 80492c6:	50                   	push   eax
 80492c7:	6a 02                	push   0x2
 80492c9:	e8 d2 fd ff ff       	call   80490a0 <__printf_chk@plt>
```

* 이 역시 FORTIFY_SOURCE 관련


### 7) Canary 검사

```asm
 80492d1:	8b 44 24 1c          	mov    eax,DWORD PTR [esp+0x1c]
 80492d5:	65 2b 05 14 00 00 00 	sub    eax,DWORD PTR gs:0x14
 80492dc:	75 06                	jne    80492e4 <vuln+0x64>
 80492de:	83 c4 24             	add    esp,0x24
 80492e1:	5b                   	pop    ebx
 80492e2:	5e                   	pop    esi
 80492e3:	c3                   	ret
 80492e4:	e8 07 00 00 00       	call   80492f0 <__stack_chk_fail_local>
```

의미:

1. 스택 canary 복사본 읽음
2. TLS 원본과 비교
3. jne → 다르면 fail로 점프, 같으면 정상 리턴 진행

### 정리

-O2에서는 프레임 포인터가 제거되고 스택 접근 방식이 변경되지만,
Canary의 동작 구조(TLS 읽기 → 스택 저장 → 종료 직전 비교)는 동일하게 유지된다.

---

## A.3 차이점 분석

### 비교 요약

| 항목            | -O0        | -O2              |
| ------------- | ---------- | ---------------- |
| frame pointer | 사용         | 생략               |
| 주소 표현         | [ebp-...]  | [esp+...]        |
| read          | read@plt   | __read_chk@plt   |
| printf        | printf@plt | __printf_chk@plt |
| canary 논리     | 동일         | 동일               |

### canary 검사

-O0에서는 canary가 일치할 경우 분기(je)하여 정상 리턴으로 이동한다.</br>
반면 -O2에서는 불일치 시(jne)에만 분기하여 실패 루틴으로 이동하고,
정상 경로를 fall-through로 배치한다.

* -O0 방식: if (equal) jump success else fail
* -O2 방식: if (not equal) jump fail else success

이는 최적화 과정에서 정상 실행 경로를 직선 흐름으로 유지하기 위한 구조적 변화이다.

최적화 옵션에 따라 스택 프레임 구성, 레지스터 사용, 분기 구조는 달라질 수 있다.</br>
그러나 Stack Canary의 본질적인 동작(원본 읽기 → 스택 저장 → 종료 직전 비교 → 실패 시 종료)은
최적화 여부와 무관하게 동일하게 유지된다.

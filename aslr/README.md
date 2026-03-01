# ASLR

**ASLR (Address Space Layout Randomization)** 은 프로세스가 실행될 때마다 메모리 주소를 랜덤화하는 기법이다. </br>
이는 커널 수준에서 구현된다.

이 파트에서는 ASLR의 동작 방식에 대해 알아보고, ASLR의 영향을 확인하는 것을 목표로 한다.

---

## 1. 등장 배경

### 1.1 코드 재사용 공격

NX 도입 전에는 코드 삽입 공격 사용.
NX 도입 후 코드 삽입이 막히자 코드 재사용 공격을 하게 됨.
코드 재사용 공격의 대표적인 기법은 ret2libc, ROP 등이 있음.

ret2libc는 saved retrun address를 libc 내부 함수의 주소로 바꾸어 원하는 함수를 수행하도록 하는 기법.
이때 libc 주소가 고정이면 직접 특정 함수의 주소를 페이로드에 포함시켜 익스플로잇을 수행할 수 있음.
예를 들어 다음과 같음 페이로드로 `system("/bin/sh")`를 수행할 수 있다.

```
[padding][system addr][fake RET]["/bin/sh"]
```

즉,

```
return address → system("/bin/sh")
```

이 경우에는 이미 메모리에 있는 libc 코드를 재사용하므로, NX로 막을 수 없다.

### 1.2 ASLR이 막는 것

앞서 든 예시에서는 libc 내부 함수를 하드코딩.
이는 libc의 주소가 고정되어 있기 때문.
이처럼 메모리에 이미 있는 코드의 주소를 알 수 있다면 코드 재사용 공격에 활용 가능.

이를 어렵게 하기 위해 ASLR을 도입.
주요 메모리 영역의 base를 랜덤화

### 1.3 ASLR 도입 이후 공격의 변화

leak 어쩌구

---

## 2. base가 저장되는 위치

---

## 3. ASLR 동작 방식

```
execve()
 → 커널이 ELF 로딩
 → Program Header 읽음
 → mmap으로 메모리 배치 (이때 랜덤 오프셋 적용)
 → ld-linux 실행
 → ld-linux가 libc 등 매핑
 → relocation 수행
 → main() 진입
```

---

## 4. 엔트로피(entropy)

---

## 5. 실습 구성

---

## 6. ASLR off 상태 바이너리 분석

---

## 7. ASLR on 상태 바이너리 분석

---

## 8. 정리

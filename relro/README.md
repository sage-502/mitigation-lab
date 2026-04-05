# RELRO (Relocation Read-Only)

**RELRO**는 **GOT(Global Offset Table)** 을 보호하는 보호기법이다. </br>
이 파트에서는 링커와 relocation에 대해 알아보고, RELRO가 어떻게 GOT overwrite와 같은 공격을 방어하는지 알아본다.

---

## 1. 등장 배경

### 1.1 GOT overwrite

### 1.2 RELRO가 막는 것

### 1.3 RELRO 도입 이후 공격의 변화

---

## 2. PLT와 GOT

### 2.1 PLT

### 2.2 GOT

---

## 3. Relocation의 방식

### 3.1 eager binding

### 3.2 lazy binding

---

## 4. RELRO의 구현

전체 흐름:

```
gcc -Wl,-z,relro,-z,no

↓
컴파일러 → 링커 옵션 전달

↓
링커
→ PT_GNU_RELRO 생성
→ GOT 포함 영역 지정

↓
실행 (ld-linux)
→ relocation 수행
→ mprotect로 read-only 설정

↓
RELRO 적용 완료
```

### 4.1 컴파일러

### 4.2 링커

### 4.3 로더

---

## 5. 실습 구성

---

## 6. Full RELRO

---

## 7. Rartial RELRO

---

## 8. 정리

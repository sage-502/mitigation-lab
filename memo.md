# memo

메모장 :)

---

## Want to do

도입 순서대로

- [x] nx
  - 첫 시도라 좀 헤맸음.
  - 동작 방식 정리가 어려웠음 → 운영체제 과목 수강 후 보강이 필요할 것 같음

- [x] stack canary
  - abort 후 backtrace 했을 때 #11까지 나옴. 아직 잘 모르겠음. 필요하다는 거 일단 메모.
    -  Linux signal handling
    - abort() 내부 동작
    - glibc stack_chk_fail 구현
    - System V ABI (x86)
    - stack unwinding
- [x] aslr
  - 시간이 상당히 많이 들었음.
  - ASLR이 커널 구현이라 리눅스 프로세스 생성 과정을 봐야 했음.
  - 브루트포스 시도해보고 싶었는데, 엔트로피가 64bit 아키텍쳐로 나온 것 같음. 망함.
    - 실습을 하려면 애초에 32bit 아키텍쳐 VM을 설치해야 했을 것 같음.
- [ ] pie
- [ ] relro

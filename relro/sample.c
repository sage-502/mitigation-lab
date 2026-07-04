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

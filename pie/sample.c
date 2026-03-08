// filename: sample.c
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

void win(){
    setreuid(geteuid(), geteuid());
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

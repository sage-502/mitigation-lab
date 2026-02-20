#include<stdio.h>
#include<stdlib.h>
#include <unistd.h>

void win(){
    setregid(getegid(), getegid());
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

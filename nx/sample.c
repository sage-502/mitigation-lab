#include <stdio.h>
#include <unistd.h>

void vuln() {
    char buf[100];
    gets(buf);
}

int main() {
    setreuid(geteuid(), geteuid());
    vuln();
    return 0;
}

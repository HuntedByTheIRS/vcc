#include <stdio.h>
#include <string.h>
#include <stdlib.h>

int main(void) {
    char buf[16];
    memset(buf, 'x', 5);
    buf[5] = '\0';
    printf("%s %zu\n", buf, strlen(buf));
    memcpy(buf, "abc", 4);
    printf("%s\n", buf);
    printf("%d %d\n", strcmp("abc", "abc"), strcmp("abc", "abd"));
    printf("%.3f\n", (double)strtol("1234", NULL, 10) / 8);
    char *dot = strchr("a.b.c", '.');
    printf("%s\n", dot);
    return 0;
}

#include <stdio.h>

int table[8] = {0, 1, 4, 9, 16, 25, 36, 49};
const char *names[3] = {"zero", "one", "two"};
static long counter = 100;
char greeting[] = "hello";

int main(void) {
    int sum = 0;
    for (int i = 0; i < 8; i++) {
        sum += table[i];
    }
    printf("%d\n", sum);
    printf("%s %s %s\n", names[0], names[1], names[2]);
    counter += 23;
    printf("%ld\n", counter);
    printf("%s %zu\n", greeting, sizeof(greeting));
    int *p = table;
    printf("%d %d\n", *p, *(p + 5));
    return 0;
}

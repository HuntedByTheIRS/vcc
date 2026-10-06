#include <stdio.h>

// C99 line comment

int main(void) {
    long long big = 1000000000000LL;
    int i;
    for (i = 0; i < 2; i++) {
    }
    for (int j = 0; j < 3; j++) {
    }
    printf("%lld %d\n", big, i);
    struct S {
        int a, b;
    };
    struct S s = {.b = 2, .a = 1};
    printf("%d %d\n", s.a, s.b);
    int *p = (int[]){4, 5, 6};
    printf("%d\n", p[2]);
    return 0;
}

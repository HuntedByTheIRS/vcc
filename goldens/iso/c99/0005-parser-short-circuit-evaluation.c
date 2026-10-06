#include <stdio.h>

static int calls = 0;

static int truth(void) {
    calls++;
    return 1;
}

static int lie(void) {
    calls++;
    return 0;
}

int main(void) {
    int r;
    r = lie() && truth();
    printf("%d %d\n", r, calls);
    calls = 0;
    r = truth() || lie();
    printf("%d %d\n", r, calls);
    calls = 0;
    r = truth() && truth();
    printf("%d %d\n", r, calls);
    calls = 0;
    r = lie() || lie();
    printf("%d %d\n", r, calls);
    int x = 0;
    (void)(0 && (x = 5));
    printf("x=%d\n", x);
    return 0;
}

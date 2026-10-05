#include <stdio.h>

typedef unsigned long u64;

static u64 square(u64 x);
static u64 cube(u64 x);
static int gcd(int a, int b);

int main(void) {
    printf("%lu %lu\n", square(12), cube(5));
    printf("%d\n", gcd(1071, 462));
    return 0;
}

static u64 square(u64 x) {
    return x * x;
}

static u64 cube(u64 x) {
    return x * square(x);
}

static int gcd(int a, int b) {
    while (b) {
        int t = a % b;
        a = b;
        b = t;
    }
    return a;
}

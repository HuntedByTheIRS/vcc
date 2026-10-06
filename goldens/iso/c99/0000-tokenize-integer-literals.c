#include <stdio.h>

int main(void) {
    int dec = 42;
    int oct = 052;
    int hex = 0x2A;
    int bin = 0b101010;
    unsigned u = 42u;
    long l = 42L;
    unsigned long ul = 42UL;
    unsigned long long ull = 42ULL;
    long long neg = -42LL;
    printf("%d %d %d %d\n", dec, oct, hex, bin);
    printf("%u %ld %lu %llu %lld\n", u, l, ul, ull, neg);
    return 0;
}

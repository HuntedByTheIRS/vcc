/* __builtin_add_overflow and __builtin_mul_overflow */

#include <stdio.h>
#include <limits.h>

int main(void)
{
    int ires = 0, iover;
    long lres = 0, lover;
    unsigned int ures = 0, uover;
    unsigned long ulres = 0, ulover;

    iover = __builtin_add_overflow(1, 2, &ires);
    printf("%d %d\n", iover, ires);
    iover = __builtin_add_overflow(INT_MAX, 1, &ires);
    printf("%d %d\n", iover, ires);
    iover = __builtin_mul_overflow(100000, 100000, &ires);
    printf("%d %d\n", iover, ires);
    iover = __builtin_mul_overflow(-3, 5, &ires);
    printf("%d %d\n", iover, ires);

    lover = __builtin_add_overflow(5L, 7L, &lres);
    printf("%d %ld\n", lover, lres);
    lover = __builtin_add_overflow(LONG_MAX, 1L, &lres);
    printf("%d %ld\n", lover, lres);
    lover = __builtin_mul_overflow(LONG_MAX, 2L, &lres);
    printf("%d %ld\n", lover, lres);

    uover = __builtin_add_overflow(-1u, 0u, &ures);
    printf("%d %u\n", uover, ures);
    uover = __builtin_add_overflow(0xFFFFFFFFu, 1u, &ures);
    printf("%d %u\n", uover, ures);
    uover = __builtin_mul_overflow(70000u, 70000u, &ures);
    printf("%d %u\n", uover, ures);

    ulover = __builtin_mul_overflow(0x100000000UL, 0x100000000UL, &ulres);
    printf("%d %lu\n", ulover, ulres);
    ulover = __builtin_add_overflow(1UL, 2UL, &ulres);
    printf("%d %lu\n", ulover, ulres);
    return 0;
}

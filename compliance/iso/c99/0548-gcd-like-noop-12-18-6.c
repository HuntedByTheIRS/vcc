/* 0548: CHECK(gcd_like_noop(12, 18) == 6);
 *
 * monolithic.c:11258 (numerics)
 */

#include <stdio.h>

static int gcd_like_noop(int a, int b);

static int gcd_like_noop(int a, int b)
{
    while (b != 0) {
        int t = a % b;
        a = b;
        b = t;
    }
    return a;
}

#define CHECK(...)                                                            \
    do {                                                                      \
        if (!(__VA_ARGS__)) {                                                 \
            printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #__VA_ARGS__);      \
            return 1;                                                         \
        }                                                                     \
    } while (0)

int main(void)
{
    CHECK(gcd_like_noop(12, 18) == 6);
    return 0;
}

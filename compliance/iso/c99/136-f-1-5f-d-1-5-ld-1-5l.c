/* 136: CHECK(f == 1.5f && d == 1.5 && ld == 1.5L);
 *
 * monolithic.c:9815 (types)
 */

#include <stdio.h>

#define CHECK(...)                                                            \
    do {                                                                      \
        if (!(__VA_ARGS__)) {                                                 \
            printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #__VA_ARGS__);      \
            return 1;                                                         \
        }                                                                     \
    } while (0)

int main(void)
{
    long double ld = 1.5L;
    float f = 1.5f;
    double d = 1.5;
    CHECK(f == 1.5f && d == 1.5 && ld == 1.5L);
    return 0;
}

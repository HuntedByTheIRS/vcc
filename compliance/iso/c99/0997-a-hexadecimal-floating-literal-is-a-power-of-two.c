/* 0997: CHECK(0x1p4 == 16.0 && 0x1.8p1 == 3.0);
 *
 * not in monolithic.c: added after the corpus was split, so it has no line there.
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
    double a = 0x1p4;
    double b = 0x1.8p1;
    double c = 0x1.0p-1;
    CHECK(a == 16.0);
    CHECK(b == 3.0);
    CHECK(c == 0.5);
    CHECK(0x1p10 == 1024.0);
    return 0;
}

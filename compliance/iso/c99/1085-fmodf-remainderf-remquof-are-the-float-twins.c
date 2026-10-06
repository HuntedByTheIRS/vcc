/* 1085: fmodf-remainderf-remquof-are-the-float-twins
 *
 * ISO/IEC 9899:1999 7.12.10.1: the fmod functions return the value x - n *
 * y for an integral n.
 */

#include <math.h>

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
    int q = 0;
    float r = remquof(7.0f, 2.0f, &q);
    CHECK(fmodf(7.0f, 2.0f) == 1.0f);
    CHECK(fmodl(7.0L, 2.0L) == 1.0L);
    CHECK(remainderf(7.0f, 2.0f) == -1.0f);
    CHECK(remainderl(7.0L, 2.0L) == -1.0L);
    CHECK(r == -1.0f && (q & 3) == 0);
    return 0;
}

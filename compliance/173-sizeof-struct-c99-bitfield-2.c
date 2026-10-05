/* 173: CHECK(sizeof(struct c99_bitfield) >= 2);
 *
 * monolithic.c:9868 (types)
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
    struct c99_bitfield {
            unsigned int a : 3;   /* unsigned bitfield */
            signed int b : 5;     /* signed bitfield */
            _Bool c : 1;          /* _Bool bitfield is a C99 addition */
            unsigned int : 0;     /* unnamed zero-width bitfield: alignment */
            unsigned int d : 2;
        } bf = {5u, -3, 1, 1u};
    CHECK(f == 1.5f && d == 1.5 && ld == 1.5L);
    CHECK(sizeof ld == sizeof(long double) && sizeof f == sizeof(float));
    CHECK(bf.a == 5u && bf.c == 1u && bf.d == 1u);
    CHECK(sizeof(struct c99_bitfield) >= 2);
    return 0;
}

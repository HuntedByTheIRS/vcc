/* 972: CHECK(vals[0] == -56 && vals[1] == 200);
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
    signed char signed_narrow = -56;
    unsigned char unsigned_narrow = 200;
    int vals[2];
    /* A value of a type narrower than int is converted to int in arithmetic,
     * so the signed one stays negative and the unsigned one is 200 rather than
     * -56. */
    vals[0] = signed_narrow * 1;
    vals[1] = unsigned_narrow * 1;
    CHECK(vals[0] == -56);
    CHECK(vals[1] == 200);
    CHECK(sizeof(signed_narrow + 0) == sizeof(int));
    return 0;
}

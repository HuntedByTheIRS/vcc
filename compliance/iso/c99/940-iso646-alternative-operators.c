/* 940: CHECK(1 and 1) ... CHECK(a xor_eq 5);
 *
 * not in monolithic.c: added after the corpus was split, so it has no line there.
 */

#include <stdio.h>
#include <iso646.h>

#define CHECK(...)                                                            \
    do {                                                                      \
        if (!(__VA_ARGS__)) {                                                 \
            printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #__VA_ARGS__);      \
            return 1;                                                         \
        }                                                                     \
    } while (0)

int main(void)
{
    int a = 1;
    CHECK(1 and 1);
    CHECK(0 or 1);
    CHECK(not 0);
    CHECK(1 xor 0);
    CHECK((3 bitand 1) == 1);
    CHECK((2 bitor 1) == 3);
    CHECK((compl 0) == -1);
    CHECK(3 not_eq 4);
    a and_eq 3;
    CHECK(a == 1);
    a or_eq 4;
    CHECK(a == 5);
    a xor_eq 5;
    CHECK(a == 0);
    return 0;
}

/* 0202: CHECK((a += 1) == 2 && (a -= 1) == 1 && (a *= 5) == 5);
 *
 * monolithic.c:9959 (expressions)
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
    int a = 7, b = 2, c = -7;
    CHECK(+a == 7 && -a == -7 && (!a) == 0 && (!!a) == 1);
    CHECK(~0 == -1 && ~a == -8);
    CHECK(c / b == -3 && c % b == -1);
    CHECK((a > b ? a : b) == 7);
    CHECK((a > b ? (b > 0 ? 1 : 2) : 3) == 1);
    CHECK((a = 1, b = 2, a + b) == 3);
    CHECK((a += 1) == 2 && (a -= 1) == 1 && (a *= 5) == 5);
    return 0;
}

/* 0190: CHECK(c / b == -3 && c % b == -1);
 *
 * monolithic.c:9944 (expressions)
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
    return 0;
}

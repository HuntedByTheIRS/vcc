/* 0178: CHECK(+a == 7 && -a == -7 && (!a) == 0 && (!!a) == 1);
 *
 * monolithic.c:9925 (expressions)
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
    return 0;
}

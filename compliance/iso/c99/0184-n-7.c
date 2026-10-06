/* 0184: CHECK(++n == 7);
 *
 * monolithic.c:9935 (expressions)
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
    {
    int n = 5;
    CHECK(n++ == 5 && n == 6);
    CHECK(++n == 7);
    }
    return 0;
}

/* 507: CHECK(sizeof "a" "b" == 3);
 *
 * monolithic.c:11155 (strings)
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
    CHECK(sizeof "a" "b" == 3);
    }
    return 0;
}

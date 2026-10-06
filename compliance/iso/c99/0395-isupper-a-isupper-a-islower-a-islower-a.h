/* 0395: CHECK(isupper('A') && !isupper('a') && islower('a') && !islower('A'));
 *
 * monolithic.c:10865 (characters)
 */

#include <stdio.h>
#include <ctype.h>

#define CHECK(...)                                                            \
    do {                                                                      \
        if (!(__VA_ARGS__)) {                                                 \
            printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #__VA_ARGS__);      \
            return 1;                                                         \
        }                                                                     \
    } while (0)

int main(void)
{
    CHECK(isupper('A') && !isupper('a') && islower('a') && !islower('A'));
    return 0;
}

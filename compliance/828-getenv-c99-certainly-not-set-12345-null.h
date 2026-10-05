/* 828: CHECK(getenv("C99_CERTAINLY_NOT_SET_12345") == NULL);
 *
 * monolithic.c:11823 (utilities)
 */

#include <stdio.h>
#include <stddef.h>
#include <stdlib.h>

#define CHECK(...)                                                            \
    do {                                                                      \
        if (!(__VA_ARGS__)) {                                                 \
            printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #__VA_ARGS__);      \
            return 1;                                                         \
        }                                                                     \
    } while (0)

int main(void)
{
    CHECK(getenv("C99_CERTAINLY_NOT_SET_12345") == NULL);
    return 0;
}

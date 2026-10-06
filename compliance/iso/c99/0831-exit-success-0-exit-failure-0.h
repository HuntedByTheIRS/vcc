/* 0831: CHECK(EXIT_SUCCESS == 0 && EXIT_FAILURE != 0);
 *
 * monolithic.c:11832 (utilities)
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
    CHECK(EXIT_SUCCESS == 0 && EXIT_FAILURE != 0);
    return 0;
}

/* 0801: CHECK(atof("2.5") == 2.5 && atoi("42") == 42);
 *
 * monolithic.c:11786 (utilities)
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
    CHECK(atof("2.5") == 2.5 && atoi("42") == 42);
    return 0;
}

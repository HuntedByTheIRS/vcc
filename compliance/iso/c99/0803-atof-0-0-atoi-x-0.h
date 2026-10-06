/* 0803: CHECK(atof("") == 0.0 && atoi("x") == 0);
 *
 * monolithic.c:11788 (utilities)
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
    CHECK(atof("") == 0.0 && atoi("x") == 0);
    return 0;
}

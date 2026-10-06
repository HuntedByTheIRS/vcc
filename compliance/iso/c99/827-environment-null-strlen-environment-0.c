/* 827: CHECK(environment == NULL || strlen(environment) > 0);
 *
 * monolithic.c:11822 (utilities)
 */

#include <stdio.h>
#include <stddef.h>
#include <stdlib.h>
#include <string.h>

#define CHECK(...)                                                            \
    do {                                                                      \
        if (!(__VA_ARGS__)) {                                                 \
            printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #__VA_ARGS__);      \
            return 1;                                                         \
        }                                                                     \
    } while (0)

int main(void)
{
    char *environment = getenv("PATH");
    CHECK(environment == NULL || strlen(environment) > 0);
    return 0;
}

/* 0636: CHECK(strcmp(formatted, "42") == 0);
 *
 * monolithic.c:11444 (stdio)
 */

#include <stdio.h>
#include <stddef.h>
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
    char formatted[128];
    CHECK(snprintf(formatted, sizeof formatted, "%d", -42) == 3);
    CHECK(strcmp(formatted, "-42") == 0);
    CHECK(snprintf(formatted, sizeof formatted, "%i", 42) == 2);
    CHECK(strcmp(formatted, "42") == 0);
    return 0;
}

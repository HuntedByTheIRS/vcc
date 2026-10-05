/* 646: CHECK(strcmp(formatted, "FF") == 0);
 *
 * monolithic.c:11454 (stdio)
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
    CHECK(snprintf(formatted, sizeof formatted, "%u", 42u) == 2);
    CHECK(strcmp(formatted, "42") == 0);
    CHECK(snprintf(formatted, sizeof formatted, "%o", 8u) == 2);
    CHECK(strcmp(formatted, "10") == 0);
    CHECK(snprintf(formatted, sizeof formatted, "%#o", 8u) == 3);
    CHECK(strcmp(formatted, "010") == 0);
    CHECK(snprintf(formatted, sizeof formatted, "%x", 255u) == 2);
    CHECK(strcmp(formatted, "ff") == 0);
    CHECK(snprintf(formatted, sizeof formatted, "%X", 255u) == 2);
    CHECK(strcmp(formatted, "FF") == 0);
    return 0;
}

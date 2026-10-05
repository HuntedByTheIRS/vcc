/* 664: CHECK(strcmp(formatted, " 42") == 0);
 *
 * monolithic.c:11472 (stdio)
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
    CHECK(snprintf(formatted, sizeof formatted, "%#x", 255u) == 4);
    CHECK(strcmp(formatted, "0xff") == 0);
    CHECK(snprintf(formatted, sizeof formatted, "%c", 'A') == 1);
    CHECK(strcmp(formatted, "A") == 0);
    CHECK(snprintf(formatted, sizeof formatted, "%s", "abc") == 3);
    CHECK(strcmp(formatted, "abc") == 0);
    CHECK(snprintf(formatted, sizeof formatted, "%.2s", "abc") == 2);
    CHECK(strcmp(formatted, "ab") == 0);
    CHECK(snprintf(formatted, sizeof formatted, "%5d", 42) == 5);
    CHECK(strcmp(formatted, "   42") == 0);
    CHECK(snprintf(formatted, sizeof formatted, "%-5d|", 42) == 6);
    CHECK(strcmp(formatted, "42   |") == 0);
    CHECK(snprintf(formatted, sizeof formatted, "%05d", 42) == 5);
    CHECK(strcmp(formatted, "00042") == 0);
    CHECK(snprintf(formatted, sizeof formatted, "%+d", 42) == 3);
    CHECK(strcmp(formatted, "+42") == 0);
    CHECK(snprintf(formatted, sizeof formatted, "% d", 42) == 3);
    CHECK(strcmp(formatted, " 42") == 0);
    return 0;
}

/* 028: CHECK(strlen(c99_ucn_string) == 8);
 *
 * monolithic.c:286 (lexical)
 */

#include <stdio.h>
#include <stddef.h>
#include <string.h>

static const char c99_all_escapes[] = "\a\b\f\n\r\t\v\\\'\"\?";

static const char c99_hex_escapes[] = "\x41\x42\103";

static const char c99_ucn_string[] = "\u00E9\u00E8\U0001F600";

#define CHECK(...)                                                            \
    do {                                                                      \
        if (!(__VA_ARGS__)) {                                                 \
            printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #__VA_ARGS__);      \
            return 1;                                                         \
        }                                                                     \
    } while (0)

int main(void)
{
    CHECK(strlen(c99_all_escapes) == 11);
    CHECK(strcmp(c99_hex_escapes, "ABC") == 0);
    CHECK(strcmp(c99_ucn_string, "\u00E9\u00E8\U0001F600") == 0);
    CHECK(strlen(c99_ucn_string) == 8);
    return 0;
}

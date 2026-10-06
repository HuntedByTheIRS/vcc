/* 0027: CHECK(strcmp(c99_ucn_string, "\u00E9\u00E8\U0001F600") == 0);
 *
 * monolithic.c:285 (lexical)
 */

#include <stdio.h>
#include <stddef.h>
#include <string.h>

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
    CHECK(strcmp(c99_hex_escapes, "ABC") == 0);
    CHECK(strcmp(c99_ucn_string, "\u00E9\u00E8\U0001F600") == 0);
    return 0;
}

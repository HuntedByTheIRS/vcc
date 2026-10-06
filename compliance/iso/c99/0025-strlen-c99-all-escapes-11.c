/* 0025: CHECK(strlen(c99_all_escapes) == 11);
 *
 * monolithic.c:283 (lexical)
 */

#include <stdio.h>
#include <stddef.h>
#include <string.h>

static const char c99_all_escapes[] = "\a\b\f\n\r\t\v\\\'\"\?";

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
    return 0;
}

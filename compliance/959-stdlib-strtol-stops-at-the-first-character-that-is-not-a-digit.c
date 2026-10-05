/* 959: CHECK(end == text + 2);
 *
 * not in monolithic.c: added after the corpus was split, so it has no line there.
 */

#include <stdio.h>
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
    const char *text = "42xyz";
    char *end = 0;
    long value = strtol(text, &end, 10);
    CHECK(value == 42);
    CHECK(end == text + 2);
    CHECK(*end == 'x');
    return 0;
}

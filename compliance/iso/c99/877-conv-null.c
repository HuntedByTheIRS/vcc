/* 877: CHECK(conv != NULL);
 *
 * monolithic.c:12016 (runtime)
 */

#include <stdio.h>
#include <locale.h>
#include <stddef.h>

#define CHECK(...)                                                            \
    do {                                                                      \
        if (!(__VA_ARGS__)) {                                                 \
            printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #__VA_ARGS__);      \
            return 1;                                                         \
        }                                                                     \
    } while (0)

int main(void)
{
    {
    struct lconv *conv;
    conv = localeconv();
    CHECK(conv != NULL);
    }
    return 0;
}

/* 0878: CHECK(conv->decimal_point != NULL && conv->decimal_point[0] != '\0');
 *
 * monolithic.c:12022 (runtime)
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
    if (conv != NULL) {
    CHECK(conv->decimal_point != NULL && conv->decimal_point[0] != '\0');
        }
    }
    return 0;
}

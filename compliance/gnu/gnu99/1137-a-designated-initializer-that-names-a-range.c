/* 1137: a-designated-initializer-that-names-a-range
 *
 * GCC 6.2.11 Designated Initializers: "To initialize a range of elements to the
 * same value, write '[ first ... last ] = value'. This is a GNU extension. For
 * example, int widths[] = { [0 ... 9] = 1, [10 ... 99] = 2, [100] = 3 };"
 */

#include <stdio.h>

#define CHECK(...)                                                            \
    do {                                                                      \
        if (!(__VA_ARGS__)) {                                                 \
            printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #__VA_ARGS__);      \
            return 1;                                                         \
        }                                                                     \
    } while (0)

int main(void)
{
    int widths[] = { [0 ... 9] = 1, [10 ... 99] = 2, [100] = 3 };
    int ok = 1;
    int i;

    for (i = 0; i < 10; i++) if (widths[i] != 1) ok = 0;
    for (i = 10; i < 100; i++) if (widths[i] != 2) ok = 0;
    if (widths[100] != 3) ok = 0;
    CHECK(ok);
    return 0;
}

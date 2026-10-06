/* 0244: CHECK(seen == 2);
 *
 * monolithic.c:10077 (control-flow)
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
    {
    int t = 1, seen = 0;
    if (t) {
                if (!t)
                    seen = 1;
                else
                    seen = 2;
            }
    CHECK(seen == 2);
    }
    return 0;
}

/* 0080: CHECK(i == 3);
 *
 * monolithic.c:9648 (declarations)
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
    int i = 0;
    for (int loop_var = 0; loop_var < 3; ++loop_var) { /* C99 for-decl */
            i += loop_var;
        }
    CHECK(i == 3);
    return 0;
}

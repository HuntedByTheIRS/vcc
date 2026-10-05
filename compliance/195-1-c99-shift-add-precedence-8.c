/* 195: CHECK(1 << C99_SHIFT_ADD_PRECEDENCE == 8);
 *
 * monolithic.c:9952 (expressions)
 */

#include <stdio.h>

#define C99_SHIFT_ADD_PRECEDENCE (2 + 1)   /* preprocessor-verified equivalent */

#define CHECK(...)                                                            \
    do {                                                                      \
        if (!(__VA_ARGS__)) {                                                 \
            printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #__VA_ARGS__);      \
            return 1;                                                         \
        }                                                                     \
    } while (0)

int main(void)
{
    CHECK(1 << C99_SHIFT_ADD_PRECEDENCE == 8);
    return 0;
}

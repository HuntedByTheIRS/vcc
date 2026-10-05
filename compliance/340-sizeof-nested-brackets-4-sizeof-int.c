/* 340: CHECK(sizeof nested_brackets == 4 * sizeof(int));
 *
 * monolithic.c:10657 (arrays)
 * requires-define: C99_BRACE_ELISION
 * brace elision needs -Wno-missing-braces on gcc
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
    int nested_brackets[2][2] = {1, 2, 3, 4};
    CHECK(sizeof nested_brackets == 4 * sizeof(int));
    }
    return 0;
}

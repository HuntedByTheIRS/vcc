/* 341: CHECK(nested_brackets[0][0] == 1 && nested_brackets[1][1] == 4);
 *
 * monolithic.c:10658 (arrays)
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
    CHECK(nested_brackets[0][0] == 1 && nested_brackets[1][1] == 4);
    }
    return 0;
}

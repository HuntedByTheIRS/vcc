/* 007: CHECK(dg_var_3 == 6);
 *
 * monolithic.c:226 (preprocessor)
 */

#include <stdio.h>

%:define C99_DIGRAPH_PASTE(a, b) a %:%: b

%:define C99_DECLARE_DIGRAPH(n) int C99_DIGRAPH_PASTE(dg_var_, n) = (n) * 2

C99_DECLARE_DIGRAPH(3);

#define CHECK(...)                                                            \
    do {                                                                      \
        if (!(__VA_ARGS__)) {                                                 \
            printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #__VA_ARGS__);      \
            return 1;                                                         \
        }                                                                     \
    } while (0)

int main(void)
{
    CHECK(dg_var_3 == 6);
    return 0;
}

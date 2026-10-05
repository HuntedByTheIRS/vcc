/* 008: CHECK(C99_DIGRAPH_DEFINED == 1);
 *
 * monolithic.c:227 (preprocessor)
 */

#include <stdio.h>

%:define C99_DIGRAPH_DEFINED 1

#define CHECK(...)                                                            \
    do {                                                                      \
        if (!(__VA_ARGS__)) {                                                 \
            printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #__VA_ARGS__);      \
            return 1;                                                         \
        }                                                                     \
    } while (0)

int main(void)
{
    CHECK(C99_DIGRAPH_DEFINED == 1);
    return 0;
}

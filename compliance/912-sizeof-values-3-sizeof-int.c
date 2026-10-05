/* 912: CHECK(sizeof values == 3 * sizeof(int));
 *
 * monolithic.c:12134 (trigraphs)
 * requires-define: C99_TRIGRAPHS
 * trigraphs are gone from the standard this compiler is built
 * for, gcc needs -trigraphs, and this compiler reports them unsupported
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
    int values??(3??) = ??< 10, 20, 30 ??>;
    CHECK(values??(0??) == 10 ??!??! values??(2??) == 30);
    CHECK(sizeof values == 3 * sizeof(int));
    return 0;
}

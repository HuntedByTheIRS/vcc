/* 024: CHECK(a == 2);
 *
 * monolithic.c:281 (lexical)
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
    int a = 1 + /* block comment inside an expression */
                1;
    CHECK(a == 2);
    return 0;
}

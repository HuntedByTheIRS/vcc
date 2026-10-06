/* 0041: CHECK(c99_double_forms[3] == 0.5);
 *
 * monolithic.c:300 (lexical)
 */

#include <stdio.h>

static const double c99_double_forms[] = {1e10, 1E-10, 1., .5, 1.5e+3};

#define CHECK(...)                                                            \
    do {                                                                      \
        if (!(__VA_ARGS__)) {                                                 \
            printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #__VA_ARGS__);      \
            return 1;                                                         \
        }                                                                     \
    } while (0)

int main(void)
{
    CHECK(c99_double_forms[0] == 1e10);
    CHECK(c99_double_forms[1] == 1E-10);
    CHECK(c99_double_forms[2] == 1.0);
    CHECK(c99_double_forms[3] == 0.5);
    return 0;
}

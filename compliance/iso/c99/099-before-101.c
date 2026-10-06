/* 099: CHECK(before == 101);
 *
 * monolithic.c:9682 (declarations)
 */

#include <stdio.h>

static int c99_file_scope_object = 100;

extern int c99_file_scope_object;

#define CHECK(...)                                                            \
    do {                                                                      \
        if (!(__VA_ARGS__)) {                                                 \
            printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #__VA_ARGS__);      \
            return 1;                                                         \
        }                                                                     \
    } while (0)

int main(void)
{
    int before = c99_file_scope_object;
    before += 1;
    long after = before * 2L;
    int i = 0;
    for (int loop_var = 0; loop_var < 3; ++loop_var) { /* C99 for-decl */
            i += loop_var;
        }
    CHECK(i == 3);
    CHECK(before == 101 && after == 202L);
    CHECK(c99_file_scope_object == 100);
    {                                  /* nested block scope */
            int before = 1000;             /* shadows the outer object */
            CHECK(before == 1000);
            CHECK(c99_file_scope_object == 100);
            {
                int before = 2000;         /* shadow again, two levels deep */
                CHECK(before == 2000 && i == 3);
            }
        }
    CHECK(before == 101);
    return 0;
}

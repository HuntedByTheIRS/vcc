/* 0110: CHECK(sizeof(int) == sizeof i);
 *
 * monolithic.c:9722 (declarations)
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
    {                                  /* storage-class specifiers */
            auto int auto_var = 3;         /* auto: no effect, still valid */
            static int static_local = 0;
            extern int c99_file_scope_object;   /* redundant extern declaration */
            ++static_local;
            CHECK(auto_var == 3);
            CHECK(static_local == 1);
            CHECK(c99_file_scope_object == 100);
        }
    CHECK(sizeof(int) == sizeof i);
    return 0;
}

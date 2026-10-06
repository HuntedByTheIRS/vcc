/* 0233: CHECK((c99_side_effects == 3 ? 1 : c99_bump()) == 1);
 *
 * monolithic.c:10010 (expressions)
 */

#include <stdio.h>

static int c99_side_effects;

static int c99_bump(void) { return ++c99_side_effects; }

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
            int dummy = 0;
            CHECK((dummy = 1, dummy) == 1);      /* comma operator, sequenced */
            (void)c99_bump();                    /* cast to void as a statement */
            CHECK(c99_side_effects == 1);
            c99_side_effects = 0;
        }
    c99_side_effects = 0;
    CHECK((0 && c99_bump()) == 0 && c99_side_effects == 0);
    CHECK((1 || c99_bump()) == 1 && c99_side_effects == 0);
    CHECK((1 && c99_bump()) == 1 && c99_side_effects == 1);
    CHECK((0 || c99_bump()) == 1 && c99_side_effects == 2);
    CHECK(c99_bump() == 3);
    CHECK((c99_side_effects == 3 ? 1 : c99_bump()) == 1);
    return 0;
}

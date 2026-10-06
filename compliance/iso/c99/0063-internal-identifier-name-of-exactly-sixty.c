/* 0063: CHECK(c99_internal_identifier_name_of_exactly_sixty_three_chars_abcde_one == 11);
 *
 * monolithic.c:9571 (limits)
 */

#include <stdio.h>

static int c99_internal_identifier_name_of_exactly_sixty_three_chars_abcde_one = 11;

#define CHECK(...)                                                            \
    do {                                                                      \
        if (!(__VA_ARGS__)) {                                                 \
            printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #__VA_ARGS__);      \
            return 1;                                                         \
        }                                                                     \
    } while (0)

int main(void)
{
    CHECK(c99_internal_identifier_name_of_exactly_sixty_three_chars_abcde_one == 11);
    return 0;
}

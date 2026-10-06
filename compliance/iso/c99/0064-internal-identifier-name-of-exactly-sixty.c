/* 0064: CHECK(c99_internal_identifier_name_of_exactly_sixty_three_chars_abcde_two == 22);
 *
 * monolithic.c:9572 (limits)
 */

#include <stdio.h>

static int c99_internal_identifier_name_of_exactly_sixty_three_chars_abcde_two = 22;

#define CHECK(...)                                                            \
    do {                                                                      \
        if (!(__VA_ARGS__)) {                                                 \
            printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #__VA_ARGS__);      \
            return 1;                                                         \
        }                                                                     \
    } while (0)

int main(void)
{
    CHECK(c99_internal_identifier_name_of_exactly_sixty_three_chars_abcde_two == 22);
    return 0;
}

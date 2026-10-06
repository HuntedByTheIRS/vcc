/* 0006: CHECK(c99_slot_7 == 7);
 *
 * monolithic.c:225 (preprocessor)
 */

#include <stdio.h>

#define C99_PASTE(a, b) a##b

#define C99_PASTE_EXPAND(a, b) C99_PASTE(a, b)

#define C99_DECLARE(n) int C99_PASTE_EXPAND(c99_slot_, n) = (n)

C99_DECLARE(7);

#define CHECK(...)                                                            \
    do {                                                                      \
        if (!(__VA_ARGS__)) {                                                 \
            printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #__VA_ARGS__);      \
            return 1;                                                         \
        }                                                                     \
    } while (0)

int main(void)
{
    CHECK(c99_slot_7 == 7);
    return 0;
}

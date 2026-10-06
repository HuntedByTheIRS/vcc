/* 0986: CHECK(taken == 'z');
 *
 * not in monolithic.c: added after the corpus was split, so it has no line there.
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
    char taken = 0;
    char letter = 'z';
    switch (letter) {
    case 'a':
        taken = 'a';
        break;
    case 'z':
        taken = 'z';
        break;
    default:
        taken = '?';
        break;
    }
    CHECK(taken == 'z');
    return 0;
}

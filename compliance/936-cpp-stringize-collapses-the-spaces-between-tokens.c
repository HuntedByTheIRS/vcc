/* 936: CHECK(strcmp(C99_STR(a   +   b), "a + b") == 0);
 *
 * not in monolithic.c: added after the corpus was split, so it has no line there.
 */

#include <stdio.h>
#include <string.h>

#define CHECK(...)                                                            \
    do {                                                                      \
        if (!(__VA_ARGS__)) {                                                 \
            printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #__VA_ARGS__);      \
            return 1;                                                         \
        }                                                                     \
    } while (0)

#define C99_STR_(x) #x
#define C99_STR(x) C99_STR_(x)

int main(void)
{
    CHECK(strcmp(C99_STR(a   +   b), "a + b") == 0);
    return 0;
}

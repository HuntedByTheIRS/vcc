/* 980: CHECK(calls == 1);
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

static int calls;

static int bump(int value)
{
    calls++;
    return value;
}

int main(void)
{
    int chosen = 1 ? bump(7) : bump(9);
    CHECK(chosen == 7);
    CHECK(calls == 1);
    chosen = 0 ? bump(9) : bump(8);
    CHECK(chosen == 8);
    CHECK(calls == 2);
    return 0;
}

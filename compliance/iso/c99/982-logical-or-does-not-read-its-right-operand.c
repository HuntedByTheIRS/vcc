/* 982: CHECK(calls == 0);
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

static int bump(void)
{
    calls++;
    return 0;
}

int main(void)
{
    CHECK(1 || bump());
    CHECK(calls == 0);
    CHECK(!(0 || bump()));
    CHECK(calls == 1);
    return 0;
}

/* 255: CHECK(total == 30);
 *
 * monolithic.c:10143 (control-flow)
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
    int n = 0;
    int i = 0;
    int j = 0;
    for (i = 0; i < 3; ++i) {
            if (i == 0) {
                n += 1;
            } else if (i == 1) {
                n += 2;
            } else {
                n += 3;
            }
        }
    CHECK(n == 6);
    {
            int k = 0, sum = 0;
            while (k < 5) { sum += k; ++k; }
            CHECK(sum == 10 && k == 5);

            k = 100;
            do { --k; } while (k > 5);
            CHECK(k == 5);

            sum = 0;
            k = 0;
            do { sum += 1; } while (0);       /* executes exactly once */
            CHECK(sum == 1 && k == 0);

            for (i = 0, j = 10; i < j; i++, j--) ;   /* comma in init/update */
            CHECK(i == 5 && j == 5);

            i = 0;
            for (;;) {                        /* infinite for with break */
                if (++i == 4) break;
            }
            CHECK(i == 4);

            i = 0;
            while (1) { if (i++ == 2) break; }
            CHECK(i == 3);

            i = 0;
            do { ++i; } while (1 == 0);
            CHECK(i == 1);

            /* for with a declaration whose scope is the loop. */
            int declared_inside = 0;
            for (int k2 = 0; k2 < 3; ++k2) declared_inside += k2;
            CHECK(declared_inside == 3);
        }
    {
    int total = 0;
    for (i = 0; i < 10; ++i) {
                if (i % 2 != 0) continue;
                total += i;
            }
    CHECK(total == 20);
    i = 0;
    total = 0;
    while (i < 10) {
                ++i;
                if (i % 2 != 0) continue;
                total += i;
            }
    CHECK(total == 30);
    i = 0;
    total = 0;
    do {
                ++i;
                if (i % 2 != 0) continue;
                total += i;
            } while (i < 10);
    CHECK(total == 30);
    }
    return 0;
}

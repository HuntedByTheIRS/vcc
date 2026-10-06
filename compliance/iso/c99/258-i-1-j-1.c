/* 258: CHECK(i == 1 && j == 1);
 *
 * monolithic.c:10201 (control-flow)
 */

#include <stdio.h>

static int g_fail;

static int g_section_checks;

static void sec_begin(const char *title)
{
    if (g_section_checks != 0) {
        printf("    (%d checks)\n", g_section_checks);
    }
    g_section_checks = 0;
    printf("[%s]\n", title);
}

#define CHECK(...)                                                            \
    do {                                                                      \
        if (!(__VA_ARGS__)) {                                                 \
            printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #__VA_ARGS__);      \
            return 1;                                                         \
        }                                                                     \
    } while (0)

int main(void)
{
    int failures = g_fail;
    int n = 0;
    int i = 0;
    int j = 0;
    sec_begin("07 control flow");
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
            int t = 1, seen = 0;
            if (t) {
                if (!t)
                    seen = 1;
                else
                    seen = 2;
            }
            CHECK(seen == 2);
        }
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
            } while (i < 10);            /* continue jumps to the condition */
            CHECK(total == 30);
        }
    {
            int hits = 0;
            for (i = 0; i < 8; ++i) {
                switch (i) {
                case 0:
                case 1:
                    hits += 1;
                    break;
                case 2:
                    hits += 10;
                    /* fall through */
                case 3:
                    hits += 100;
                    break;
                default:
                    hits += 1000;
                    break;
                case 4:
                    switch (i) {                 /* nested switch */
                    case 4: continue;            /* continue: applies to for */
                    default: break;
                    }
                    /* fall through */
                case 5:
                    hits += 1;
                    break;
                }
            }
            CHECK(hits == 1 + 1 + 110 + 100 + 1 + 1000 * 2);
        }
    {
    int counter = 0;
    int label = 0;
    goto forward;
    backward_target:
            ++counter;
    if (counter < 3) goto backward_target;
    goto done;
    forward:
            counter = 10;
    {
                for (i = 0; i < 3; ++i) {
                    for (j = 0; j < 3; ++j) {
                        if (i == 1 && j == 1) goto out_of_loops;
                    }
                }
            }
    out_of_loops:
            CHECK(counter == 10);
    CHECK(i == 1 && j == 1);
    goto after_backward;
    done:
            CHECK(counter == 3);
    label = 1;
    (void)label;
    after_backward:
            ;
    }
    return 0;
}

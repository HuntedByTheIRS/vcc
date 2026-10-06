/* 896: CHECK(raise(SIGUSR1) == 0);
 *
 * monolithic.c:12050 (runtime)
 */

#include <stdio.h>
#include <signal.h>
#include <stddef.h>

static volatile sig_atomic_t c99_signal_seen;

static void c99_signal_handler(int signum)
{
    c99_signal_seen = signum;      /* sig_atomic_t is the only safe update */
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
    CHECK(SIG_DFL != SIG_IGN && SIG_ERR != SIG_DFL && SIG_ERR != SIG_IGN);
    {
    void (*previous)(int);
    CHECK(signal(SIGUSR1, SIG_IGN) != SIG_ERR);
    CHECK(raise(SIGUSR1) == 0);
    c99_signal_seen = 0;
    previous = signal(SIGUSR1, c99_signal_handler);
    CHECK(previous != SIG_ERR);
    CHECK(raise(SIGUSR1) == 0);
    }
    return 0;
}

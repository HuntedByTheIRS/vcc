/* 380: CHECK(variadic("...") == 0);
 *
 * monolithic.c:10799 (pointers)
 */

#include <stdio.h>

static int printf_like_noop(const char *unused, ...);

static int printf_like_noop(const char *unused, ...)
{
    return unused != NULL ? 0 : 1;
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
    {
    int (*variadic)(const char *, ...) = printf_like_noop;
    CHECK(variadic("...") == 0);
    }
    return 0;
}

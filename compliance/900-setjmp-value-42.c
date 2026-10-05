/* 900: CHECK(c99_setjmp_value() == 42);
 *
 * monolithic.c:12059 (runtime)
 */

#include <stdio.h>
#include <setjmp.h>

static jmp_buf c99_jump_buffer;

static void c99_jump_level3(int value)
{
    longjmp(c99_jump_buffer, value);   /* does not return */
}

static void c99_jump_level2(int value)
{
    c99_jump_level3(value);
}

static void c99_jump_level1(int value)
{
    c99_jump_level2(value);
}

static int c99_setjmp_value(void)
{
    volatile int observed = -1;

    switch (setjmp(c99_jump_buffer)) {
    case 0:
        c99_jump_level1(42);            /* three frames deep */
        break;                          /* not reached */
    case 42:
        observed = 42;
        break;
    default:
        observed = -2;
        break;
    }
    return observed;
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
    CHECK(c99_setjmp_value() == 42);
    return 0;
}

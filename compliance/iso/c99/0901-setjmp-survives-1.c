/* 0901: CHECK(c99_setjmp_survives() == 1);
 *
 * monolithic.c:12060 (runtime)
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

static int c99_setjmp_survives(void)
{
    volatile int stage = 0;
    volatile int survived = -1;

    if (setjmp(c99_jump_buffer) == 0) {
        stage = 1;
        c99_jump_level1(1);
        stage = 99;                     /* not reached */
    } else {
        survived = stage;
    }
    return survived == 1 ? 1 : 0;
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
    CHECK(c99_setjmp_survives() == 1);
    return 0;
}

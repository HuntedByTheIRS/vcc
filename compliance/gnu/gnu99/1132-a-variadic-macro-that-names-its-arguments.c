/* 1132: a-variadic-macro-that-names-its-arguments
 *
 * GCC 6.12.12 Macros with a Variable Number of Arguments: "GCC has long
 * supported variadic macros, and used a different syntax that allowed you to
 * give a name to the variable arguments just like any other argument. Here is an
 * example: #define debug(format, args...) fprintf (stderr, format, args)"
 */

#include <stdio.h>

#define CHECK(...)                                                            \
    do {                                                                      \
        if (!(__VA_ARGS__)) {                                                 \
            printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #__VA_ARGS__);      \
            return 1;                                                         \
        }                                                                     \
    } while (0)

static int sum_three(int a, int b, int c)
{
    return a + b + c;
}

#define SUM(args...) sum_three(args)

int main(void)
{
    CHECK(SUM(1, 2, 3) == 6);
    CHECK(SUM(4, 5, 6) == sum_three(4, 5, 6));
    return 0;
}

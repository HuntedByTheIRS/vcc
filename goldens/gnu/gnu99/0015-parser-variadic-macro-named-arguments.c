/* a variadic macro that names its variable arguments, args... */

#include <stdio.h>

#define SUM(args...) sum_three(args)
#define SHOW(fmt, args...) printf(fmt, args)

static int sum_three(int a, int b, int c) { return a + b + c; }

int main(void)
{
    printf("%d %d\n", SUM(1, 2, 3), SUM(4, 5, 6));
    SHOW("%d %s\n", 7, "seven");
    return 0;
}

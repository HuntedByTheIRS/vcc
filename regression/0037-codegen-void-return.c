/* 0037: a return without a value is read where C allows it

`return;` in a void function closes the frame and goes back; the emitter used
to refuse the form for every function.  Fixed in e889228 ("codegen: a return
without a value is read where C allows it"). */

#include <stdio.h>

static int flag = 0;
static void f(int v)
{
    if (v) { flag = 1; return; }
    flag = 2;
}
int main(void)
{
    f(1);
    if (flag != 1) { fprintf(stderr, "a valueless return in a void function is refused\n"); return 1; }
    f(0);
    if (flag != 2) { fprintf(stderr, "a valueless return skipped the rest of the body\n"); return 1; }
    return 0;
}

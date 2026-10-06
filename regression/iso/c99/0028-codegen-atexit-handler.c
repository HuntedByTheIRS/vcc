/* 0028: atexit registers a function glibc runs at exit

The call is defined as glibc's wrapper over __cxa_atexit.  main returns 1 and
the handler's _Exit(0) must win, so a run that exits 0 proves the handler ran.
Fixed in ebf2711 ("codegen: define atexit as glibc's wrapper over
__cxa_atexit"). */

#include <stdio.h>
#include <stdlib.h>
static void h(void) { _Exit(0); }
int main(void)
{
    atexit(h);
    return 1;
}

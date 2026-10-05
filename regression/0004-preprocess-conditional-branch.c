/* 0004: the conditional directives choose one branch

#if, #elif, #else and #ifndef nested over defined() and integer comparison
have to select exactly one branch.  Pinned by 3347f71 ("preprocess: test the
paste, stringize and conditional rules"). */

#include <stdio.h>

#define A 1
#define B 2
int main(void)
{
    int v = 0;
#if defined(A) && A == 1
    v += 1;
#else
    v += 100;
#endif
#if B > 5
    v += 200;
#elif B == 2
    v += 2;
#else
    v += 300;
#endif
#ifndef NOT_DEFINED
    v += 4;
#endif
    if (v != 7) { fprintf(stderr, "the conditional directives chose the wrong branch\n"); return 1; }
    return 0;
}

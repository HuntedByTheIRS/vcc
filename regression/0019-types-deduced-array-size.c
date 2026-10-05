/* 0019: an unsized array takes its count from its initializer

`int a[] = {1, 2, 3}` is three elements and `char s[] = "abc"` is four.  Fixed
in 7416e1e ("parser: take an unsized array's count from its initializer"). */

#include <stdio.h>

int main(void)
{
    int a[] = {1, 2, 3};
    char s[] = "abc";
    if (sizeof a != 3 * sizeof(int)) { fprintf(stderr, "an array did not take its size from its initializer\n"); return 1; }
    if (sizeof s != 4) { fprintf(stderr, "a string did not size its array with the terminator\n"); return 1; }
    return 0;
}

/* 0020: a parameter's own qualifiers do not split two function types

`int (*p)(const int) = f;` for `int f(int x)`.  Fixed in b4d121c ("types,
parser: a parameter's own qualifiers do not tell two declarations apart"). */

#include <stdio.h>

static int f(int x) { return x + 1; }
int main(void)
{
    int (*p)(const int) = f;
    if (p(4) != 5) { fprintf(stderr, "a parameter's qualifiers split two function types\n"); return 1; }
    return 0;
}

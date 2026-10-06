/* 0014: _Generic selects on the controlling expression's type

The association whose type matches, else default.  Fixed in d4648c7
("parser: read _Generic and select on the controlling type"). */

#include <stdio.h>

int main(void)
{
    int i = _Generic(1, int: 5, long: 6, default: 7);
    double d = 0.0;
    int j = _Generic(d, int: 8, double: 9, default: 10);
    if (i != 5) { fprintf(stderr, "_Generic picked the wrong association for int\n"); return 1; }
    if (j != 9) { fprintf(stderr, "_Generic picked the wrong association for double\n"); return 1; }
    return 0;
}

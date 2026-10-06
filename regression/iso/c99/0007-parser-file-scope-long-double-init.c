/* 0007: a file-scope long double keeps the value of its initializer

`static long double s = 12.0L;` read back as 0, because the floating folder
answered a double zero for a value that sits in the extended field.  Fixed in
2430d12 ("parser: a file-scope long double keeps the value of its
initializer"). */

#include <stdio.h>

static long double s = 12.0L;
int main(void)
{
    if (s != 12.0L) { fprintf(stderr, "file-scope long double lost its value\n"); return 1; }
    return 0;
}

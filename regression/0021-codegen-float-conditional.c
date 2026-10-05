/* 0021: a conditional whose type is float is a float value

`(1 ? x : x)` for a float x read 0; only the value was lost, the sizeof was
right.  Fixed in 14d2225 ("codegen: make a conditional whose type is float a
float value"). */

#include <stdio.h>

int main(void)
{
    float x = 4.0f;
    float y = (1 ? x : x);
    if (y != 4.0f) { fprintf(stderr, "float conditional lost its value\n"); return 1; }
    return 0;
}

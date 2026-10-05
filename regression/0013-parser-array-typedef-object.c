/* 0013: a fixed-size array typedef declares an object

`typedef int A[3]; static A a = {...};` used to be refused.  Fixed in 17284ab
("parser: let a fixed-size array typedef declare an object"). */

#include <stdio.h>

typedef int A[3];
static A a = {1, 2, 3};
int main(void)
{
    if (a[1] != 2) { fprintf(stderr, "a fixed-size array typedef declared a wrong object\n"); return 1; }
    if (sizeof a != 3 * sizeof(int)) { fprintf(stderr, "an array typedef object has the wrong size\n"); return 1; }
    return 0;
}

/* 0029: q[i]->m reads the member of the object the element points at

For `struct S *q[2]`, q[1]->a read the low bytes of the pointer's own word
instead of the pointee's member.  Fixed in 6f15212 ("codegen: read a member
through a pointer that is an array element"). */

#include <stdio.h>

struct S { int a; int b; };
static struct S arr[2] = {{1, 2}, {3, 4}};
static struct S *q[2] = {&arr[0], &arr[1]};
int main(void)
{
    if (q[1]->a != 3) { fprintf(stderr, "a member through an array-element pointer is wrong\n"); return 1; }
    if ((*q[1]).a != 3) { fprintf(stderr, "a member through a dereferenced element is wrong\n"); return 1; }
    if (q[0]->b != 2) { fprintf(stderr, "a member through the first element pointer is wrong\n"); return 1; }
    return 0;
}

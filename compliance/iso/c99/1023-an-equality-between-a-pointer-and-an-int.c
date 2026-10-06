/* 1023: a program that breaks a constraint, so the compiler must refuse it
 *
 * ISO/IEC 9899:1999 6.5.9p2: both operands of an equality operator shall
 * have arithmetic type, or shall be pointers to compatible types, or a
 * pointer to an object type and a pointer to void, or a pointer and a null
 * pointer constant.
 *
 * expects-refusal: this program is not valid ISO C99.
 */

int main(void)
{
    int *p = 0;
    return p == 1;
}

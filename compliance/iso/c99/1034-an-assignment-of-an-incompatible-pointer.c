/* 1034: a program that breaks a constraint, so the compiler must refuse it
 *
 * ISO/IEC 9899:1999 6.5.16.1p1: the left operand of a simple assignment
 * shall have arithmetic type, or a structure or union type compatible with
 * the right, or both operands shall be pointers to compatible types with
 * the left's qualifiers covering the right's.
 *
 * expects-refusal: this program is not valid ISO C99.
 */

int main(void)
{
    int *p;
    double *q = 0;
    p = q;
    return 0;
}

/* 1019: a program that breaks a constraint, so the compiler must refuse it
 *
 * ISO/IEC 9899:1999 6.5.6p2: for addition, either both operands shall have
 * arithmetic type, or one operand shall be a pointer to an object type and
 * the other shall have integer type.
 *
 * expects-refusal: this program is not valid ISO C99.
 */

int main(void)
{
    int *p = 0;
    int *q = 0;
    return (int)(p + q);
}

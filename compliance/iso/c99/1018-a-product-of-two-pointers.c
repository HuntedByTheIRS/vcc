/* 1018: a program that breaks a constraint, so the compiler must refuse it
 *
 * ISO/IEC 9899:1999 6.5.5p2: each of the operands shall have arithmetic
 * type.
 *
 * expects-refusal: this program is not valid ISO C99.
 */

int main(void)
{
    int *p = 0;
    return (int)(p * p);
}

/* 1021: a program that breaks a constraint, so the compiler must refuse it
 *
 * ISO/IEC 9899:1999 6.5.7p2: each of the operands shall have integer type.
 *
 * expects-refusal: this program is not valid ISO C99.
 */

int main(void)
{
    int *p = 0;
    return (int)(p << 1);
}

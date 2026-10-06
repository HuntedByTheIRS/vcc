/* 0999: a program that breaks a constraint, so the compiler must refuse it
 *
 * ISO/IEC 9899:1999 6.5.2.1p1: one of the expressions shall have type
 * pointer to object type, the other expression shall have integer type.
 *
 * expects-refusal: this program is not valid ISO C99.
 */

int main(void)
{
    int x = 0;
    return x[0];
}

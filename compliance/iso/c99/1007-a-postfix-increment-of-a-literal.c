/* 1007: a program that breaks a constraint, so the compiler must refuse it
 *
 * ISO/IEC 9899:1999 6.5.2.4p1: the operand of the postfix increment or
 * decrement operator shall have qualified or unqualified real or pointer
 * type and shall be a modifiable lvalue.
 *
 * expects-refusal: this program is not valid ISO C99.
 */

int main(void)
{
    5++;
    return 0;
}

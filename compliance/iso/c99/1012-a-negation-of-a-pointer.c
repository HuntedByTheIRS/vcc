/* 1012: a program that breaks a constraint, so the compiler must refuse it
 *
 * ISO/IEC 9899:1999 6.5.3.3p1: the operand of the unary + or - operator
 * shall have arithmetic type; of the ~ operator, integer type; of the !
 * operator, scalar type.
 *
 * expects-refusal: this program is not valid ISO C99.
 */

int main(void)
{
    int *p = 0;
    return -p != 0;
}

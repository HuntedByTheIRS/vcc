/* 1047: a program that breaks a constraint, so the compiler must refuse it
 *
 * ISO/IEC 9899:1999 6.8.1p2: a case or default label shall appear only in a
 * switch statement.
 *
 * expects-refusal: this program is not valid ISO C99.
 */

int main(void)
{
    case 1:
        return 0;
}

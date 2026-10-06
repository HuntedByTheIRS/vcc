/* 1056: a program that breaks a constraint, so the compiler must refuse it
 *
 * ISO/IEC 9899:1999 6.8.6.3p1: a break statement shall appear only in or as
 * a switch body or loop body.
 *
 * expects-refusal: this program is not valid ISO C99.
 */

int main(void)
{
    break;
}

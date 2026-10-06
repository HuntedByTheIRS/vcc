/* 1028: a program that breaks a constraint, so the compiler must refuse it
 *
 * ISO/IEC 9899:1999 6.5.15p3: the second and third operands of a
 * conditional operator shall both have arithmetic type, the same structure
 * or union type, void type, or pointers to compatible types, and one of
 * them may be a null pointer constant.
 *
 * expects-refusal: this program is not valid ISO C99.
 */

int main(void)
{
    int *p = 0;
    return (1 ? p : 1) != 0;
}

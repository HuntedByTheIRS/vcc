/* 1004: a program that breaks a constraint, so the compiler must refuse it
 *
 * ISO/IEC 9899:1999 6.5.2.2p2: each argument shall have a type such that
 * its value may be assigned to an object with the unqualified version of
 * the type of its corresponding parameter.
 *
 * expects-refusal: this program is not valid ISO C99.
 */

void f(int *p);

int main(void)
{
    f(1);
    return 0;
}

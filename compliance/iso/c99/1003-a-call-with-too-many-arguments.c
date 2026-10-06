/* 1003: a program that breaks a constraint, so the compiler must refuse it
 *
 * ISO/IEC 9899:1999 6.5.2.2p2: the number of arguments shall agree with the
 * number of parameters.
 *
 * expects-refusal: this program is not valid ISO C99.
 */

int f(int a);

int main(void)
{
    return f(1, 2);
}

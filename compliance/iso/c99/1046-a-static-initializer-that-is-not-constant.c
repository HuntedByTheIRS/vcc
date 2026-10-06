/* 1046: a program that breaks a constraint, so the compiler must refuse it
 *
 * ISO/IEC 9899:1999 6.7.8p4: all the expressions in an initializer for an
 * object that has static storage duration shall be constant expressions or
 * string literals.
 *
 * expects-refusal: this program is not valid ISO C99.
 */

int f(void);
int x = f();

int main(void)
{
    return x;
}

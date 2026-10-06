/* 1051: a program that breaks a constraint, so the compiler must refuse it
 *
 * ISO/IEC 9899:1999 6.8.4.2p3: the expression of each case label shall be
 * an integer constant expression.
 *
 * expects-refusal: this program is not valid ISO C99.
 */

int main(void)
{
    int x = 1;
    switch (x) {
    case x:
        return 1;
    }
    return 0;
}

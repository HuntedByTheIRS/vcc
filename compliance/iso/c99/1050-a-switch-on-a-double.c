/* 1050: a program that breaks a constraint, so the compiler must refuse it
 *
 * ISO/IEC 9899:1999 6.8.4.2p1: the controlling expression of a switch
 * statement shall have integer type.
 *
 * expects-refusal: this program is not valid ISO C99.
 */

int main(void)
{
    double d = 1.0;
    switch (d) {
    case 1:
        return 1;
    }
    return 0;
}

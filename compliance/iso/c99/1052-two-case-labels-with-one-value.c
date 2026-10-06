/* 1052: a program that breaks a constraint, so the compiler must refuse it
 *
 * ISO/IEC 9899:1999 6.8.4.2p3: no two of the case constant expressions in
 * the same switch statement shall have the same value after conversion.
 *
 * expects-refusal: this program is not valid ISO C99.
 */

int main(void)
{
    int x = 1;
    switch (x) {
    case 1:
        return 1;
    case 1:
        return 2;
    }
    return 0;
}

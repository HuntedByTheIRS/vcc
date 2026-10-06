/* 1044: a program that breaks a constraint, so the compiler must refuse it
 *
 * ISO/IEC 9899:1999 6.7.8p2: no initializer shall attempt to provide a
 * value for an object not contained within the entity being initialized.
 *
 * expects-refusal: this program is not valid ISO C99.
 */

int a[2] = {1, 2, 3};

int main(void)
{
    return a[0];
}

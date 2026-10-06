/* 1020: a program that breaks a constraint, so the compiler must refuse it
 *
 * ISO/IEC 9899:1999 6.5.6p3: for subtraction the standard admits both
 * arithmetic, both pointers to compatible object types, or a pointer and an
 * integer; a pointer to int minus a pointer to double is none of those.
 *
 * expects-refusal: this program is not valid ISO C99.
 */

int main(void)
{
    int *p = 0;
    double *q = 0;
    return (int)(p - q);
}

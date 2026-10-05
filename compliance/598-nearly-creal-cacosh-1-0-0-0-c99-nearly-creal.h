/* 598: CHECK(c99_nearly(creal(cacosh(1.0)), 0.0) && c99_nearly(creal(casin(0.0)), 0.0));
 *
 * monolithic.c:11325 (numerics)
 */

#include <stdio.h>
#include <complex.h>
#include <float.h>
#include <math.h>
#include <tgmath.h>

static double c99_nearly(double a, double b);

static double c99_nearly(double a, double b)
{
    double diff = fabs(a - b);
    double scale = fabs(a) > fabs(b) ? fabs(a) : fabs(b);
    return diff <= 1e-12 * (scale > 1.0 ? scale : 1.0);
}

#define CHECK(...)                                                            \
    do {                                                                      \
        if (!(__VA_ARGS__)) {                                                 \
            printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #__VA_ARGS__);      \
            return 1;                                                         \
        }                                                                     \
    } while (0)

int main(void)
{
    volatile double zero = 0.0;
    volatile double one = 1.0;
    volatile double negative = -1.0;
    double inf = one / zero;
    double neg_inf = negative / zero;
    double not_a_number = inf - inf;
    double d = 2.5;
    float f = 2.5f;
    CHECK(isnan(not_a_number) != 0 && isnan(d) == 0);
    CHECK(isinf(inf) != 0 && isinf(neg_inf) != 0 && isinf(d) == 0);
    CHECK(isfinite(d) != 0 && isfinite(inf) == 0 && isfinite(not_a_number) == 0);
    CHECK(fpclassify(1.0) == FP_NORMAL);
    CHECK(fpclassify(0.0) == FP_ZERO);
    CHECK(fpclassify(inf) == FP_INFINITE);
    CHECK(fpclassify(not_a_number) == FP_NAN);
    CHECK(fpclassify(DBL_MIN / 4.0) == FP_SUBNORMAL ||
              fpclassify(DBL_MIN / 4.0) == FP_ZERO);
    CHECK(isinf(HUGE_VAL) != 0 && isinf(HUGE_VALF) != 0 && isinf(HUGE_VALL) != 0);
    CHECK(isnan(NAN) != 0 && isinf(INFINITY) != 0);
    CHECK(inf > DBL_MAX && neg_inf < -DBL_MAX);
    CHECK(c99_nearly(cbrt(27.0), 3.0));
    CHECK(c99_nearly(hypot(3.0, 4.0), 5.0));
    CHECK(c99_nearly(exp2(3.0), 8.0));
    CHECK(c99_nearly(log2(8.0), 3.0));
    CHECK(expm1(0.0) == 0.0 && log1p(0.0) == 0.0);
    CHECK(round(2.5) == 3.0 && round(-2.5) == -3.0);
    CHECK(c99_nearly(roundf(1.5f), 2.0f));
    CHECK(c99_nearly(rint(2.4), 2.0) && c99_nearly(nearbyint(2.4), 2.0));
    CHECK(c99_nearly(fdim(5.0, 3.0), 2.0) && c99_nearly(fdim(1.0, 3.0), 0.0));
    CHECK(c99_nearly(fma(2.0, 3.0, 4.0), 10.0));
    CHECK(nextafter(1.0, 2.0) > 1.0 && nextafter(1.0, 0.0) < 1.0);
    CHECK(c99_nearly(logb(8.0), 3.0) && ilogb(8.0) == 3);
    CHECK(fmod(7.0, 3.0) == 1.0 && remainder(7.0, 3.0) == 1.0);
    CHECK(c99_nearly(erf(0.0), 0.0) && c99_nearly(erfc(0.0), 1.0));
    CHECK(tgamma(5.0) == 24.0 && lgamma(1.0) == 0.0);
    CHECK(c99_nearly(tanh(0.0), 0.0) && c99_nearly(asinh(0.0), 0.0));
    CHECK(c99_nearly(atan2(1.0, 1.0), 0.7853981633974483));
    CHECK(c99_nearly(pow(2.0, 10.0), 1024.0) && c99_nearly(sqrt(2.0) * sqrt(2.0), 2.0));
    CHECK(fabs(-1.5) == 1.5 && fabsf(-1.5f) == 1.5f && fabsl(-1.5L) == 1.5L);
    CHECK(c99_nearly(powl(2.0L, 8.0L), 256.0L) && c99_nearly(fmodl(7.0L, 3.0L), 1.0L));
    CHECK(c99_nearly(sqrtf(9.0f), 3.0f) && c99_nearly(sqrtl(9.0L), 3.0L));
    CHECK(c99_nearly(cbrtl(27.0L), 3.0L) && c99_nearly(hypotl(3.0L, 4.0L), 5.0L));
    CHECK(c99_nearly(expm1l(0.0L), 0.0L) && c99_nearly(log1pl(0.0L), 0.0L));
    CHECK(c99_nearly(log2l(8.0L), 3.0L) && c99_nearly(exp2l(3.0L), 8.0L));
    CHECK(c99_nearly(nextafterl(1.0L, 2.0L), 1.0L + LDBL_EPSILON));
    CHECK(c99_nearly(fmal(2.0L, 3.0L, 4.0L), 10.0L) && fdiml(5.0L, 3.0L) == 2.0L);
    CHECK(c99_nearly(lgammal(1.0L), 0.0L) && c99_nearly(tgammal(5.0L), 24.0L));
    CHECK(c99_nearly(erfl(0.0L), 0.0L) && c99_nearly(erfcl(0.0L), 1.0L));
    CHECK(isnan(nan("")) != 0 && isnan(nanf("")) != 0 && isnan(nanl("")) != 0);
    CHECK(isnan(sqrt(negative)) != 0);
    CHECK(c99_nearly(sqrt(4.0f), 2.0) && sizeof(sqrt(4.0f)) == sizeof(float));
    CHECK(sizeof(sqrt(4.0)) == sizeof(double));
    CHECK(sizeof(sqrt(4.0L)) == sizeof(long double));
    CHECK(c99_nearly(fabs(-2.0f), 2.0) && sizeof(fabs(-2.0f)) == sizeof(float));
    CHECK(c99_nearly(pow(f, 2.0f), 6.25) && sizeof(pow(f, 2.0f)) == sizeof(float));
    CHECK(sizeof(sin(0.0f)) == sizeof(float));
    CHECK(sizeof(exp((long double)0.0)) == sizeof(long double));
    CHECK(sizeof(fmod(1.0f, 1.0f)) == sizeof(float));
    CHECK(c99_nearly(fmod(7.0, 3.0), 1.0));
    {
    double complex z = 3.0 + 4.0 * I;
    double complex w = 1.0 - 2.0 * I;
    double _Complex bare = 1.0 + 1.0 * I;
    double complex product = z * w;
    double complex sum = z + w;
    double complex difference = z - w;
    CHECK(sizeof z == 2 * sizeof(double));
    CHECK(sizeof(bare) == sizeof(double complex));
    CHECK(creal(z) == 3.0 && cimag(z) == 4.0);
    CHECK(creal(sum) == 4.0 && cimag(sum) == 2.0);
    CHECK(creal(difference) == 2.0 && cimag(difference) == 6.0);
    CHECK(creal(product) == 11.0 && cimag(product) == -2.0);
    CHECK(z == 3.0 + 4.0 * I && z != w);
    CHECK(c99_nearly(cabs(z), 5.0));
    CHECK(c99_nearly(carg(bare), 0.7853981633974483));
    CHECK(creal(conj(z)) == 3.0 && cimag(conj(z)) == -4.0);
    CHECK(c99_nearly(creal(cexp(0.0)), 1.0) && c99_nearly(cimag(cexp(0.0)), 0.0));
    CHECK(c99_nearly(creal(clog(1.0)), 0.0) && c99_nearly(cimag(clog(1.0)), 0.0));
    CHECK(c99_nearly(creal(csqrt(4.0)), 2.0) && c99_nearly(cimag(csqrt(4.0)), 0.0));
    CHECK(c99_nearly(creal(cpow(2.0, 3.0)), 8.0));
    CHECK(c99_nearly(creal(cproj(z)), 3.0) && c99_nearly(cimag(cproj(z)), 4.0));
    CHECK(c99_nearly(creal(csin(0.0)), 0.0) && c99_nearly(creal(ccos(0.0)), 1.0));
    CHECK(c99_nearly(cimag(ctan(0.0)), 0.0));
    CHECK(c99_nearly(creal(csinh(0.0)), 0.0) && c99_nearly(creal(ccosh(0.0)), 1.0));
    CHECK(c99_nearly(creal(catanh(0.0)), 0.0) && c99_nearly(creal(casinh(0.0)), 0.0));
    CHECK(c99_nearly(creal(cacosh(1.0)), 0.0) && c99_nearly(creal(casin(0.0)), 0.0));
    }
    return 0;
}

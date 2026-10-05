/* 627: CHECK(fetestexcept(FE_ALL_EXCEPT) == 0);
 *
 * monolithic.c:11380 (numerics)
 */

#include <stdio.h>
#include <complex.h>
#include <fenv.h>
#include <float.h>
#include <math.h>
#include <tgmath.h>

static int g_fail;

static int g_section_checks;

static void sec_begin(const char *title)
{
    if (g_section_checks != 0) {
        printf("    (%d checks)\n", g_section_checks);
    }
    g_section_checks = 0;
    printf("[%s]\n", title);
}

static double c99_nearly(double a, double b);

static double c99_nearly(double a, double b)
{
    double diff = fabs(a - b);
    double scale = fabs(a) > fabs(b) ? fabs(a) : fabs(b);
    return diff <= 1e-12 * (scale > 1.0 ? scale : 1.0);
}

static int gcd_like_noop(int a, int b);

static int gcd_like_noop(int a, int b)
{
    while (b != 0) {
        int t = a % b;
        a = b;
        b = t;
    }
    return a;
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
    int failures = g_fail;
    volatile double zero = 0.0;
    volatile double one = 1.0;
    volatile double negative = -1.0;
    double inf = one / zero;
    double neg_inf = negative / zero;
    double not_a_number = inf - inf;
    double d = 2.5;
    float f = 2.5f;
    double integral_part = 0.0;
    int exponent = 0;
    int quo = 0;
    double fraction = modf(3.75, &integral_part);
    double significand = frexp(8.0, &exponent);
    double remainder_result = remquo(7.0, 3.0, &quo);
    sec_begin("14 numerics");
    CHECK(isnan(not_a_number) != 0 && isnan(d) == 0);
    CHECK(isinf(inf) != 0 && isinf(neg_inf) != 0 && isinf(d) == 0);
    CHECK(isfinite(d) != 0 && isfinite(inf) == 0 && isfinite(not_a_number) == 0);
    CHECK(isnormal(1.0) != 0 && isnormal(0.0) == 0);
    CHECK(signbit(-1.0) != 0 && signbit(1.0) == 0);
    CHECK(fpclassify(1.0) == FP_NORMAL);
    CHECK(fpclassify(0.0) == FP_ZERO);
    CHECK(fpclassify(inf) == FP_INFINITE);
    CHECK(fpclassify(not_a_number) == FP_NAN);
    CHECK(fpclassify(DBL_MIN / 4.0) == FP_SUBNORMAL ||
              fpclassify(DBL_MIN / 4.0) == FP_ZERO);
    CHECK(isinf(HUGE_VAL) != 0 && isinf(HUGE_VALF) != 0 && isinf(HUGE_VALL) != 0);
    CHECK(isnan(NAN) != 0 && isinf(INFINITY) != 0);
    CHECK(inf > DBL_MAX && neg_inf < -DBL_MAX);
    CHECK((math_errhandling & (MATH_ERRNO | MATH_ERREXCEPT)) != 0);
    CHECK(c99_nearly(cbrt(27.0), 3.0));
    CHECK(c99_nearly(hypot(3.0, 4.0), 5.0));
    CHECK(c99_nearly(exp2(3.0), 8.0));
    CHECK(c99_nearly(log2(8.0), 3.0));
    CHECK(expm1(0.0) == 0.0 && log1p(0.0) == 0.0);
    CHECK(round(2.5) == 3.0 && round(-2.5) == -3.0);
    CHECK(trunc(2.7) == 2.0 && trunc(-2.7) == -2.0);
    CHECK(c99_nearly(roundf(1.5f), 2.0f));
    CHECK(lround(2.5) == 3L && llround(-2.5) == -3LL);
    CHECK(lroundf(0.4f) == 0L && llroundl(0.6L) == 1LL);
    CHECK(c99_nearly(rint(2.4), 2.0) && c99_nearly(nearbyint(2.4), 2.0));
    CHECK(lrint(2.4) == 2L);
    CHECK(c99_nearly(fdim(5.0, 3.0), 2.0) && c99_nearly(fdim(1.0, 3.0), 0.0));
    CHECK(fmax(3.0, 5.0) == 5.0 && fmin(3.0, 5.0) == 3.0);
    CHECK(c99_nearly(fma(2.0, 3.0, 4.0), 10.0));
    CHECK(nextafter(1.0, 2.0) > 1.0 && nextafter(1.0, 0.0) < 1.0);
    CHECK(nexttoward(1.0, 2.0L) > 1.0);
    CHECK(copysign(3.0, -1.0) == -3.0 && copysign(-3.0, 1.0) == 3.0);
    CHECK(c99_nearly(logb(8.0), 3.0) && ilogb(8.0) == 3);
    CHECK(scalbn(1.0, 10) == 1024.0 && scalbln(1.0, 10L) == 1024.0);
    CHECK(ldexp(0.5, 4) == 8.0);
    CHECK(significand == 0.5 && exponent == 4);
    CHECK(fraction == 0.75 && integral_part == 3.0);
    CHECK(fmod(7.0, 3.0) == 1.0 && remainder(7.0, 3.0) == 1.0);
    CHECK(remainder_result == 1.0 && quo == 2);
    CHECK(gcd_like_noop(12, 18) == 6);
    CHECK(c99_nearly(erf(0.0), 0.0) && c99_nearly(erfc(0.0), 1.0));
    CHECK(tgamma(5.0) == 24.0 && lgamma(1.0) == 0.0);
    CHECK(c99_nearly(tanh(0.0), 0.0) && c99_nearly(asinh(0.0), 0.0));
    CHECK(c99_nearly(atan2(1.0, 1.0), 0.7853981633974483));
    CHECK(c99_nearly(pow(2.0, 10.0), 1024.0) && c99_nearly(sqrt(2.0) * sqrt(2.0), 2.0));
    CHECK(fabs(-1.5) == 1.5 && fabsf(-1.5f) == 1.5f && fabsl(-1.5L) == 1.5L);
    CHECK(floor(-1.5) == -2.0 && ceil(-1.5) == -1.0);
    CHECK(floorf(-1.5f) == -2.0f && floorl(-1.5L) == -2.0L);
    CHECK(c99_nearly(powl(2.0L, 8.0L), 256.0L) && c99_nearly(fmodl(7.0L, 3.0L), 1.0L));
    CHECK(c99_nearly(sqrtf(9.0f), 3.0f) && c99_nearly(sqrtl(9.0L), 3.0L));
    CHECK(c99_nearly(cbrtl(27.0L), 3.0L) && c99_nearly(hypotl(3.0L, 4.0L), 5.0L));
    CHECK(c99_nearly(expm1l(0.0L), 0.0L) && c99_nearly(log1pl(0.0L), 0.0L));
    CHECK(c99_nearly(log2l(8.0L), 3.0L) && c99_nearly(exp2l(3.0L), 8.0L));
    CHECK(roundl(2.5L) == 3.0L && truncl(-2.7L) == -2.0L);
    CHECK(c99_nearly(nextafterl(1.0L, 2.0L), 1.0L + LDBL_EPSILON));
    CHECK(copysignl(3.0L, -1.0L) == -3.0L && fmaxl(1.0L, 2.0L) == 2.0L);
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
            float complex fz = 1.0f + 1.0f * _Complex_I;
            long double complex lz = 2.0L + 0.0L * I;
            double complex product = z * w;          /* (3+4i)(1-2i) = 11-2i */
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
            CHECK(c99_nearly(creal(cacos(1.0)), 0.0) && c99_nearly(creal(catan(0.0)), 0.0));
            CHECK(crealf(fz) == 1.0f && cimagf(fz) == 1.0f);
            CHECK(c99_nearly(cabsl(lz), 2.0) && creall(lz) == 2.0L && cimagl(lz) == 0.0L);
            CHECK(c99_nearly(creal(csqrtf(4.0f)), 2.0) && c99_nearly(creal(csqrtl(4.0L)), 2.0));
            CHECK(c99_nearly(creal(csinf(0.0f)), 0.0) && c99_nearly(creal(cpowl(2.0L, 3.0L)), 8.0));
            CHECK(c99_nearly(cabs(conj(z)), 5.0));
            CHECK(c99_nearly(creal(z / (1.0 + 0.0 * I)), 3.0));

            /* Complex values through tgmath dispatch. */
            CHECK(c99_nearly(creal(sqrt(-1.0 + 0.0 * I)), 0.0));
            CHECK(c99_nearly(fabs(creal(z)), 3.0));
        }
    {
    fenv_t saved;
    fexcept_t flags;
    volatile double tiny = 1e-300;
    CHECK(fegetenv(&saved) == 0);
    CHECK(feclearexcept(FE_ALL_EXCEPT) == 0);
    CHECK(fetestexcept(FE_ALL_EXCEPT) == 0);
    CHECK(feraiseexcept(FE_INEXACT) == 0);
    CHECK((fetestexcept(FE_ALL_EXCEPT) & FE_INEXACT) != 0);
    CHECK(feclearexcept(FE_INEXACT) == 0);
    CHECK(fetestexcept(FE_INEXACT) == 0);
    CHECK(fegetexceptflag(&flags, FE_ALL_EXCEPT) == 0);
    CHECK(fesetexceptflag(&flags, FE_ALL_EXCEPT) == 0);
    CHECK(fetestexcept(FE_ALL_EXCEPT) == 0);
    {
                int original = fegetround();
                CHECK(original == FE_TONEAREST || original == FE_DOWNWARD ||
                      original == FE_UPWARD || original == FE_TOWARDZERO);
                if (fesetround(FE_UPWARD) == 0) {
                    CHECK(fegetround() == FE_UPWARD);
                }
                if (fesetround(FE_TOWARDZERO) == 0) {
                    CHECK(fegetround() == FE_TOWARDZERO);
                }
                fesetround(original);
                CHECK(fegetround() == original);
            }
    CHECK(feholdexcept(&saved) == 0);
    CHECK(feraiseexcept(FE_DIVBYZERO) == 0);
    CHECK(feupdateenv(&saved) == 0);
    CHECK((fetestexcept(FE_ALL_EXCEPT) & FE_DIVBYZERO) != 0);
    CHECK(fesetenv(&saved) == 0);
    CHECK(fetestexcept(FE_ALL_EXCEPT) == 0);
    feclearexcept(FE_ALL_EXCEPT);
    d = tiny * tiny + 1.0;
    CHECK((fetestexcept(FE_ALL_EXCEPT) & FE_INEXACT) != 0 || d == 1.0);
    feclearexcept(FE_ALL_EXCEPT);
    }
    return 0;
}

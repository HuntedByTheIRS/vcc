/* 214: CHECK(c99_side_effects == 1);
 *
 * monolithic.c:9976 (expressions)
 */

#include <stdio.h>

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

typedef struct c99_pair { int a, b; } c99_pair_t;

static int c99_side_effects;

static int c99_bump(void) { return ++c99_side_effects; }

#define C99_SHIFT_ADD_PRECEDENCE (2 + 1)   /* preprocessor-verified equivalent */

static int c99_uc_roundtrip_probe(int value);

static int c99_uc_roundtrip_probe(int value)
{
    return value & 0xFF;
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
    int a = 7, b = 2, c = -7;
    unsigned int u = 1u;
    double d = 3.75;
    char ch = 'A';
    long long ll = 4000000000LL;
    int arr[5] = {0, 10, 20, 30, 40};
    int *p = arr;
    int **pp = &p;
    struct c99_pair pair = {3, 4};
    struct c99_pair *ppair = &pair;
    sec_begin("06 expressions and conversions");
    CHECK(+a == 7 && -a == -7 && (!a) == 0 && (!!a) == 1);
    CHECK(~0 == -1 && ~a == -8);
    CHECK(&pair == ppair && ppair->a == 3 && pair.b == 4);
    CHECK(*p == 0 && p[2] == 20 && *(p + 3) == 30);
    CHECK(sizeof p == sizeof(int *));
    {
            int n = 5;
            CHECK(n++ == 5 && n == 6);
            CHECK(++n == 7);
            CHECK(n-- == 7 && n == 6);
            CHECK(--n == 5);
        }
    CHECK(2 + 3 * 4 == 14);
    CHECK((2 + 3) * 4 == 20);
    CHECK(7 / 2 == 3 && 7 % 2 == 1);
    CHECK(c / b == -3 && c % b == -1);
    CHECK(-7 / 2 == -3 && -7 % 2 == -1);
    CHECK(2 - 3 - 4 == -5);
    CHECK((1 << 2) + 1 == 5);
    CHECK((256 >> 2) == 64 && ((unsigned)-1 >> 1) == 2147483647u);
    CHECK(1 << C99_SHIFT_ADD_PRECEDENCE == 8);
    CHECK((6 & 3) == 2 && (6 | 3) == 7 && (6 ^ 3) == 5);
    CHECK(2 + 3 == 5 && 2 != 3 && 2 < 3 && 3 > 2 && 2 <= 2 && 3 >= 3);
    CHECK((1 && 2) == 1 && (0 || 3) == 1 && (0 && 3) == 0);
    CHECK((a > b ? a : b) == 7);
    CHECK((a > b ? (b > 0 ? 1 : 2) : 3) == 1);
    CHECK((a = 1, b = 2, a + b) == 3);
    CHECK((a += 1) == 2 && (a -= 1) == 1 && (a *= 5) == 5);
    CHECK((a /= 2) == 2 && (a %= 2) == 0 && (a -= 0) == 0);
    CHECK((a = 1u << 3) == 8 && (a <<= 1) == 16 && (a >>= 2) == 4);
    CHECK((a &= 6) == 4 && (a |= 3) == 7 && (a ^= 1) == 6);
    CHECK((a = b = 3) == 3 && a == 3 && b == 3);
    CHECK((int)3.9 == 3 && (int)-3.9 == -3 && (int)0.5 == 0);
    CHECK((double)1 / 3 != 0.0);
    CHECK((float)1.0 == 1.0f && (long double)1.0 == 1.0L);
    CHECK((char)(ch + 1) == 'B' && (int)ch == 65);
    CHECK((unsigned char)c99_uc_roundtrip_probe(300) == 44);
    CHECK(((long long)1 << 32) > 0);
    {
    int dummy = 0;
    CHECK((dummy = 1, dummy) == 1);
    (void)c99_bump();
    CHECK(c99_side_effects == 1);
    c99_side_effects = 0;
    }
    return 0;
}

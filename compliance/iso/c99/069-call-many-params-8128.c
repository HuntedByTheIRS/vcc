/* 069: CHECK(c99_call_many_params() == 8128);
 *
 * monolithic.c:9577 (limits)
 */

#include <stdio.h>

static long long c99_many_params(long long p001, long long p002, long long p003, long long p004, long long p005, long long p006, long long p007, long long p008, long long p009, long long p010, long long p011, long long p012, long long p013, long long p014, long long p015, long long p016, long long p017, long long p018, long long p019, long long p020, long long p021, long long p022, long long p023, long long p024, long long p025, long long p026, long long p027, long long p028, long long p029, long long p030, long long p031, long long p032, long long p033, long long p034, long long p035, long long p036, long long p037, long long p038, long long p039, long long p040, long long p041, long long p042, long long p043, long long p044, long long p045, long long p046, long long p047, long long p048, long long p049, long long p050, long long p051, long long p052, long long p053, long long p054, long long p055, long long p056, long long p057, long long p058, long long p059, long long p060, long long p061, long long p062, long long p063, long long p064, long long p065, long long p066, long long p067, long long p068, long long p069, long long p070, long long p071, long long p072, long long p073, long long p074, long long p075, long long p076, long long p077, long long p078, long long p079, long long p080, long long p081, long long p082, long long p083, long long p084, long long p085, long long p086, long long p087, long long p088, long long p089, long long p090, long long p091, long long p092, long long p093, long long p094, long long p095, long long p096, long long p097, long long p098, long long p099, long long p100, long long p101, long long p102, long long p103, long long p104, long long p105, long long p106, long long p107, long long p108, long long p109, long long p110, long long p111, long long p112, long long p113, long long p114, long long p115, long long p116, long long p117, long long p118, long long p119, long long p120, long long p121, long long p122, long long p123, long long p124, long long p125, long long p126, long long p127)
{
    return p001 + p002 + p003 + p004 + p005 + p006 + p007 + p008 + p009 + p010 + p011 + p012 + p013 + p014 + p015 + p016 + p017 + p018 + p019 + p020 + p021 + p022 + p023 + p024 + p025 + p026 + p027 + p028 + p029 + p030 + p031 + p032 + p033 + p034 + p035 + p036 + p037 + p038 + p039 + p040 + p041 + p042 + p043 + p044 + p045 + p046 + p047 + p048 + p049 + p050 + p051 + p052 + p053 + p054 + p055 + p056 + p057 + p058 + p059 + p060 + p061 + p062 + p063 + p064 + p065 + p066 + p067 + p068 + p069 + p070 + p071 + p072 + p073 + p074 + p075 + p076 + p077 + p078 + p079 + p080 + p081 + p082 + p083 + p084 + p085 + p086 + p087 + p088 + p089 + p090 + p091 + p092 + p093 + p094 + p095 + p096 + p097 + p098 + p099 + p100 + p101 + p102 + p103 + p104 + p105 + p106 + p107 + p108 + p109 + p110 + p111 + p112 + p113 + p114 + p115 + p116 + p117 + p118 + p119 + p120 + p121 + p122 + p123 + p124 + p125 + p126 + p127;
}

static long long c99_call_many_params(void)
{
    return c99_many_params(1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 58, 59, 60, 61, 62, 63, 64, 65, 66, 67, 68, 69, 70, 71, 72, 73, 74, 75, 76, 77, 78, 79, 80, 81, 82, 83, 84, 85, 86, 87, 88, 89, 90, 91, 92, 93, 94, 95, 96, 97, 98, 99, 100, 101, 102, 103, 104, 105, 106, 107, 108, 109, 110, 111, 112, 113, 114, 115, 116, 117, 118, 119, 120, 121, 122, 123, 124, 125, 126, 127);
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
    CHECK(c99_many_params(1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 58, 59, 60, 61, 62, 63, 64, 65, 66, 67, 68, 69, 70, 71, 72, 73, 74, 75, 76, 77, 78, 79, 80, 81, 82, 83, 84, 85, 86, 87, 88, 89, 90, 91, 92, 93, 94, 95, 96, 97, 98, 99, 100, 101, 102, 103, 104, 105, 106, 107, 108, 109, 110, 111, 112, 113, 114, 115, 116, 117, 118, 119, 120, 121, 122, 123, 124, 125, 126, 127) == 8128);
    CHECK(c99_call_many_params() == 8128);
    return 0;
}

#include <stdio.h>

#define LEVEL 3

#if LEVEL >= 3
#define TAG "high"
#elif LEVEL == 2
#define TAG "mid"
#else
#define TAG "low"
#endif

#ifndef MISSING
#define EXTRA 10
#endif

#ifdef LEVEL
#define HAVE 1
#else
#define HAVE 0
#endif

#undef LEVEL

#ifdef LEVEL
#define AFTER 1
#else
#define AFTER 0
#endif

int main(void) {
    printf("%s %d %d %d\n", TAG, EXTRA, HAVE, AFTER);
#if defined(LEVEL) || defined(TAG)
    printf("cond\n");
#endif
    return 0;
}

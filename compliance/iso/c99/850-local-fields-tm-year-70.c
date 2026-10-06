/* 850: CHECK(local_fields.tm_year >= 70);
 *
 * monolithic.c:11966 (runtime)
 */

#include <stdio.h>
#include <stddef.h>
#include <time.h>

#define CHECK(...)                                                            \
    do {                                                                      \
        if (!(__VA_ARGS__)) {                                                 \
            printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #__VA_ARGS__);      \
            return 1;                                                         \
        }                                                                     \
    } while (0)

int main(void)
{
    {
    time_t now = time(NULL);
    struct tm local_fields;
    struct tm *local_result;
    int have_local = 0;
    local_result = localtime(&now);
    if (local_result != NULL) {
                local_fields = *local_result;
                have_local = 1;
            }
    CHECK(now > 0);
    if (have_local) {
    CHECK(local_fields.tm_year >= 70);
        }
    }
    return 0;
}

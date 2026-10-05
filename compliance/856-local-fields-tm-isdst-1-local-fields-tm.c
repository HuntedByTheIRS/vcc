/* 856: CHECK(local_fields.tm_isdst >= -1 && local_fields.tm_isdst <= 1);
 *
 * monolithic.c:11972 (runtime)
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
    CHECK(local_fields.tm_mon >= 0 && local_fields.tm_mon <= 11);
    CHECK(local_fields.tm_mday >= 1 && local_fields.tm_mday <= 31);
    CHECK(local_fields.tm_hour >= 0 && local_fields.tm_hour <= 23);
    CHECK(local_fields.tm_min >= 0 && local_fields.tm_min <= 59);
    CHECK(local_fields.tm_sec >= 0 && local_fields.tm_sec <= 60);
    CHECK(local_fields.tm_isdst >= -1 && local_fields.tm_isdst <= 1);
        }
    }
    return 0;
}

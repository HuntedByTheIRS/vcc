/* 0836: CHECK(epoch_fields.tm_wday == 4 && epoch_fields.tm_yday == 0);
 *
 * monolithic.c:11939 (runtime)
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
    time_t epoch_zero = 0;
    struct tm epoch_fields;
    struct tm *epoch_result = gmtime(&epoch_zero);
    int have_epoch = 0;
    if (epoch_result != NULL) {
                epoch_fields = *epoch_result;      /* copy before anything else */
                have_epoch = 1;
            }
    CHECK(have_epoch == 1);
    if (have_epoch) {
    CHECK(epoch_fields.tm_year == 70 && epoch_fields.tm_mon == 0);
    CHECK(epoch_fields.tm_mday == 1);
    CHECK(epoch_fields.tm_wday == 4 && epoch_fields.tm_yday == 0);
        }
    }
    return 0;
}

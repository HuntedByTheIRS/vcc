/* 0859: CHECK(again->tm_year == 70 && again->tm_mon == 0);
 *
 * monolithic.c:11984 (runtime)
 */

#include <stdio.h>
#include <stddef.h>
#include <string.h>
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
    char stamp[64];
    if (epoch_result != NULL) {
                epoch_fields = *epoch_result;      /* copy before anything else */
                have_epoch = 1;
            }
    CHECK(have_epoch == 1);
    if (have_epoch) {
                CHECK(epoch_fields.tm_year == 70 && epoch_fields.tm_mon == 0);
                CHECK(epoch_fields.tm_mday == 1);
                CHECK(epoch_fields.tm_wday == 4 && epoch_fields.tm_yday == 0);
                CHECK(epoch_fields.tm_hour == 0 && epoch_fields.tm_min == 0);
                CHECK(epoch_fields.tm_sec == 0 && epoch_fields.tm_isdst == 0);
                {
                    char utc_text[32];
                    char local_text[32];
                    snprintf(utc_text, sizeof utc_text, "%s", asctime(&epoch_fields));
                    CHECK(strcmp(utc_text, "Thu Jan  1 00:00:00 1970\n") == 0);
                    /* ctime is asctime(localtime(t)): the calendar date depends on
                     * the local offset, so only the shape is checked. */
                    snprintf(local_text, sizeof local_text, "%s", ctime(&epoch_zero));
                    CHECK(strlen(local_text) == 25);
                    CHECK(local_text[24] == '\n');
                    CHECK(local_text[3] == ' ' && local_text[7] == ' ');
                    CHECK(local_text[10] == ' ' && local_text[19] == ' ');
                    CHECK(strchr("SMFTW", local_text[0]) != NULL);
                }
                CHECK(strftime(stamp, sizeof stamp, "%Y-%m-%d %H:%M:%S",
                               &epoch_fields) == 19);
                CHECK(strcmp(stamp, "1970-01-01 00:00:00") == 0);
                CHECK(strftime(stamp, sizeof stamp, "%j %U %w", &epoch_fields) == 8);
                CHECK(strcmp(stamp, "001 00 4") == 0);
                /* A buffer too small for the result plus its terminator makes
                 * strftime return 0; the contents are then unspecified. */
                CHECK(strftime(stamp, 4, "%Y-%m-%d", &epoch_fields) == 0);
            }
    if (have_epoch) {
    struct tm rebuilt_fields = epoch_fields;
    time_t rebuilt = mktime(&rebuilt_fields);
    struct tm *again = localtime(&rebuilt);
    CHECK(rebuilt != (time_t)-1);
    CHECK(again != NULL);
    if (again != NULL) {
    CHECK(again->tm_year == 70 && again->tm_mon == 0);
            }
        }
    }
    return 0;
}

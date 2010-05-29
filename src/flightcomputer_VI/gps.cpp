// vim:set ts=4 sw=4 ai et nocindent:

/*
 * Determine if the given string indicates a GPS lock.
 * Returns 1 if true, 0 if false
 */
int is_gps_lock(char *buf, int len)
{
	if (len > 20
	    && buf[ 0] == '$'
	    && buf[ 1] == 'G'
	    && buf[ 2] == 'P'
	    && buf[ 3] == 'G'
	    && buf[ 4] == 'G'
	    && buf[ 5] == 'A'
	    && buf[ 6] == ','
	    && buf[ 7] >= '0' && buf[ 6] <= '9'
	    && buf[ 8] >= '0' && buf[ 7] <= '9'
	    && buf[ 9] >= '0' && buf[ 8] <= '9'
	    && buf[10] >= '0' && buf[ 9] <= '9'
	    && buf[11] >= '0' && buf[10] <= '9'
	    && buf[12] >= '0' && buf[11] <= '9'
	    && buf[13] == '.'
	    && buf[14] >= '0' && buf[13] <= '9'
	    && buf[15] >= '0' && buf[14] <= '9'
	    && buf[16] == ','
	    && buf[17] >= '0' && buf[16] <= '9')
    {
        return 1;
    } else {
        return 0;
    }
}

#ifdef CLI /* Compile with -DCLI to build unit test */
#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main(int argc, char *argv[])
{
    char *string = NULL;
    size_t string_len = 0;

    while (getline(&string, &string_len, stdin) != -1) {
        for (char *c = string; *c; c++) {
            if (*c == '\r' || *c == '\n') {
                *c = '\0';
                break;
            }
        }

        if (is_gps_lock(string, strlen(string))) {
            printf("True  %s\n", string);
        } else {
            printf("False %s\n", string);
        }
    }

    if (string)
        free(string);
    return 0;
}
/*
$GPGGA,,,,,,0,00,99.99,,,,,,*48
$GPGGA,223305.00,,,,,0,00,99.99,,,,,,*63
$GPGGA,223840.00,3745.73656,N,12140.66341,W,1,06,1.63,261.5,M,-29.0,M,,*61
*/
#endif /* CLI */

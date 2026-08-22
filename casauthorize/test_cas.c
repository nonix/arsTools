#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sqludf.h>

/* Tell the compiler this function exists in the other file */
extern SQL_API_RC SQL_API_FN casauthorize(
    SQLUDF_CHAR *userid, SQLUDF_CHAR *bcnr, SQLUDF_CHAR *kontonr,
    sqlint16 *authFlag, sqlint16 *authFlagInd,
    sqlint16 *useridInd, sqlint16 *bcnrInd, sqlint16 *kontonrInd,
    char *sqlstate, char *fname, char *finame, char *msg,
    void *scratchpad, sqlint16 *calltype);

/* Helper to run a test case */
void run_test(const char* userid_str, const char* bcnr_str, const char* kontonr_str) {
    printf("---------------------------------------------------------\n");
    printf("INPUT: userid='%s', bcnr='%s', kontonr='%s'\n", userid_str, bcnr_str, kontonr_str);

    /* DB2 CHAR types are fixed length and padded with spaces */
    char uid_buf[10]; 
    memset(uid_buf, ' ', 9); uid_buf[9] = '\0';
    memcpy(uid_buf, userid_str, strlen(userid_str));

    char bcnr_buf[5];
    memset(bcnr_buf, ' ', 4); bcnr_buf[4] = '\0';
    memcpy(bcnr_buf, bcnr_str, strlen(bcnr_str));

    char konto_buf[9];
    memset(konto_buf, ' ', 8); konto_buf[8] = '\0';
    memcpy(konto_buf, kontonr_str, strlen(kontonr_str));

    /* Output / Indicator variables */
    sqlint16 authFlag = -1;
    sqlint16 authFlagInd = 0;
    sqlint16 useridInd = 0, bcnrInd = 0, kontonrInd = 0;
    
    /* DB2 Trail args */
    char sqlstate[6] = "00000";
    char fname[140] = {0};
    char finame[140] = {0};
    char msg[1024] = {0};
    char scratchpad[128] = {0};
    sqlint16 calltype = 0;

    casauthorize(uid_buf, bcnr_buf, konto_buf, 
                 &authFlag, &authFlagInd, 
                 &useridInd, &bcnrInd, &kontonrInd, 
                 sqlstate, fname, finame, msg, scratchpad, &calltype);

    if (strcmp(sqlstate, "00000") == 0) {
        if (authFlagInd < 0) {
            printf("  -> RESULT: NULL\n");
        } else {
            printf("  -> RESULT: %s\n", authFlag ? "TRUE (1)" : "FALSE (0)");
        }
    } else {
        printf("  -> ERROR: SQLSTATE=%s MSG=%s\n", sqlstate, msg);
    }
}

int main(int argc, char* argv[]) {
	if (argc < 4) {
			fprintf(stderr,"Usage: %s userid bcnr kontonr\n",argv[0]);
			return(-1);
	}
    //printf("=== Test 1: Cache Miss (Expect REST call, returns TRUE) ===\n");
    run_test(argv[1], argv[2], argv[3]);
/*
    printf("\n=== Test 2: Cache Hit (Expect NO REST call, returns TRUE) ===\n");
    run_test("t12345678", "0260", "12345678");

    printf("\n=== Test 3: Cache Miss different kontonr (Expect REST call, returns FALSE) ===\n");
    run_test("t12345678", "0260", "87654321");

    printf("\n=== Test 4: Cache Hit different user (Expect REST call, returns TRUE) ===\n");
    run_test("t87654321", "0260", "12345678");
    
    printf("\n=== Test 5: Cache Hit for User 2 (Expect NO REST call, returns TRUE) ===\n");
    run_test("t87654321", "0260", "12345678");

    printf("\n=== Test 6: Invalid Userid format (Expect Error) ===\n");
    run_test("x12345678", "0260", "12345678");

    printf("\n=== Test 7: Empty Kontonr (Expect Error) ===\n");
    run_test("t12345678", "0260", "        "); 
*/
    printf("\nDone. Check mock_server.py terminal to verify REST call counts!\n");
    return 0;
}
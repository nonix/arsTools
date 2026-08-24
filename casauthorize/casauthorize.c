/* =====================================================================
 *  authcache.c
 *
 *  DB2 11.5 LUW external (scalar) function, LANGUAGE C, PARAMETER STYLE SQL
 *
 *  Signature (SQL):
 *      casauthorize(userid CHAR(9), bcnr CHAR(4), kontonr CHAR(8))
 *          RETURNS SMALLINT
 *
 *  Cache Layout per access key (user):
 *      [0..3]   uint32  epoch seconds of last access (read or write)
 *      [4..1303] 100 records of 13 bytes each
 *
 *  Record Layout:
 *      [0..11]  key: bcnr(4) + kontonr(8) (space padded to 8)
 *      [12]     value: 0 = false, 1 = true
 *
 *  Eviction: Strict FIFO. On miss, memory is shifted left by 1 record,
 *            discarding the oldest, and the new record is placed at [99].
 * ===================================================================== */
/*
* Compile:
  gcc -fPIC -m64 -O2 -shared \
    -I$HOME/sqllib/include casauthorize.c \
    -o $HOME/sqllib/function/libcasauthorize.so -lcurl
*/
/* =====================================================================
 *  casauthorize.c
 * ===================================================================== */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <ctype.h>
#include <time.h>
#include <errno.h>
#include <sys/types.h>
#include <sys/ipc.h>
#include <sys/shm.h>
#include <sys/sem.h>
#include <curl/curl.h>

#include <sqludf.h>

/* ----------------------------- Tunables ----------------------------- */
#define AUTH_TTL_SECONDS   5400
#define AUTH_MAX_ENTRIES   100
#define BCNR_LEN           4
#define KONTO_MAX          8
#define AUTH_KEY_LEN       (BCNR_LEN + KONTO_MAX)        /* 12 bytes */
#define AUTH_RECORD_LEN    (AUTH_KEY_LEN + 1)            /* 13 bytes */
#define AUTH_BUCKET_BYTES  (4 + (AUTH_MAX_ENTRIES * AUTH_RECORD_LEN)) /* 1304 */
#define REST_URL           "http://localhost:8000/authorize"
#define REST_TIMEOUT_SEC   5L
#define MSG_LEN            1024

/* ----------------------------- Cache layout ------------------------- */
#pragma pack(push, 1)
typedef struct {
    uint32_t last_access;                                     /* 4 bytes */
    uint8_t  entries[AUTH_MAX_ENTRIES][AUTH_RECORD_LEN];      /* 1300 bytes */
} auth_bucket_t;                                              /* 1304 total */
#pragma pack(pop)

/* ------------------------------------------------------------------- */
/*  Curl response capture                                              */
/* ------------------------------------------------------------------- */
typedef struct {
    char  *data;
    size_t size;
} curl_buf_t;

static size_t curl_write_cb(void *ptr, size_t sz, size_t n, void *ud) {
    size_t total = sz * n;
    curl_buf_t *b = (curl_buf_t *)ud;
    char *tmp = (char *)realloc(b->data, b->size + total + 1);
    if (!tmp) return 0; 
    b->data = tmp;
    memcpy(b->data + b->size, ptr, total);
    b->size += total;
    b->data[b->size] = '\0';
    return total;
}

/* ------------------------------------------------------------------- */
/*  REST call: returns 0/1, or -1 on error (sqlstate/errmsg set).      */
/* ------------------------------------------------------------------- */
static int call_rest(const char *userid, const char *bcnr_trim,
                     const char *konto_trim, char *sqlstate, char *msg)
{
    CURL *curl = curl_easy_init();
    if (!curl) {
        strcpy(sqlstate, "58004");
        strncpy(msg, "casauthorize: curl_easy_init failed", MSG_LEN - 1);
        msg[MSG_LEN - 1] = '\0';
        return -1;
    }

    char post[256];
    snprintf(post, sizeof(post),
             "{\"userid\":\"%.9s\",\"bcnr\":\"%s\",\"kontonr\":\"%s\"}",
             userid, bcnr_trim, konto_trim);

    struct curl_slist *hdrs = curl_slist_append(NULL, "Content-Type: application/json");

    curl_buf_t buf = { NULL, 0 };
    long   http_code = 0;
    int    rc        = -1;

    curl_easy_setopt(curl, CURLOPT_URL,            REST_URL);
    curl_easy_setopt(curl, CURLOPT_POST,           1L);
    curl_easy_setopt(curl, CURLOPT_POSTFIELDS,    post);
    curl_easy_setopt(curl, CURLOPT_HTTPHEADER,    hdrs);
    curl_easy_setopt(curl, CURLOPT_WRITEFUNCTION, curl_write_cb);
    curl_easy_setopt(curl, CURLOPT_WRITEDATA,     &buf);
    curl_easy_setopt(curl, CURLOPT_TIMEOUT,       REST_TIMEOUT_SEC);
    curl_easy_setopt(curl, CURLOPT_NOSIGNAL,     1L);
    curl_easy_setopt(curl, CURLOPT_FAILONERROR,  1L);

    CURLcode cres = curl_easy_perform(curl);
    curl_easy_getinfo(curl, CURLINFO_RESPONSE_CODE, &http_code);

    if (cres != CURLE_OK || http_code != 200 || !buf.data) {
        strcpy(sqlstate, "58004");
        snprintf(msg, MSG_LEN,
                 "casauthorize: REST failure curl=%d http=%ld", cres, http_code);
        goto done;
    }

    /* Tiny parser: find "authorization" : true|false */
    char *p = strstr(buf.data, "\"authorization\"");
    if (!p) p = strstr(buf.data, "authorization");
    if (p) {
        char *c = strchr(p, ':');
        if (c) {
            c++;
            while (*c == ' ' || *c == '\t' || *c == '\n' || *c == '\r') c++;
            if (!strncmp(c, "true", 4))      rc = 1;
            else if (!strncmp(c, "false", 5)) rc = 0;
            else {
                strcpy(sqlstate, "58004");
                strncpy(msg, "casauthorize: bad JSON body", MSG_LEN - 1);
                msg[MSG_LEN - 1] = '\0';
            }
        }
    }

done:
    curl_slist_free_all(hdrs);
    curl_easy_cleanup(curl);
    free(buf.data);
    return rc;
}

/* ------------------------------------------------------------------- */
/*  SysV semaphore helpers                                              */
/* ------------------------------------------------------------------- */
static int sem_lock(int semid) {
    struct sembuf op = { 0, -1, SEM_UNDO };
    while (semop(semid, &op, 1) == -1) {
        if (errno == EINTR) continue;
        return -1;
    }
    return 0;
}
static void sem_unlock(int semid) {
    struct sembuf op = { 0, +1, SEM_UNDO };
    while (semop(semid, &op, 1) == -1 && errno == EINTR) ;
}

/* ------------------------------------------------------------------- */
/*  Build lpad cache key (4 + 8 = 12 bytes)                            */
/* ------------------------------------------------------------------- */
static void build_key(const char *bcnr_trim, const char *konto_trim, uint8_t out[AUTH_KEY_LEN]) {
    /* Left-pad bcnr to 4 bytes */
    size_t blen = strlen(bcnr_trim);
    size_t bpad = (blen < BCNR_LEN) ? (BCNR_LEN - blen) : 0;
    memset(out, ' ', bpad);
    memcpy(out + bpad, bcnr_trim, (blen > BCNR_LEN) ? BCNR_LEN : blen);

    /* Left-pad kontonr to 8 bytes */
    size_t klen = strlen(konto_trim);
    size_t kpad = (klen < KONTO_MAX) ? (KONTO_MAX - klen) : 0;
    memset(out + BCNR_LEN, ' ', kpad);
    memcpy(out + BCNR_LEN + kpad, konto_trim, (klen > KONTO_MAX) ? KONTO_MAX : klen);
}

/* ------------------------------------------------------------------- */
/*  Main UDF entry point                                               */
/* ------------------------------------------------------------------- */
#ifdef __cplusplus
extern "C"
#endif
SQL_API_RC SQL_API_FN casauthorize(
        /* in  */ SQLUDF_CHAR   *userid,
        /* in  */ SQLUDF_CHAR   *bcnr,
        /* in  */ SQLUDF_CHAR   *kontonr,
        /* out */ sqlint16      *authFlag,
        /* out */ sqlint16      *authFlagInd,
        /* ix  */ sqlint16      *useridInd,
        /* ix  */ sqlint16      *bcnrInd,
        /* ix  */ sqlint16      *kontonrInd,
        /* io  */ char          *sqlstate,
        /* io  */ char          *fname,
        /* io  */ char          *finame,
        /* io  */ char          *msg,
        /* io  */ void          *scratchpad,
        /* io  */ sqlint16      *calltype)
{
    *authFlagInd = 0;
    *authFlag    = 0;

    if (*useridInd < 0) {
        *authFlagInd = -1;
        return 0;
    }

    /* ----- 1. Validate & Parse userid (t + 1-8 digits) ------------- */
    if (toupper(userid[0]) != 'T') {
        strcpy(sqlstate, "38503");
        strncpy(msg, "casauthorize: userid must start with 'T'", MSG_LEN - 1);
        msg[MSG_LEN - 1] = '\0';
        return 0;
    }

	long uid_num = atol(userid+1);
	if (uid_num == 0) {
        strcpy(sqlstate, "38503");
        strncpy(msg, "casauthorize: userid must be a Tnumber", MSG_LEN - 1);
        msg[MSG_LEN - 1] = '\0';
        return 0;
    }

    /* ----- 2. Validate & Parse bcnr (0-4 alnum chars) -------------- */
    /* If bcnr is provided NULL by DB2, treat as empty string */
    const char *bcnr_p = (*bcnrInd < 0) ? "" : bcnr;
    char bcnr_trim[BCNR_LEN + 1];
    size_t blen = 0;
    for (int i = 0; i < BCNR_LEN; ++i) {
        if (bcnr_p[i] == ' ' || bcnr_p[i] == '\0') break;
        if (!isalnum((unsigned char)bcnr_p[i])) {
            strcpy(sqlstate, "38503");
            strncpy(msg, "casauthorize: bcnr must be alphanumeric", MSG_LEN - 1);
            msg[MSG_LEN - 1] = '\0';
            return 0;
        }
        bcnr_trim[blen++] = bcnr_p[i];
    }
    bcnr_trim[blen] = '\0';

    /* ----- 3. Validate & Parse kontonr (0-8 alnum chars) ----------- */
    const char *konto_p = (*kontonrInd < 0) ? "" : kontonr;
    char konto_trim[KONTO_MAX + 1];
    size_t klen = 0;
    for (int i = 0; i < KONTO_MAX; ++i) {
        if (konto_p[i] == ' ' || konto_p[i] == '\0') break;
        if (!isalnum((unsigned char)konto_p[i])) {
            strcpy(sqlstate, "38503");
            strncpy(msg, "casauthorize: kontonr must be alphanumeric", MSG_LEN - 1);
            msg[MSG_LEN - 1] = '\0';
            return 0;
        }
        konto_trim[klen++] = konto_p[i];
    }
    konto_trim[klen] = '\0';

    /* ----- 4. Setup Shared Memory keys ----------------------------- */
    /* 
     * Offset keys to a specific application namespace (0x50xxxxxx).
     * This guarantees they will not collide with DB2's or OS segments.
     * Maximum userid is 99999999 (0x05F5E0FF), so the max combined key 
     * is 0x55F5E0FF, which safely fits in a signed 32-bit integer.
     */

    key_t shmkey = (key_t)(0x50000000L + uid_num);
    key_t semkey = (key_t)(0x51000000L + uid_num);
	
    /* ----- Acquire / create the shm segment ---------------------- */
    int shmid = shmget(shmkey, AUTH_BUCKET_BYTES, 0666);
    if (shmid == -1 && errno == ENOENT) {
        shmid = shmget(shmkey, AUTH_BUCKET_BYTES, IPC_CREAT | IPC_EXCL | 0666);
        if (shmid == -1 && errno == EEXIST)
            shmid = shmget(shmkey, AUTH_BUCKET_BYTES, 0666);
    }

    /* ----- Acquire / create the semaphore ------------------------- */
    int semid = semget(semkey, 1, 0666);
    if (semid == -1 && errno == ENOENT) {
        semid = semget(semkey, 1, IPC_CREAT | IPC_EXCL | 0666);
        if (semid == -1 && errno == EEXIST)
            semid = semget(semkey, 1, 0666);
        else if (semid != -1)
            (void)semctl(semid, 0, SETVAL, 1); 
    }

    /* Fallback to direct REST if IPC mechanisms fail */
    if (shmid == -1 || semid == -1) {
        int r = call_rest(userid, bcnr_trim, konto_trim, sqlstate, msg);
        if (r < 0) return 0;
        *authFlag = (sqlint16)r;
        return 0;
    }

    auth_bucket_t *bk = (auth_bucket_t *)shmat(shmid, NULL, 0);
    if (bk == (auth_bucket_t *)-1) {
        int r = call_rest(userid, bcnr_trim, konto_trim, sqlstate, msg);
        if (r < 0) return 0;
        *authFlag = (sqlint16)r;
        return 0;
    }

    /* ----- 5. Build 12-byte cache key ------------------------------ */
    uint8_t key[AUTH_KEY_LEN];
    build_key(bcnr_trim, konto_trim, key);

    time_t now = time(NULL);
    int    hit = -1;
    int    rc  = 0;
    int    expired = 0;

    /* ----- Lock bucket, do the cache read ----------------------- */
    if (sem_lock(semid) == 0) {
        expired = (bk->last_access == 0) ||
                  ((uint32_t)now - bk->last_access) > AUTH_TTL_SECONDS;

        if (!expired) {
            for (uint16_t i = 0; i < AUTH_MAX_ENTRIES; ++i) {
                if (memcmp(bk->entries[i], key, AUTH_KEY_LEN) == 0) {
                    hit = (int)i;
                    break;
                }
            }
        }

        if (hit >= 0) {
            rc = bk->entries[hit][AUTH_KEY_LEN];
            bk->last_access = (uint32_t)now; /* Refresh read access */
        }
        sem_unlock(semid);
    } else {
        shmdt(bk);
        int r = call_rest(userid, bcnr_trim, konto_trim, sqlstate, msg);
        if (r < 0) return 0;
        *authFlag = (sqlint16)r;
        return 0;
    }

    /* ----- On miss, call REST and update cache ------------------ */
    if (hit < 0) {
        int r = call_rest(userid, bcnr_trim, konto_trim, sqlstate, msg);
        if (r < 0) { shmdt(bk); return 0; }
        rc = r;

        if (sem_lock(semid) == 0) {
            if (bk->last_access == 0 || ((uint32_t)now - bk->last_access) > AUTH_TTL_SECONDS) {
                memset(bk->entries, 0, AUTH_MAX_ENTRIES * AUTH_RECORD_LEN);
            }

            /* FIFO Eviction: shift memory left by 1 record, discarding index 0 */
            memmove(&bk->entries[0], &bk->entries[1], (AUTH_MAX_ENTRIES - 1) * AUTH_RECORD_LEN);

            /* Insert new record at the end (index 99) */
            memcpy(&bk->entries[AUTH_MAX_ENTRIES - 1], key, AUTH_KEY_LEN);
            bk->entries[AUTH_MAX_ENTRIES - 1][AUTH_KEY_LEN] = (uint8_t)(rc ? 1 : 0);

            bk->last_access = (uint32_t)now;
            sem_unlock(semid);
        }
    }

    shmdt(bk);
    *authFlag = (sqlint16)rc;
    return 0;
}
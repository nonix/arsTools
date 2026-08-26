/* =====================================================================
 *  ipcclean.c
 *  Standalone cron job to clean up expired casauthorize cache segments.
 *  Compatible with AIX 7.3 and Linux.
 * Compile:
 *  gcc -maix64 -O2 -o ipcclean ipcclean.c
 *
 * Synopses:
 *  It uses popen("ipcs -m", "r") to safely enumerate all shared memory 
 *  segments without relying on non-standard kernel APIs (like SHM_INFO),
 *  parses the output for your 0x50 signature, checks the 4-byte timestamp,
 *  and removes both the shared memory and its matching 0x51 semaphore
 *  if they are older than 90 minutes.
 *
 * Display help
 *./ipcclean 
 * Output: Usage: ./ipcclean expiry_minutes [Tnumber]
 *
 * Remove all casauthorize entries regardless of age
 *./ipcclean 0
 *
 * Remove t320818 if last used was older than 10 minutes
 *./ipcclean 10 t320818
 *
 * Run for all matching keys older than 90 minutes (ideal for cron)
 *./ipcclean 90
 * ===================================================================== */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <ctype.h>
#include <time.h>
#include <sys/types.h>
#include <sys/ipc.h>
#include <sys/shm.h>
#include <sys/sem.h>

/* Must match the UDF definitions */
#define AUTH_MAX_ENTRIES   100
#define BCNR_LEN           4
#define KONTO_MAX          8
#define AUTH_KEY_LEN       (BCNR_LEN + KONTO_MAX)        /* 12 bytes */
#define AUTH_RECORD_LEN    (AUTH_KEY_LEN + 1)            /* 13 bytes */
#define AUTH_BUCKET_BYTES  (4 + (AUTH_MAX_ENTRIES * AUTH_RECORD_LEN)) /* 1304 */

void print_usage(const char *prog_name) {
    fprintf(stderr, "Usage: %s expiry_minutes [Tnumber]\n", prog_name);
    fprintf(stderr, "  expiry_minutes: Minutes of inactivity before removal (0 = remove all immediately)\n");
    fprintf(stderr, "  Tnumber: Optional specific user (e.g., t320818) to target\n");
}

/* Helper to check and remove a specific shm/sem pair */
void clean_segment(key_t shmkey, key_t semkey, int exp_min) {
    int shmid = shmget(shmkey, AUTH_BUCKET_BYTES, 0666);
    if (shmid == -1) return; /* Doesn't exist */

    int remove_it = 0;
    if (exp_min == 0) {
        remove_it = 1; /* Special case: 0 minutes = force remove */
    } else {
        void *ptr = shmat(shmid, NULL, 0);
        if (ptr != (void *)-1) {
            uint32_t last_access = *(uint32_t *)ptr;
            shmdt(ptr);

            time_t now = time(NULL);
            if (now - last_access > (exp_min * 60)) {
                remove_it = 1;
            }
        }
    }

    if (remove_it) {
        if (shmctl(shmid, IPC_RMID, NULL) == 0) {
            printf("Removed SHM key 0x%08x\n", shmkey);
        }
        int semid = semget(semkey, 1, 0666);
        if (semid != -1) {
            if (semctl(semid, 0, IPC_RMID, 0) == 0) {
                printf("Removed SEM key 0x%08x\n", semkey);
            }
        }
    }
}

int main(int argc, char *argv[])
{
    if (argc < 2 || argc > 3) {
        print_usage(argv[0]);
        return 1;
    }

    int exp_min = atoi(argv[1]);
    if (exp_min < 0) {
        print_usage(argv[0]);
        return 1;
    }

    /* ----- Case 1: Specific Tnumber provided ----- */
    if (argc == 3) {
        const char *t = argv[2];
        if (strlen(t) < 2 || (t[0] != 't' && t[0] != 'T')) {
            print_usage(argv[0]);
            return 1;
        }

        /* Validate numeric portion */
        for (int i = 1; t[i] != '\0'; ++i) {
            if (!isdigit((unsigned char)t[i])) {
                print_usage(argv[0]);
                return 1;
            }
        }

        long uid_num = atol(t + 1);
        key_t shmkey = (key_t)(0x50000000L + uid_num);
        key_t semkey = (key_t)(0x51000000L + uid_num);

        clean_segment(shmkey, semkey, exp_min);
        return 0;
    }

    /* ----- Case 2: Global scan via ipcs ----- */
    FILE *fp = popen("ipcs -m", "r");
    if (!fp) {
        perror("ipcclean: popen failed");
        return 1;
    }

    char line[256];
    int cleaned = 0;

    /* Read ipcs output line by line */
    while (fgets(line, sizeof(line), fp)) {
        char *tok = strtok(line, " \t\n");
        while (tok != NULL) {
            /* Look for tokens that are exactly 10 chars long and start with 0x50 */
            if (strlen(tok) == 10 && tok[0] == '0' && (tok[1] == 'x' || tok[1] == 'X')) {
                key_t shmkey = (key_t)strtoul(tok, NULL, 16);
                
                /* Check if it's one of our segments (0x50000000 mask) */
                if ((shmkey & 0xFF000000) == 0x50000000) {
                    key_t semkey = (shmkey & 0x00FFFFFF) | 0x51000000;
                    
                    /* If exp_min == 0, we will definitely remove it, count it */
                    if (exp_min == 0) {
                        int shmid = shmget(shmkey, AUTH_BUCKET_BYTES, 0666);
                        if (shmid != -1) cleaned++;
                    }
                    
                    clean_segment(shmkey, semkey, exp_min);
                }
            }
            tok = strtok(NULL, " \t\n");
        }
    }

    pclose(fp);

    if (exp_min == 0 && cleaned == 0) {
        printf("No casauthorize cache segments found to remove.\n");
    }

    return 0;
}

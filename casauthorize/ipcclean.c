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
 * ===================================================================== */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
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

#define EXPIRY_SECONDS     (90 * 60)  /* 90 minutes */

int main(void)
{
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
                    int shmid = shmget(shmkey, AUTH_BUCKET_BYTES, 0666);
                    if (shmid != -1) {
                        void *ptr = shmat(shmid, NULL, 0);
                        if (ptr != (void *)-1) {
                            uint32_t last_access = *(uint32_t *)ptr;
                            shmdt(ptr);

                            time_t now = time(NULL);
                            if (now - last_access > EXPIRY_SECONDS) {
                                /* Expired! Remove Shared Memory */
                                if (shmctl(shmid, IPC_RMID, NULL) == 0) {
                                    printf("Removed SHM key %s (last access %ld sec ago)\n", 
                                           tok, (long)(now - last_access));
                                    cleaned++;
                                }
                                
                                /* Compute matching semkey and remove Semaphore */
                                key_t semkey = (shmkey & 0x00FFFFFF) | 0x51000000;
                                int semid = semget(semkey, 1, 0666);
                                if (semid != -1) {
                                    if (semctl(semid, 0, IPC_RMID, 0) == 0) {
                                        printf("Removed SEM key 0x%08x\n", semkey);
                                    }
                                }
                            }
                        }
                    }
                }
            }
            tok = strtok(NULL, " \t\n");
        }
    }

    pclose(fp);

    if (cleaned == 0) {
        printf("No expired casauthorize cache segments found.\n");
    } else {
        printf("Cleanup complete. Removed %d expired segment(s).\n", cleaned);
    }

    return 0;
}

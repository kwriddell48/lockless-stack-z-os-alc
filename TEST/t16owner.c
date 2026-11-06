/* T16OWNER - pusher TCB exits before pop; oversize srcLen RC=8. */
#define _OPEN_THREADS 1
#include "mpmcs.h"

#ifdef __MVS__
#pragma runopts(POSIX(ON))
#endif

#include <pthread.h>

/* Inline path (<=256): node comes from SINIT prefill (mother TCB),
 * so the pusher thread does not STORAGE OBTAIN. Unauthorized SP=0
 * would free a worker-owned >inline payload at pthread exit. */
#define PAY 200

static unsigned char src[200];
static void *g_scb;

static void *pusher(void *arg)
{
    (void)arg;
    if (mpmcs_spush(g_scb, src, PAY) != MPMCS_RC_OK)
        return (void *)8;
    return 0;
}

int main(void)
{
    void *scb;
    pthread_t tid;
    void *tr;
    unsigned char dst[200];
    uint32_t n = 0;
    int i;

    printf("T16OWNER start\n");
    fflush(stdout);

    scb = mpmcs_alloc_scb();
    TEST_EXPECT(scb != NULL, "SCB alloc failed");
    TEST_RC(mpmcs_sinit(scb,
            MPMCS_NODE_PREFILL(8) | MPMCS_OPT_PAYLOAD31,
            0, 0, 0),
            MPMCS_RC_OK, "SINIT");

    TEST_RC(mpmcs_spush(scb, scb, 0x01000000u),
            MPMCS_RC_ALLOC_FAIL, "oversize srcLen");

    for (i = 0; i < PAY; i++)
        src[i] = (unsigned char)(i & 0xFF);
    src[0] = 0x11;
    src[PAY - 1] = 0x22;
    g_scb = scb;

    TEST_EXPECT(pthread_create(&tid, 0, pusher, 0) == 0,
                "pthread_create");
    TEST_EXPECT(pthread_join(tid, &tr) == 0, "pthread_join");
    TEST_EXPECT(tr == 0, "pusher rc");

    memset(dst, 0, sizeof(dst));
    TEST_RC(mpmcs_spop(scb, dst, PAY, &n), MPMCS_RC_OK, "pop");
    TEST_EXPECT(n == PAY, "pop length");
    TEST_EXPECT(dst[0] == 0x11, "first byte");
    TEST_EXPECT(dst[PAY - 1] == 0x22, "last byte");
    TEST_EXPECT(memcmp(dst, src, PAY) == 0, "payload");

    TEST_RC(mpmcs_scbstop(scb), MPMCS_RC_OK, "SCBSTOP");
    printf("T16OWNER PASS\n");
    mpmcs_free(scb);
    return 0;
}

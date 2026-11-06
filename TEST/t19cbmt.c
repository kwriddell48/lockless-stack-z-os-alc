/* T19CBMT - notifier under multi-producer storm. */
#define _OPEN_THREADS 1
#include "mpmcs.h"

#ifdef __MVS__
#pragma runopts(POSIX(ON))
#pragma linkage(CTESTEP, OS)
#endif
extern void CTESTEP(void **out);

#include <pthread.h>

#define NPROD 6
#define NPUSH 200

typedef struct {
    void *scb;
    int   id;
    int   rc;
} Prod;

static volatile uint32_t g_seen;
static volatile int g_go;

static void *producer(void *arg)
{
    Prod *p = (Prod *)arg;
    char buf[8];
    uint32_t i;

    while (!g_go)
        ;

    p->rc = 0;
    buf[0] = (char)('A' + (p->id % 26));
    for (i = 0; i < NPUSH; i++) {
        buf[1] = (char)(i & 0x7F);
        if (mpmcs_spush(p->scb, buf, 2) != MPMCS_RC_OK) {
            p->rc = 8;
            return 0;
        }
    }
    return 0;
}

int main(void)
{
    void *scb;
    void *cb;
    pthread_t tid[NPROD];
    Prod prod[NPROD];
    char out[8];
    uint32_t n = 0;
    MpmcsStats st;
    int i;
    int spins;
    uint32_t total = (uint32_t)(NPROD * NPUSH);

    printf("T19CBMT start prods=%d each=%d\n", NPROD, NPUSH);
    fflush(stdout);

    scb = mpmcs_alloc_scb();
    TEST_EXPECT(scb != NULL, "SCB alloc");
    cb = 0;
    CTESTEP(&cb);
    TEST_EXPECT(cb != 0, "TESTCB");
    g_seen = 0;
    TEST_RC(mpmcs_sinit(scb,
            MPMCS_NODE_PREFILL(256) | MPMCS_OPT_PAYLOAD31,
            cb, (void *)&g_seen, 0),
            MPMCS_RC_OK, "SINIT");

    g_go = 0;
    for (i = 0; i < NPROD; i++) {
        prod[i].scb = scb;
        prod[i].id = i;
        if (pthread_create(&tid[i], 0, producer, &prod[i]) != 0)
            TEST_FAIL("pthread_create");
    }
    g_go = 1;
    for (i = 0; i < NPROD; i++)
        pthread_join(tid[i], 0);
    for (i = 0; i < NPROD; i++)
        TEST_EXPECT(prod[i].rc == 0, "prod rc");

    for (spins = 0; spins < 400; spins++) {
        TEST_RC(mpmcs_sstats(scb, &st), MPMCS_RC_OK, "poll");
        if (st.cb_calls >= 1 && g_seen >= 1)
            break;
        mpmcs_spin(200000u);
    }

    TEST_RC(mpmcs_sstats(scb, &st), MPMCS_RC_OK, "SSTATS");
    TEST_EXPECT(st.push_ok == total, "push_ok");
    TEST_EXPECT(st.cb_calls >= 1, "cb_calls");
    TEST_EXPECT(g_seen >= 1, "seen");
    TEST_EXPECT(g_seen <= total, "seen high");
    TEST_EXPECT(st.post_internal >= 1, "internal POST");
    TEST_EXPECT(st.cb_pending_max >= 1, "pending_max");

    printf("cb_calls=%u seen=%u pending_max=%u posts=%u\n",
           (unsigned)st.cb_calls, (unsigned)g_seen,
           (unsigned)st.cb_pending_max,
           (unsigned)st.post_internal);

    for (i = 0; (uint32_t)i < total; i++)
        TEST_RC(mpmcs_spop(scb, out, 2, &n), MPMCS_RC_OK, "pop");
    TEST_RC(mpmcs_spop(scb, out, 2, &n), MPMCS_RC_EMPTY, "empty");

    TEST_RC(mpmcs_scbstop(scb), MPMCS_RC_OK, "SCBSTOP");
    printf("T19CBMT PASS\n");
    mpmcs_free(scb);
    return 0;
}

/* T18MIXQ - two independent SCBs, threads bounce between them. */
#define _OPEN_THREADS 1
#include "mpmcs.h"

#ifdef __MVS__
#pragma runopts(POSIX(ON))
#endif

#include <pthread.h>

#define NTHR  6
#define NOPS  300

typedef struct {
    uint32_t q;
    uint32_t thr;
    uint32_t seq;
    uint32_t xorv;
} Msg;

typedef struct {
    void    *scb0;
    void    *scb1;
    int      id;
    uint64_t sum0;
    uint64_t sum1;
    uint32_t n0;
    uint32_t n1;
    int      rc;
} Worker;

static volatile int g_go;

static uint32_t msg_xor(uint32_t q, uint32_t thr, uint32_t seq)
{
    return 0xC0FFEEu ^ q ^ (thr << 8) ^ seq;
}

static void *worker(void *arg)
{
    Worker *w = (Worker *)arg;
    Msg msg;
    Msg out;
    void *scb;
    uint32_t n;
    uint32_t i;
    uint32_t q;
    int32_t rc;

    while (!g_go)
        ;

    w->sum0 = w->sum1 = 0;
    w->n0 = w->n1 = 0;
    w->rc = 0;

    for (i = 0; i < NOPS; i++) {
        q = (uint32_t)((w->id + (int)i) & 1);
        scb = (q == 0) ? w->scb0 : w->scb1;
        msg.q = q;
        msg.thr = (uint32_t)w->id;
        msg.seq = i;
        msg.xorv = msg_xor(q, msg.thr, msg.seq);
        if (mpmcs_spush(scb, &msg, (uint32_t)sizeof(msg))
            != MPMCS_RC_OK) {
            w->rc = 8;
            return 0;
        }
        if (q == 0) {
            w->sum0 += msg.seq;
            w->n0++;
        } else {
            w->sum1 += msg.seq;
            w->n1++;
        }

        /* Pop from the other queue to cross traffic. */
        scb = (q == 0) ? w->scb1 : w->scb0;
        n = 0;
        rc = mpmcs_spop(scb, &out, (uint32_t)sizeof(out), &n);
        if (rc == MPMCS_RC_OK) {
            if (n != (uint32_t)sizeof(out) ||
                out.xorv != msg_xor(out.q, out.thr, out.seq) ||
                out.q != (q ^ 1u)) {
                w->rc = 8;
                return 0;
            }
        } else if (rc != MPMCS_RC_EMPTY) {
            w->rc = 8;
            return 0;
        }
    }
    return 0;
}

static int drain_q(void *scb, uint64_t *sum, uint32_t *cnt,
                   uint32_t expect_q)
{
    Msg out;
    uint32_t n;
    int32_t rc;

    for (;;) {
        n = 0;
        rc = mpmcs_spop(scb, &out, (uint32_t)sizeof(out), &n);
        if (rc == MPMCS_RC_EMPTY)
            return 0;
        if (rc != MPMCS_RC_OK)
            return 8;
        if (n != (uint32_t)sizeof(out) ||
            out.q != expect_q ||
            out.xorv != msg_xor(out.q, out.thr, out.seq))
            return 8;
        *sum += out.seq;
        (*cnt)++;
    }
}

int main(void)
{
    void *scb0;
    void *scb1;
    pthread_t tid[NTHR];
    Worker w[NTHR];
    uint64_t pop0 = 0;
    uint64_t pop1 = 0;
    uint32_t n0 = 0;
    uint32_t n1 = 0;
    MpmcsStats st0;
    MpmcsStats st1;
    int i;

    printf("T18MIXQ start thr=%d ops=%d\n", NTHR, NOPS);
    fflush(stdout);

    scb0 = mpmcs_alloc_scb();
    scb1 = mpmcs_alloc_scb();
    TEST_EXPECT(scb0 && scb1, "SCB alloc");
    TEST_RC(mpmcs_sinit(scb0,
            MPMCS_NODE_PREFILL(128) | MPMCS_OPT_PAYLOAD31,
            0, 0, 0), MPMCS_RC_OK, "SINIT0");
    TEST_RC(mpmcs_sinit(scb1,
            MPMCS_NODE_PREFILL(128) | MPMCS_OPT_PAYLOAD31,
            0, 0, 0), MPMCS_RC_OK, "SINIT1");

    g_go = 0;
    for (i = 0; i < NTHR; i++) {
        w[i].scb0 = scb0;
        w[i].scb1 = scb1;
        w[i].id = i;
        if (pthread_create(&tid[i], 0, worker, &w[i]) != 0)
            TEST_FAIL("pthread_create");
    }
    g_go = 1;
    for (i = 0; i < NTHR; i++)
        pthread_join(tid[i], 0);

    for (i = 0; i < NTHR; i++)
        TEST_EXPECT(w[i].rc == 0, "worker rc");

    TEST_EXPECT(drain_q(scb0, &pop0, &n0, 0) == 0, "drain0");
    TEST_EXPECT(drain_q(scb1, &pop1, &n1, 1) == 0, "drain1");
    TEST_RC(mpmcs_sstats(scb0, &st0), MPMCS_RC_OK, "SSTATS0");
    TEST_RC(mpmcs_sstats(scb1, &st1), MPMCS_RC_OK, "SSTATS1");
    TEST_EXPECT(st0.push_ok == st0.pop_ok, "q0 balance");
    TEST_EXPECT(st1.push_ok == st1.pop_ok, "q1 balance");
    TEST_EXPECT(st0.push_ok + st1.push_ok ==
                (uint32_t)(NTHR * NOPS), "total push");
    TEST_EXPECT(st0.depth_cur == 0 && st1.depth_cur == 0,
                "depth");
    (void)pop0;
    (void)pop1;

    printf("q0 push=%u q1 push=%u retries=%u/%u\n",
           (unsigned)st0.push_ok, (unsigned)st1.push_ok,
           (unsigned)(st0.push_retry + st0.pop_retry),
           (unsigned)(st1.push_retry + st1.pop_retry));

    TEST_RC(mpmcs_scbstop(scb0), MPMCS_RC_OK, "STOP0");
    TEST_RC(mpmcs_scbstop(scb1), MPMCS_RC_OK, "STOP1");
    printf("T18MIXQ PASS\n");
    mpmcs_free(scb0);
    mpmcs_free(scb1);
    return 0;
}

/* T17STORM - high-contention churn: all threads push and pop. */
#define _OPEN_THREADS 1
#include "mpmcs.h"

#ifdef __MVS__
#pragma runopts(POSIX(ON))
#endif

#include <pthread.h>

#define NTHR  8
#define NOPS  400

typedef struct {
    uint32_t thr;
    uint32_t seq;
    uint32_t mark;
    uint32_t pad;
} Msg;

typedef struct {
    void    *scb;
    int      id;
    uint64_t push_sum;
    uint64_t pop_sum;
    uint32_t npush;
    uint32_t npop;
    int      rc;
} Worker;

static volatile int g_go;

static void *worker(void *arg)
{
    Worker *w = (Worker *)arg;
    Msg msg;
    Msg out;
    uint32_t n;
    uint32_t i;
    int32_t rc;
    unsigned idle;

    while (!g_go)
        ;

    w->push_sum = 0;
    w->pop_sum = 0;
    w->npush = 0;
    w->npop = 0;
    w->rc = 0;

    for (i = 0; i < NOPS; i++) {
        msg.thr = (uint32_t)w->id;
        msg.seq = i;
        msg.mark = 0xA5A50000u ^ (uint32_t)w->id ^ i;
        msg.pad = 0;
        if (mpmcs_spush(w->scb, &msg, (uint32_t)sizeof(msg))
            != MPMCS_RC_OK) {
            w->rc = 8;
            return 0;
        }
        w->push_sum += ((uint64_t)msg.thr << 32) | msg.seq;
        w->npush++;

        /* Immediate try-pop: create TOP/FREE churn under contention. */
        n = 0;
        rc = mpmcs_spop(w->scb, &out, (uint32_t)sizeof(out), &n);
        if (rc == MPMCS_RC_OK) {
            if (n != (uint32_t)sizeof(out) ||
                out.mark !=
                (0xA5A50000u ^ out.thr ^ out.seq)) {
                w->rc = 8;
                return 0;
            }
            w->pop_sum += ((uint64_t)out.thr << 32) | out.seq;
            w->npop++;
        } else if (rc != MPMCS_RC_EMPTY) {
            w->rc = 8;
            return 0;
        }
    }

    /* Drain remaining until quiet. */
    idle = 0;
    for (;;) {
        n = 0;
        rc = mpmcs_spop(w->scb, &out, (uint32_t)sizeof(out), &n);
        if (rc == MPMCS_RC_OK) {
            idle = 0;
            if (n != (uint32_t)sizeof(out) ||
                out.mark !=
                (0xA5A50000u ^ out.thr ^ out.seq)) {
                w->rc = 8;
                return 0;
            }
            w->pop_sum += ((uint64_t)out.thr << 32) | out.seq;
            w->npop++;
            continue;
        }
        if (rc != MPMCS_RC_EMPTY) {
            w->rc = 8;
            return 0;
        }
        if (++idle > 50000u)
            break;
        mpmcs_spin(200u);
    }
    return 0;
}

int main(void)
{
    void *scb;
    pthread_t tid[NTHR];
    Worker w[NTHR];
    uint64_t psum = 0;
    uint64_t csum = 0;
    uint32_t np = 0;
    uint32_t nc = 0;
    MpmcsStats st;
    Msg leftover;
    uint32_t n = 0;
    int i;

    printf("T17STORM start thr=%d ops=%d\n", NTHR, NOPS);
    fflush(stdout);

    scb = mpmcs_alloc_scb();
    TEST_EXPECT(scb != NULL, "SCB alloc failed");
    TEST_RC(mpmcs_sinit(scb,
            MPMCS_NODE_PREFILL(256) | MPMCS_OPT_PAYLOAD31,
            0, 0, 0),
            MPMCS_RC_OK, "SINIT");

    g_go = 0;
    for (i = 0; i < NTHR; i++) {
        w[i].scb = scb;
        w[i].id = i;
        if (pthread_create(&tid[i], 0, worker, &w[i]) != 0)
            TEST_FAIL("pthread_create");
    }
    g_go = 1;
    for (i = 0; i < NTHR; i++)
        pthread_join(tid[i], 0);

    for (i = 0; i < NTHR; i++) {
        TEST_EXPECT(w[i].rc == 0, "worker rc");
        psum += w[i].push_sum;
        csum += w[i].pop_sum;
        np += w[i].npush;
        nc += w[i].npop;
    }

    for (;;) {
        n = 0;
        if (mpmcs_spop(scb, &leftover, (uint32_t)sizeof(leftover),
                       &n) != MPMCS_RC_OK)
            break;
        TEST_EXPECT(n == (uint32_t)sizeof(leftover), "drain len");
        csum += ((uint64_t)leftover.thr << 32) | leftover.seq;
        nc++;
    }

    TEST_EXPECT(np == (uint32_t)(NTHR * NOPS), "push count");
    TEST_EXPECT(nc == np, "pop count");
    TEST_EXPECT(csum == psum, "checksum");

    TEST_RC(mpmcs_sstats(scb, &st), MPMCS_RC_OK, "SSTATS");
    TEST_EXPECT(st.depth_cur == 0, "depth_cur");
    printf("push=%u pop=%u retry p/p=%u/%u fl=%u/%u dmax=%u\n",
           (unsigned)st.push_ok, (unsigned)st.pop_ok,
           (unsigned)st.push_retry, (unsigned)st.pop_retry,
           (unsigned)st.freelist_pop_retry,
           (unsigned)st.freelist_push_retry,
           (unsigned)st.depth_max);

    TEST_RC(mpmcs_scbstop(scb), MPMCS_RC_OK, "SCBSTOP");
    printf("T17STORM PASS\n");
    mpmcs_free(scb);
    return 0;
}

/* T12CONC - several producer and consumer threads, checksum of ids. */
#define _OPEN_THREADS 1
#include "mpmcs.h"

#ifdef __MVS__
#pragma runopts(POSIX(ON))
#endif

#include <pthread.h>

#define NPROD 4
#define NCONS 4
#define NPUSH 250

typedef struct {
    void    *scb;
    int      id;
    uint64_t sum;
    uint32_t count;
    int      rc;
} Worker;

static void *producer(void *arg)
{
    Worker *w = (Worker *)arg;
    uint32_t seq;
    uint32_t payload[2];

    w->sum = 0;
    w->count = 0;
    w->rc = 0;
    for (seq = 0; seq < NPUSH; seq++) {
        payload[0] = (uint32_t)w->id;
        payload[1] = seq;
        if (mpmcs_spush(w->scb, payload, (uint32_t)sizeof(payload))
            != MPMCS_RC_OK) {
            w->rc = 8;
            return 0;
        }
        w->sum += ((uint64_t)w->id * NPUSH) + seq;
        w->count++;
    }
    return 0;
}

static void *consumer(void *arg)
{
    Worker *w = (Worker *)arg;
    uint32_t payload[2];
    uint32_t n;
    int32_t rc;
    unsigned idle = 0;

    w->sum = 0;
    w->count = 0;
    w->rc = 0;
    for (;;) {
        n = 0;
        rc = mpmcs_spop(w->scb, payload, (uint32_t)sizeof(payload), &n);
        if (rc == MPMCS_RC_OK) {
            idle = 0;
            if (n != (uint32_t)sizeof(payload)) {
                w->rc = 8;
                break;
            }
            w->sum += ((uint64_t)payload[0] * NPUSH) + payload[1];
            w->count++;
            continue;
        }
        if (rc != MPMCS_RC_EMPTY) {
            w->rc = 8;
            break;
        }
        if (++idle > 200000u)
            break;
    }
    return 0;
}

int main(void)
{
    void *scb;
    pthread_t tp[NPROD];
    pthread_t tc[NCONS];
    Worker prod[NPROD];
    Worker cons[NCONS];
    uint64_t expect = 0;
    uint64_t got = 0;
    uint32_t npop = 0;
    MpmcsStats st;
    int i;
    uint32_t leftover[2];
    uint32_t n = 0;

    printf("T12CONC start prods=%d cons=%d each=%d\n",
           NPROD, NCONS, NPUSH);
    fflush(stdout);

    scb = mpmcs_alloc_scb();
    TEST_EXPECT(scb != NULL, "SCB alloc failed");
    TEST_RC(mpmcs_sinit(scb,
                        MPMCS_NODE_PREFILL(128) | MPMCS_OPT_PAYLOAD31,
                        0, 0, 0),
            MPMCS_RC_OK, "SINIT");

    for (i = 0; i < NPROD; i++) {
        prod[i].scb = scb;
        prod[i].id = i;
        if (pthread_create(&tp[i], 0, producer, &prod[i]) != 0)
            TEST_FAIL("pthread_create producer");
    }
    for (i = 0; i < NCONS; i++) {
        cons[i].scb = scb;
        cons[i].id = i;
        if (pthread_create(&tc[i], 0, consumer, &cons[i]) != 0)
            TEST_FAIL("pthread_create consumer");
    }

    for (i = 0; i < NPROD; i++)
        pthread_join(tp[i], 0);
    for (i = 0; i < NCONS; i++)
        pthread_join(tc[i], 0);

    for (i = 0; i < NPROD; i++) {
        TEST_EXPECT(prod[i].rc == 0, "producer rc");
        expect += prod[i].sum;
    }
    for (i = 0; i < NCONS; i++) {
        TEST_EXPECT(cons[i].rc == 0, "consumer rc");
        got += cons[i].sum;
        npop += cons[i].count;
    }

    /* Drain anything still on the stack (consumer idle-exit). */
    for (;;) {
        n = 0;
        if (mpmcs_spop(scb, leftover, (uint32_t)sizeof(leftover), &n)
            != MPMCS_RC_OK)
            break;
        TEST_EXPECT(n == 8, "drain len");
        got += ((uint64_t)leftover[0] * NPUSH) + leftover[1];
        npop++;
    }

    TEST_EXPECT(npop == (uint32_t)(NPROD * NPUSH),
                "lost or extra pops");
    TEST_EXPECT(got == expect, "id checksum mismatch");

    TEST_RC(mpmcs_sstats(scb, &st), MPMCS_RC_OK, "SSTATS");
    TEST_EXPECT(st.push_ok == (uint32_t)(NPROD * NPUSH), "push_ok");
    TEST_EXPECT(st.pop_ok == (uint32_t)(NPROD * NPUSH), "pop_ok");
    TEST_EXPECT(st.depth_cur == 0, "depth_cur after drain");

    printf("pushed=%u popped=%u retries push/pop=%u/%u depth_max=%u\n",
           (unsigned)st.push_ok, (unsigned)st.pop_ok,
           (unsigned)st.push_retry, (unsigned)st.pop_retry,
           (unsigned)st.depth_max);

    TEST_RC(mpmcs_scbstop(scb), MPMCS_RC_OK, "SCBSTOP");
    printf("T12CONC PASS\n");
    mpmcs_free(scb);
    return 0;
}

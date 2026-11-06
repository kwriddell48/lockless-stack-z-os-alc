/* T20WAVE - producer waves exit while consumers keep draining. */
#define _OPEN_THREADS 1
#include "mpmcs.h"

#ifdef __MVS__
#pragma runopts(POSIX(ON))
#endif

#include <pthread.h>

#define NWAVE   4
#define NPROD   4
#define NCONS   4
#define NPUSH   150
#define PAYLEN  64

typedef struct {
    uint32_t wave;
    uint32_t thr;
    uint32_t seq;
    uint32_t crc;
    unsigned char body[PAYLEN - 16];
} Msg;

typedef struct {
    void    *scb;
    int      id;
    uint32_t wave;
    uint64_t sum;
    uint32_t count;
    int      rc;
} Worker;

static volatile int g_stop_cons;
static volatile uint32_t g_wave_done;

static uint32_t msg_crc(const Msg *m)
{
    uint32_t c = 0x12345678u;
    uint32_t i;
    c ^= m->wave ^ (m->thr << 10) ^ m->seq;
    for (i = 0; i < sizeof(m->body); i++)
        c = (c * 33u) + m->body[i];
    return c;
}

static void *producer(void *arg)
{
    Worker *w = (Worker *)arg;
    Msg msg;
    uint32_t i;
    uint32_t j;

    w->sum = 0;
    w->count = 0;
    w->rc = 0;
    memset(&msg, 0, sizeof(msg));
    msg.wave = w->wave;
    msg.thr = (uint32_t)w->id;
    for (j = 0; j < sizeof(msg.body); j++)
        msg.body[j] = (unsigned char)(w->id + j + w->wave);

    for (i = 0; i < NPUSH; i++) {
        msg.seq = i;
        msg.crc = msg_crc(&msg);
        if (mpmcs_spush(w->scb, &msg, (uint32_t)sizeof(msg))
            != MPMCS_RC_OK) {
            w->rc = 8;
            return 0;
        }
        w->sum += ((uint64_t)msg.wave << 48) |
                  ((uint64_t)msg.thr << 32) | msg.seq;
        w->count++;
    }
    return 0;
}

static void *consumer(void *arg)
{
    Worker *w = (Worker *)arg;
    Msg out;
    uint32_t n;
    int32_t rc;
    unsigned idle = 0;

    w->sum = 0;
    w->count = 0;
    w->rc = 0;
    for (;;) {
        n = 0;
        rc = mpmcs_spop(w->scb, &out, (uint32_t)sizeof(out), &n);
        if (rc == MPMCS_RC_OK) {
            idle = 0;
            if (n != (uint32_t)sizeof(out) ||
                out.crc != msg_crc(&out)) {
                w->rc = 8;
                return 0;
            }
            w->sum += ((uint64_t)out.wave << 48) |
                      ((uint64_t)out.thr << 32) | out.seq;
            w->count++;
            continue;
        }
        if (rc != MPMCS_RC_EMPTY) {
            w->rc = 8;
            return 0;
        }
        if (g_stop_cons && g_wave_done == NWAVE) {
            if (++idle > 100000u)
                break;
        } else {
            idle = 0;
        }
        mpmcs_spin(50u);
    }
    return 0;
}

int main(void)
{
    void *scb;
    pthread_t tc[NCONS];
    pthread_t tp[NPROD];
    Worker cons[NCONS];
    Worker prod[NPROD];
    uint64_t expect = 0;
    uint64_t got = 0;
    uint32_t npop = 0;
    MpmcsStats st;
    Msg leftover;
    uint32_t n = 0;
    int w;
    int i;

    printf("T20WAVE waves=%d prod=%d cons=%d each=%d\n",
           NWAVE, NPROD, NCONS, NPUSH);
    fflush(stdout);

    scb = mpmcs_alloc_scb();
    TEST_EXPECT(scb != NULL, "SCB alloc");
    /* Prefill so waves reuse mother-owned nodes (inline body). */
    TEST_RC(mpmcs_sinit(scb,
            MPMCS_NODE_PREFILL(512) | MPMCS_OPT_PAYLOAD31,
            0, 0, 0),
            MPMCS_RC_OK, "SINIT");

    g_stop_cons = 0;
    g_wave_done = 0;
    for (i = 0; i < NCONS; i++) {
        cons[i].scb = scb;
        cons[i].id = i;
        cons[i].wave = 0;
        if (pthread_create(&tc[i], 0, consumer, &cons[i]) != 0)
            TEST_FAIL("cons create");
    }

    for (w = 0; w < NWAVE; w++) {
        for (i = 0; i < NPROD; i++) {
            prod[i].scb = scb;
            prod[i].id = i;
            prod[i].wave = (uint32_t)w;
            if (pthread_create(&tp[i], 0, producer, &prod[i]) != 0)
                TEST_FAIL("prod create");
        }
        for (i = 0; i < NPROD; i++) {
            pthread_join(tp[i], 0);
            TEST_EXPECT(prod[i].rc == 0, "prod rc");
            expect += prod[i].sum;
        }
        g_wave_done = (uint32_t)(w + 1);
        mpmcs_spin(10000u);
    }

    g_stop_cons = 1;
    for (i = 0; i < NCONS; i++)
        pthread_join(tc[i], 0);

    for (i = 0; i < NCONS; i++) {
        TEST_EXPECT(cons[i].rc == 0, "cons rc");
        got += cons[i].sum;
        npop += cons[i].count;
    }

    for (;;) {
        n = 0;
        if (mpmcs_spop(scb, &leftover, (uint32_t)sizeof(leftover),
                       &n) != MPMCS_RC_OK)
            break;
        TEST_EXPECT(n == (uint32_t)sizeof(leftover), "drain");
        TEST_EXPECT(leftover.crc == msg_crc(&leftover), "crc");
        got += ((uint64_t)leftover.wave << 48) |
               ((uint64_t)leftover.thr << 32) | leftover.seq;
        npop++;
    }

    TEST_EXPECT(npop == (uint32_t)(NWAVE * NPROD * NPUSH),
                "count");
    TEST_EXPECT(got == expect, "checksum");

    TEST_RC(mpmcs_sstats(scb, &st), MPMCS_RC_OK, "SSTATS");
    TEST_EXPECT(st.depth_cur == 0, "depth");
    printf("total=%u retries p/p=%u/%u fl=%u/%u dmax=%u\n",
           (unsigned)st.push_ok,
           (unsigned)st.push_retry, (unsigned)st.pop_retry,
           (unsigned)st.freelist_pop_retry,
           (unsigned)st.freelist_push_retry,
           (unsigned)st.depth_max);

    TEST_RC(mpmcs_scbstop(scb), MPMCS_RC_OK, "SCBSTOP");
    printf("T20WAVE PASS\n");
    mpmcs_free(scb);
    return 0;
}

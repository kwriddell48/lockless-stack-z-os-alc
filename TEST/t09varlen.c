/* T09VARLEN - mixed payload sizes, LIFO, byte-for-byte match. */
#include "mpmcs.h"

static int fill_and_push(void *scb, unsigned char fill, uint32_t len)
{
    unsigned char *buf;
    int32_t rc;

    buf = (unsigned char *)mpmcs_alloc(len == 0 ? 1 : len);
    TEST_EXPECT(buf != NULL, "payload alloc");
    memset(buf, fill, len);
    rc = mpmcs_spush(scb, buf, len);
    mpmcs_free(buf);
    TEST_RC(rc, MPMCS_RC_OK, "push varlen");
    return 0;
}

static int pop_and_check(void *scb, unsigned char fill, uint32_t len)
{
    unsigned char *buf;
    uint32_t n = 0;
    uint32_t i;
    int32_t rc;

    buf = (unsigned char *)mpmcs_alloc(len + 8);
    TEST_EXPECT(buf != NULL, "pop buf alloc");
    memset(buf, 0x00, len + 8);
    rc = mpmcs_spop(scb, buf, len + 8, &n);
    if (rc != MPMCS_RC_OK) {
        mpmcs_free(buf);
        TEST_RC(rc, MPMCS_RC_OK, "pop varlen");
    }
    if (n != len) {
        mpmcs_free(buf);
        TEST_FAIL("pop length mismatch");
    }
    for (i = 0; i < len; i++) {
        if (buf[i] != fill) {
            mpmcs_free(buf);
            TEST_FAIL("payload byte mismatch");
        }
    }
    mpmcs_free(buf);
    return 0;
}

int main(void)
{
    void *scb;
    static const uint32_t lens[] = {1, 7, 64, 255, 4096};
    static const unsigned char fills[] = {0xA1, 0xB2, 0xC3, 0xD4, 0xE5};
    int i;
    int rc;

    printf("T09VARLEN start\n");
    fflush(stdout);

    scb = mpmcs_alloc_scb();
    TEST_EXPECT(scb != NULL, "SCB alloc failed");
    TEST_RC(mpmcs_sinit(scb, MPMCS_OPT_PAYLOAD31, 0, 0, 0),
            MPMCS_RC_OK, "SINIT");

    for (i = 0; i < 5; i++) {
        rc = fill_and_push(scb, fills[i], lens[i]);
        if (rc != 0)
            return rc;
    }
    for (i = 4; i >= 0; i--) {
        rc = pop_and_check(scb, fills[i], lens[i]);
        if (rc != 0)
            return rc;
    }

    TEST_RC(mpmcs_scbstop(scb), MPMCS_RC_OK, "SCBSTOP");
    printf("T09VARLEN PASS\n");
    mpmcs_free(scb);
    return 0;
}

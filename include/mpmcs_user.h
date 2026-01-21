/* MPMC stack user API header (C callers)
 *
 * This header is designed for z/OS C callers that can call AMODE 31 assembler
 * entry points using standard OS linkage.
 *
 * Entry points:
 *   SINIT, SPUSH, SPOP, SSTATS, SCBSTOP, GETVERSION
 *
 * Notes:
 *   - The SCB must be in 31-bit addressable storage (below the bar).
 *   - Return codes are delivered as the function return value (R15).
 *   - Terminology note: this project avoids certain words; use \"stack\" terms.
 */

#ifndef MPMCS_USER_H
#define MPMCS_USER_H

#include <stdint.h>
#include <stddef.h>

/* Options for SINIT */
#define MPMCS_OPT_PAYLOAD31 0x00000000u
#define MPMCS_OPT_PAYLOAD64 0x00000001u

/* Opaque SCB.
 * Allocate in below-the-bar storage. If you need the exact layout/size,
 * use the assembler include `user_api.inc` in an assembler module.
 */
typedef struct MpmcsScb MpmcsScb;

/* Stats snapshot layout returned by SSTATS.
 * This matches the `MPMCS_STATS` DSECT field order.
 * (Big-endian applies on z/OS; integers are still usable as numeric values.)
 */
typedef struct MpmcsStats {
    uint32_t version;
    uint32_t size;

    uint32_t push_ok;
    uint32_t pop_ok;
    uint32_t pop_empty;
    uint32_t push_alloc_fail;

    uint32_t push_retry;
    uint32_t pop_retry;
    uint32_t freelist_pop_retry;
    uint32_t freelist_push_retry;

    uint32_t depth_cur;
    uint32_t depth_max;

    uint64_t payload31_cur;
    uint64_t payload31_max;
    uint64_t payload64_cur;
    uint64_t payload64_max;

    uint32_t post_internal;
    uint32_t post_userecb;
    uint32_t cb_calls;
    uint32_t cb_pending_max;
} MpmcsStats;

/* Callback called by the optional notifier TCB:
 *   (cb_ctx, scb, pending_count)
 */
typedef void (*MpmcsCallback)(void* cb_ctx, void* scb, uint32_t pending_count);

/* Public entry points */
int32_t SINIT(void* scb, uint32_t options, void* cb_ep, void* cb_ctx, void* user_ecb);
int32_t SPUSH(void* scb, const void* src, uint32_t src_len);
int32_t SPOP(void* scb, void* dst, uint32_t dst_max_len, uint32_t* out_len);
int32_t SSTATS(void* scb, void* out_stats, uint32_t out_stats_len);
int32_t SCBSTOP(void* scb);

/* GETVERSION:
 * - If out_addr == NULL: returns 0, and sets (R1=ptr, R0=len) in assembler terms.
 *   From C, prefer passing a buffer.
 * - If out_addr != NULL: copies up to out_max_len and optionally stores the full
 *   length at *out_act_len, returning 0 (fit) or 8 (truncated).
 */
int32_t GETVERSION(char* out_addr, uint32_t out_max_len, uint32_t* out_act_len);

/* -------------------- C-style usage examples -------------------- */
/*
Example: initialize + push + pop

    // Allocate scb below the bar using your site standard (example placeholder):
    // void* scb = getmain_below(SCB_SIZE_FROM_ASM_INCLUDE);

    void* scb = ...; // below-the-bar storage, zeroed or not (SINIT initializes fields)

    // Optional callback/notifier:
    MpmcsCallback cb = NULL;
    void* cb_ctx = NULL;
    void* user_ecb = NULL; // pointer to an ECB fullword, or NULL

    int32_t rc = SINIT(scb, MPMCS_OPT_PAYLOAD64, (void*)cb, cb_ctx, user_ecb);
    if (rc != 0) { /* handle */ }

    const char msg[] = "hello";
    rc = SPUSH(scb, msg, (uint32_t)sizeof(msg));
    if (rc != 0) { /* handle */ }

    char out[64];
    uint32_t actual = 0;
    rc = SPOP(scb, out, (uint32_t)sizeof(out), &actual);
    if (rc == 4) {
        /* empty */
    } else if (rc == 8) {
        /* truncated; actual has full length */
    } else if (rc == 0) {
        /* success; actual is length */
    }

Example: stats snapshot

    MpmcsStats st;
    rc = SSTATS(scb, &st, (uint32_t)sizeof(st));
    if (rc == 0 && st.version == 1) {
        /* read counters */
    }
*/

#endif /* MPMCS_USER_H */


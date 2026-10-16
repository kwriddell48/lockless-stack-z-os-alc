         TITLE 'MPMC stack DSECTs - SCB, NODE, STATS, PARM LISTS'
***********************************************************************
*  MPMC stack DSECT INCLUDE
*
*  - AMODE 31 callable stack control block (SCB) + node layout
*  - Stats snapshot layout returned by SSTATS
*  - Parameter list layouts for entry points
*
*  Notes:
*  - Counted pointers used with CDS require doubleword alignment.
*  - This include is intended for HLASM.
***********************************************************************

MPMCS_EQUATES          EQU   *
MPMCS_STATS_VERSION    EQU   1

***********************************************************************
* SINIT option bits (SINIT_OPTIONS fullword)
*
*  Layout (big-endian fullword) — chosen so fields do not overlap:
*    bits 0-15  (high half): node prefill count (0 => MPMCS_NODE_PREFILL)
*    bit  31    (X'00000001'): MPMCS_OPT_PAYLOAD64
*
*  Why this layout:
*    - Hot path does NOT read OPTIONS; it tests SCB_FLAGS with TM (already
*      one instruction). Rearranging OPTIONS will not speed up SPUSH/SPOP.
*    - Count in the high half: extract with LLH (no SRL).
*    - Flag in the low bit: TM ...+3,X'01' or TMLL on a register copy.
*    - Stop uses X'80000000' in SCB_FLAGS (high bit), so payload stays
*      at the opposite end of the word and never shares a TM byte with stop.
*
* Prefill avoids GETMAIN on the SPUSH warm path (nodes come from freelist).
***********************************************************************
MPMCS_OPT_PAYLOAD31    EQU   X'00000000'  * default: payload allocated below 2G (GETMAIN BELOW)
MPMCS_OPT_PAYLOAD64    EQU   X'00000001'  * payload allocated in 64-bit storage (IARV64)

* Performance defaults (override node count via OPTIONS high half)
MPMCS_NODE_PREFILL     EQU   64           * nodes GETMAINed onto freelist at SINIT
MPMCS_WORK_PREFILL     EQU   16           * work cells onto SCB work pool at SINIT
MPMCS_WORK_CELL        EQU   512          * fixed work-cell size (SA+spills+IARV MF)

***********************************************************************
* Stack Control Block (SCB)
***********************************************************************
MPMCS_SCB              DSECT
SCB_EYECATCH           DS    CL8               'MPMCSTK '
SCB_NAME               DS    CL16              user-assigned stack name
SCB_VERSION            DS    F                 version
SCB_FLAGS              DS    F                 runtime flags

* Ensure counted pointers are doubleword aligned for CDS.
SCB_ALIGN0             DS    0D

* Tagged pointer: (ABA32, PTR31)
* ABA is a monotonic tag used to reduce ABA effects when pointers are updated.
SCB_TOP_ABA            DS    F                 ABA tag
SCB_TOP_PTR            DS    F                 ptr to top node (31-bit)

* Optional node freelist head (tagged pointer)
SCB_FREE_ABA           DS    F                 ABA tag
SCB_FREE_PTR           DS    F                 ptr to free node

* Work-cell freelist (fixed-size SA/spill blocks) — avoids GETMAIN on SPUSH/SPOP
SCB_WORK_ABA           DS    F                 ABA tag
SCB_WORK_PTR           DS    F                 ptr to free work cell

* Async callback fields
SCB_CB_EP              DS    F                 callback entry point (AMODE 31)
SCB_CB_CTX             DS    F                 user context pointer (31-bit)
SCB_USER_ECB           DS    F                 optional user ECB to POST per PUSH

* Internal notifier support
SCB_CB_ECB             DS    F                 internal ECB (fullword)
SCB_STOP_ECB           DS    F                 posted by MPMCS_NOTIF's NOTIF_DONE
*                                               once the subtask has fully
*                                               finished cleanup; SCBSTOP WAITs
*                                               on this before returning so the
*                                               caller cannot free/reuse the SCB
*                                               while the subtask is still
*                                               referencing it.
SCB_PUSH_SEQ           DS    F                 push sequence (monotonic)
SCB_CB_SEQ_SEEN        DS    F                 last processed by notifier
SCB_CB_TCB             DS    F                 notifier TCB addr (optional)
SCB_ABA_SEQ            DS    F                 unused (retained for layout/compat —
*                                               see mpmcq.asm/mpmcq_freelist.asm
*                                               header comments: ABA tags are
*                                               now minted per-field as old+1)

***********************************************************************
* Stats (kept in SCB; returned via SSTATS)
***********************************************************************
SCB_STAT_ALIGN         DS    0D

SCB_STAT_PUSH_OK       DS    F                 unused (retained for layout/compat —
*                                               see mpmcq_stats.asm: STATS_PUSH_OK
*                                               is now sourced from SCB_PUSH_SEQ)
SCB_STAT_POP_OK        DS    F
SCB_STAT_POP_EMPTY     DS    F
SCB_STAT_PUSH_ALLOC_FAIL DS  F

SCB_STAT_PUSH_RETRY    DS    F
SCB_STAT_POP_RETRY     DS    F
SCB_STAT_FREELIST_POP_RETRY DS F
SCB_STAT_FREELIST_PUSH_RETRY DS F

SCB_STAT_DEPTH_CUR     DS    F                 best-effort
SCB_STAT_DEPTH_MAX     DS    F

* Payload byte usage (doubleword, updated via CDS loops)
* - PAYLOAD31_*: bytes allocated below 2G (GETMAIN BELOW)
* - PAYLOAD64_*: bytes allocated in 64-bit virtual storage (IARV64)
SCB_STAT_PAYLOAD31_CUR_HI DS  F
SCB_STAT_PAYLOAD31_CUR_LO DS  F
SCB_STAT_PAYLOAD31_MAX_HI DS  F
SCB_STAT_PAYLOAD31_MAX_LO DS  F

SCB_STAT_PAYLOAD64_CUR_HI DS  F
SCB_STAT_PAYLOAD64_CUR_LO DS  F
SCB_STAT_PAYLOAD64_MAX_HI DS  F
SCB_STAT_PAYLOAD64_MAX_LO DS  F

SCB_STAT_POST_INTERNAL DS   F
SCB_STAT_POST_USERECB  DS   F
SCB_STAT_CB_CALLS      DS   F
SCB_STAT_CB_PENDING_MAX DS  F

SCB_SIZE               EQU   *-MPMCS_SCB

***********************************************************************
* Node layout (31-bit storage)
***********************************************************************
MPMCQ_NODE             DSECT
NODE_ALIGN0            DS    0D

* Node reference counters (doubleword so we can update atomically with CDS)
NODE_CNT_INT           DS    F                 internal count
NODE_CNT_EXT           DS    F                 external counters

* Tagged pointer to next node (ABA, PTR)
NODE_NEXT_ABA          DS    F
NODE_NEXT_PTR          DS    F                 ptr31

* Payload in 64-bit storage (address + length)
NODE_PAYLOAD64         DS    D                 64-bit address
NODE_PAYLOAD_LEN       DS    F                 length (bytes)
NODE_RSVD              DS    F                 reserved / align

NODE_SIZE              EQU   *-MPMCQ_NODE

***********************************************************************
* SSTATS snapshot layout (caller buffer)
***********************************************************************
MPMCS_STATS             DSECT
STATS_VERSION           DS   F
STATS_SIZE              DS   F                 bytes copied

STATS_PUSH_OK           DS   F
STATS_POP_OK            DS   F
STATS_POP_EMPTY          DS   F
STATS_PUSH_ALLOC_FAIL   DS   F

STATS_PUSH_RETRY        DS   F
STATS_POP_RETRY         DS   F
STATS_FREELIST_POP_RETRY DS  F
STATS_FREELIST_PUSH_RETRY DS F

STATS_DEPTH_CUR         DS   F
STATS_DEPTH_MAX         DS   F

STATS_PAYLOAD31_CUR     DS   D
STATS_PAYLOAD31_MAX     DS   D

STATS_PAYLOAD64_CUR     DS   D
STATS_PAYLOAD64_MAX     DS   D

STATS_POST_INTERNAL     DS   F
STATS_POST_USERECB      DS   F
STATS_CB_CALLS          DS   F
STATS_CB_PENDING_MAX    DS   F

STATS_RSVD              DS   0D
STATS_END               EQU  *

***********************************************************************
* Parameter lists (R1 -> parm list)
***********************************************************************

* SINIT(SCBaddr, options, CB_EP, CB_CTX, USER_ECB)
MPMCS_SINIT_PLIST       DSECT
SINIT_SCBADDR           DS   F
SINIT_OPTIONS           DS   F
SINIT_CB_EP             DS   F
SINIT_CB_CTX            DS   F
SINIT_USER_ECB          DS   F

* SPUSH(SCBaddr, srcAddr, srcLen)
MPMCS_SPUSH_PLIST       DSECT
SPU_SCBADDR             DS   F
SPU_SRCADDR             DS   F
SPU_SRCLEN              DS   F

* SPOP(SCBaddr, dstAddr, dstMaxLen, outLenAddr)
MPMCS_SPOP_PLIST        DSECT
SPO_SCBADDR             DS   F
SPO_DSTADDR             DS   F
SPO_DSTMAX              DS   F
SPO_OUTLENADDR          DS   F

* SSTATS(SCBaddr, outStatsAddr, outStatsLen)
MPMCS_SSTATS_PLIST      DSECT
SST_SCBADDR             DS   F
SST_OUTADDR             DS   F
SST_OUTLEN              DS   F

* GETVERSION(outAddr, outMaxLen, outActLenAddr)
* - If outAddr==0, routine returns R1=ptr to version string, R0=len.
* - If outAddr!=0, routine copies up to outMaxLen and stores actual length
*   (full string length) at *outActLenAddr.
MPMCS_GETVER_PLIST      DSECT
GVER_OUTADDR            DS   F
GVER_OUTMAX             DS   F
GVER_OUTACTLENADDR      DS   F

* Callback parm list: (CB_CTX, SCBaddr, PendingCount)
MPMCQ_CB_PLIST          DSECT
CBP_CTX                 DS   F
CBP_SCB                 DS   F
CBP_PENDING             DS   F

         END

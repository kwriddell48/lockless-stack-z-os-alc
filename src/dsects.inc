         TITLE 'MPMC stack DSECTs - SCB, NODE, STATS, PARM LISTS'
***********************************************************************
*  DSECTS
*
*  - AMODE 31 callable stack control block (SCB) + node layout
*  - Stats snapshot layout returned by SSTATS
*  - Parameter list layouts for entry points
*
*  Notes:
*  - Counted pointers used with CDS require doubleword alignment.
*    The caller SCB base must itself be 0D-aligned; SINIT returns
*    RC=8 if bits 29-31 of the address are not zero.
*  - SPUSH copies with one MVCL (max X'FFFFFF'). Longer srcLen is
*    rejected (RC=8). 32-bit ABA tags wrap; residual Treiber ABA
*    after 2^32 swings of a given head is accepted.
*  - CDS on TOP/FREE/WORK is lock-free. STORAGE, IARV64, POST,
*    WAIT, and ATTACH can block. This include is for HLASM.
***********************************************************************
MPMCS_EQUATES          EQU   *
MPMCS_STATS_VERSION    EQU   1
***********************************************************************
* SINIT option bits (SINIT_OPTIONS fullword)
*
*  Layout (big-endian fullword) so fields do not overlap:
*    bits 0-15  (high half): node prefill count
*               (0 => MPMCS_NODE_PREFILL)
*    bit  31    (X'00000001'): MPMCS_OPT_PAYLOAD64
***********************************************************************
* default: payload allocated below 2G (STORAGE OBTAIN LOC=ANY)
MPMCS_OPT_PAYLOAD31    EQU   X'00000000'
* payload allocated in 64-bit storage (IARV64)
MPMCS_OPT_PAYLOAD64    EQU   X'00000001'
* SINIT: obtain ring and set TRC_MASK=TRC_ALL
MPMCS_OPT_TRACE        EQU   X'00000002'
* Performance defaults (override node count via OPTIONS high half)
* nodes obtained onto freelist at SINIT
MPMCS_NODE_PREFILL     EQU   64
* work cells onto SCB work pool at SINIT
MPMCS_WORK_PREFILL     EQU   16
* fixed work-cell size (SA+spills+IARV MF)
MPMCS_WORK_CELL        EQU   512
* inline payload buffer size per node (bypasses STORAGE OBTAIN/RELEASE)
NODE_INLINE_MAX        EQU   256
* one MVCL; SPUSH rejects srcLen above this (RC=8)
MPMCS_MAX_COPY         EQU   X'00FFFFFF'
* Subpool for nodes, work cells, 31-bit payloads, and the ring.
* Unauthorized LE/C can only use SP 0-127 (SP 131/132 => SB78-08).
* SP=0 is TCB-owned: a worker that STORAGE OBTAINs a >inline
* payload must not exit before that record is popped. Prefill at
* SINIT (mother TCB) keeps freelist nodes job-lived for workers
* that only swing existing cells. APF + SP=132 is the upgrade
* path for worker-owned external payloads.
MPMCS_STORSP           EQU   0
***********************************************************************
* Stack Control Block (SCB)
***********************************************************************
MPMCS_SCB              DSECT
SCB_EYECATCH           DS    CL8               'MPMCSTK '
SCB_NAME               DS    CL16              user stack name
SCB_VERSION            DS    F                 version
SCB_FLAGS              DS    F                 runtime flags
* Ensure counted pointers are doubleword aligned for CDS.
SCB_ALIGN0             DS    0D
* Tagged pointer: (ABA32, PTR31)
SCB_TOP_ABA            DS    F                 ABA tag
SCB_TOP_PTR            DS    F                 ptr to top node
* Optional node freelist head (tagged pointer)
SCB_FREE_ABA           DS    F                 ABA tag
SCB_FREE_PTR           DS    F                 ptr to free node
* Work-cell freelist (fixed-size SA/spill blocks).
SCB_WORK_ABA           DS    F                 ABA tag
SCB_WORK_PTR           DS    F                 ptr to free work cell
* Async callback fields
SCB_CB_EP              DS    F
SCB_CB_CTX             DS    F
SCB_USER_ECB           DS    F
* Internal notifier support
SCB_CB_ECB             DS    F                 internal ECB
SCB_STOP_ECB           DS    F
SCB_PUSH_SEQ           DS    F                 push sequence
SCB_CB_SEQ_SEEN        DS    F
SCB_CB_TCB             DS    F
SCB_ABA_SEQ            DS    F
SCB_STAT_PAD           DS    F
***********************************************************************
* Stats (kept in SCB; returned via SSTATS)
***********************************************************************
SCB_STAT_ALIGN         DS    0D
SCB_STAT_PUSH_OK       DS    F
SCB_STAT_POP_OK        DS    F
SCB_STAT_POP_EMPTY     DS    F
SCB_STAT_PUSH_ALLOC_FAIL DS  F
SCB_STAT_PUSH_RETRY    DS    F
SCB_STAT_POP_RETRY     DS    F
SCB_STAT_FREELIST_POP_RETRY DS F
SCB_STAT_FREELIST_PUSH_RETRY DS F
SCB_STAT_DEPTH_CUR     DS    F                 best-effort
SCB_STAT_DEPTH_MAX     DS    F
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
STCLR                  EQU   *-SCB_STAT_PUSH_OK
* Trace control on the next cache line (offset 256), not with TOP.
         ORG   MPMCS_SCB+256
SCB_TRC_MASK           DS    F                 class bits (low byte)
SCB_TRC_BASE           DS    F                 ring address (31-bit)
SCB_TRC_N              DS    F                 slot count (power of 2)
SCB_TRC_NMSK           DS    F                 N-1
SCB_TRC_NEXT           DS    F                 LAAL slot index
SCB_TRC_LOST           DS    F
SCB_SIZE               EQU   *-MPMCS_SCB
***********************************************************************
* Node layout (31-bit storage, with 256B inline payload fast-path)
***********************************************************************
MPMCQ_NODE             DSECT
NODE_ALIGN0            DS    0D
NODE_CNT_INT           DS    F                 internal count
NODE_CNT_EXT           DS    F                 external counters
NODE_NEXT_ABA          DS    F
NODE_NEXT_PTR          DS    F                 ptr31
NODE_PAYLOAD64         DS    D                 64-bit address
NODE_PAYLOAD_LEN       DS    F                 length (bytes)
NODE_RSVD              DS    F                 flags (1 = inline buf)
NODE_HDR_SIZE          EQU   *-MPMCQ_NODE
NODE_INLINE            DS    CL(NODE_INLINE_MAX)
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
MPMCS_SINIT_PLIST       DSECT
SINIT_SCBADDR           DS   F
SINIT_OPTIONS           DS   F
SINIT_CB_EP             DS   F
SINIT_CB_CTX            DS   F
SINIT_USER_ECB          DS   F

MPMCS_SPUSH_PLIST       DSECT
SPU_SCBADDR             DS   F
SPU_SRCADDR             DS   F
SPU_SRCLEN              DS   F

MPMCS_SPOP_PLIST        DSECT
SPO_SCBADDR             DS   F
SPO_DSTADDR             DS   F
SPO_DSTMAX              DS   F
SPO_OUTLENADDR          DS   F

MPMCS_SSTATS_PLIST      DSECT
SST_SCBADDR             DS   F
SST_OUTADDR             DS   F
SST_OUTLEN              DS   F

MPMCS_GETVER_PLIST      DSECT
GVER_OUTADDR            DS   F
GVER_OUTMAX             DS   F
GVER_OUTACTLENADDR      DS   F

MPMCQ_CB_PLIST          DSECT
CBP_CTX                 DS   F
CBP_SCB                 DS   F
CBP_PENDING             DS   F

MPMCS_STRACE_PLIST      DSECT
STR_SCBADDR             DS   F
STR_OUTADDR             DS   F
STR_OUTLEN              DS   F

MPMCS_STRSET_PLIST      DSECT
STRS_SCBADDR            DS   F
STRS_MASK               DS   F

***********************************************************************
* Flight-recorder ring (31-bit STORAGE, not in the SCB)
***********************************************************************
MPMCS_TRC_SLOTS        EQU   256
MPMCS_TRC_SLOT         EQU   32
MPMCS_TRC_BYTES        EQU   MPMCS_TRC_SLOTS*MPMCS_TRC_SLOT
TRC_API                EQU   X'01'
TRC_CDS                EQU   X'02'
TRC_NTF                EQU   X'04'
TRC_ALC                EQU   X'08'
TRC_ALL                EQU   X'0F'
TRE_SINIT              EQU   1
TRE_SINITX             EQU   2
TRE_SPUSH              EQU   3
TRE_SPUSHX             EQU   4
TRE_SPOP               EQU   5
TRE_SPOPX              EQU   6
TRE_SSTOP              EQU   7
TRE_SSTOPX             EQU   8
TRE_CDSOK              EQU   9
TRE_CDSRET             EQU   10
TRE_POSTI              EQU   11
TRE_POSTU              EQU   12
TRE_WAIT               EQU   13
TRE_CB                 EQU   14
TRE_STOP               EQU   15
TRE_DETACH             EQU   16
TRE_NGET               EQU   17
TRE_INLINE             EQU   18
TRE_OB31               EQU   19
TRE_PAYOK              EQU   20
TRE_PAYFAIL            EQU   21
TRH_TOP                EQU   1
TRH_FREE               EQU   2
TRH_WORK               EQU   3

MPMCS_TRC_HDR           DSECT
TH_NEXT                 DS   F
TH_N                    DS   F
TH_MASK                 DS   F
TH_SLOT                 DS   F
TH_HDRLEN               EQU   *-MPMCS_TRC_HDR

MPMCQ_TRSLOT            DSECT
TR_TOD                  DS   D
TR_CLASS                DS   X
TR_EVENT                DS   X
TR_CPU                  DS   H
TR_SCB                  DS   F
TR_A                    DS   F
TR_B                    DS   F
TR_C                    DS   F
TR_RSVD                 DS   F
TR_LEN                  EQU   *-MPMCQ_TRSLOT
*         END OF DSECTS

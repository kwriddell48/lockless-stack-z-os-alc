         TITLE 'MPMC stack - Storage helpers (IARV64 payload)'
***********************************************************************
*  MPMCQ_STORAGE.ASM
*
*  64-bit payload allocation/free when SINIT selected MPMCS_OPT_PAYLOAD64.
*
*  Performance: these are LEAF routines. They reuse the caller's work cell
*  (R13) at WK_IARV for the IARV64 MF=E parameter list — no GETMAIN here.
*
*  Caller must have entered via MPMCQ_ENTER_SCB (or equivalent) so that:
*    - R13 -> work cell with at least WK_IARV+WK_IARVMAX bytes
*    - a next save area is available for our STM
*
*  MPMCS_PAYGET  In: R7=len   Out: R15=0/8, R8=addr64
*  MPMCS_PAYFREE In: R8=addr64, R7=len  Out: R15=0
*
*  SHOP NOTE: IARV64 LENGTH units/policy are installation-specific.
***********************************************************************

         PRINT GEN
         OPTABLE ZOP

         COPY  'src/reg_equates.inc'
         COPY  'src/mpmcq_save.mac'

MPMCQSTO CSECT
MPMCQSTO AMODE 31
MPMCQSTO RMODE ANY

         ENTRY MPMCS_PAYGET
         ENTRY MPMCS_PAYFREE

         USING MPMCQSTO,R15

* Must match offsets in src/mpmcq.asm work-cell layout.
WK_IARV    EQU   128
WK_IARVMAX EQU   256

GET64_TEMPL  DS  0D
         IARV64 MF=L
GET64_TLEN   EQU *-GET64_TEMPL

FREE64_TEMPL DS  0D
         IARV64 MF=L
FREE64_TLEN  EQU *-FREE64_TEMPL

* WK_IARVMAX in mpmcq.asm must be >= max(GET64_TLEN,FREE64_TLEN).

***********************************************************************
* MPMCS_PAYGET
***********************************************************************
MPMCS_PAYGET DS 0H
         STM   R14,R12,12(R13)
         LR    R12,R15
         USING MPMCQSTO,12

         LTR   R7,R7
         JNZ   PAYGET_DO
         XR    R8,R8
         XR    R15,R15
         MPMCQ_LEAF_RETURN_R8 R15

PAYGET_DO DS 0H
* Build MF=E list in caller's work cell (no GETMAIN).
         MVC   WK_IARV(GET64_TLEN,R13),GET64_TEMPL
         LA    R1,WK_IARV(R13)
         IARV64 REQUEST=GETSTOR,COND=YES,LENGTH=(R7),ORIGIN=(R8),MF=(E,(R1))
         LTR   R15,R15
         JZ    PAYGET_OK
         LA    R15,8
         MPMCQ_LEAF_RETURN R15

PAYGET_OK DS 0H
         XR    R15,R15
         MPMCQ_LEAF_RETURN_R8 R15

***********************************************************************
* MPMCS_PAYFREE
***********************************************************************
MPMCS_PAYFREE DS 0H
         STM   R14,R12,12(R13)
         LR    R12,R15
         USING MPMCQSTO,12

         LTR   R7,R7
         JZ    PAYFREE_DONE

         MVC   WK_IARV(FREE64_TLEN,R13),FREE64_TEMPL
         LA    R1,WK_IARV(R13)
         IARV64 REQUEST=FREESTOR,ORIGIN=(R8),LENGTH=(R7),MF=(E,(R1))

PAYFREE_DONE DS 0H
         XR    R15,R15
         MPMCQ_LEAF_RETURN R15

         END   MPMCQSTO

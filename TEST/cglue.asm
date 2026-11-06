         TITLE 'C OS-linkage stubs to HLASM plist entries'
***********************************************************************
*  CGLUE.ASM
*
*  Each stub is #pragma linkage(..., OS) with one argument: plist*.
*  LE C OS, 1 arg: R1 -> (addr of plist* | VL).
*  Load the plist into R1, set R15 to the HLASM ENTRY (V-con),
*  tail BR to the HLASM ENTRY (R15 = entry; R12 is LARL'd).
*
*  Do not pass assembler label addresses from C (LONGNAME space 3
*  + LET yields a 0 V-con and S0C1 at address 0).
***********************************************************************
         MACRO
         C1PLIST
.* OS 1-arg: R1 -> (addr of object | VL). One load yields the plist
.* (or void** for CTESTEP). A second load would pick up pl.outaddr
.* (the caller's zeroed buffer) and GETVERSION would take the
.* outAddr==0 path: RC=0, no length stored.
         L     1,0(,1)
         SRL   1,1
         SLL   1,1
         MEND
*
CGLUE    CSECT
CGLUE    AMODE 31
CGLUE    RMODE ANY
         ENTRY CSINIT,CSPUSH,CSPOP,CSSTATS,CSCBSTP,CGETVER
         ENTRY CTESTEP,CS64ADD,CS64ADS,CS64MAX
         ENTRY CSTRACE,CSTRSET
*
CSINIT   DS    0H
         C1PLIST
         LARL  15,VSINIT
         L     15,0(,15)
         BR    15
CSPUSH   DS    0H
         C1PLIST
         LARL  15,VSPUSH
         L     15,0(,15)
         BR    15
CSPOP    DS    0H
         C1PLIST
         LARL  15,VSPOP
         L     15,0(,15)
         BR    15
CSSTATS  DS    0H
         C1PLIST
         LARL  15,VSSTATS
         L     15,0(,15)
         BR    15
CSCBSTP  DS    0H
         C1PLIST
         LARL  15,VSCBSTP
         L     15,0(,15)
         BR    15
CGETVER  DS    0H
         C1PLIST
         LARL  15,VGETVER
         L     15,0(,15)
         BR    15
*
* CTESTEP(void **out)  store A(TESTCB) at *out
CTESTEP  DS    0H
         C1PLIST
         LARL  15,VTESTCB
         L     15,0(,15)
         ST    15,0(,1)
         XR    15,15
         BR    14
*
CS64ADD  DS    0H
         C1PLIST
         LARL  15,VS64ADD
         L     15,0(,15)
         BR    15
CS64ADS  DS    0H
         C1PLIST
         LARL  15,VS64ADS
         L     15,0(,15)
         BR    15
CS64MAX  DS    0H
         C1PLIST
         LARL  15,VS64MAX
         L     15,0(,15)
         BR    15
CSTRACE  DS    0H
         C1PLIST
         LARL  15,VSTRACE
         L     15,0(,15)
         BR    15
CSTRSET  DS    0H
         C1PLIST
         LARL  15,VSTRSET
         L     15,0(,15)
         BR    15
*
         DS    0F
VSINIT   DC    V(SINIT)
VSPUSH   DC    V(SPUSH)
VSPOP    DC    V(SPOP)
VSSTATS  DC    V(SSTATS)
VSCBSTP  DC    V(SCBSTOP)
VGETVER  DC    V(GETVERSION)
VTESTCB  DC    V(TESTCB)
VS64ADD  DC    V(S64ADD)
VS64ADS  DC    V(S64ADDS)
VS64MAX  DC    V(S64MAX)
VSTRACE  DC    V(STRACE)
VSTRSET  DC    V(STRACESET)
         END   CGLUE

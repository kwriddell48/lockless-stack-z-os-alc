         TITLE 'MPMC stack - GETVERSION (product build/version string)'
***********************************************************************
*  MPMCQ_VERSION.ASM
*
*  GETVERSION — return an assemble-time stamped build/version string.
*
*  Timestamping:
*    &SYSDATE / &SYSTIME are expanded by HLASM when this module is
*    assembled, not at runtime.
*
*  Calling (R1 -> MPMCQ_GETVER_PLIST):
*    outAddr       - 31-bit buffer address, or 0
*    outMaxLen     - max bytes to copy when outAddr != 0
*    outActLenAddr - optional fullword to receive the FULL string length
*
*  Behavior:
*    outAddr == 0:
*      R1 = address of internal constant string
*      R0 = length
*      R15 = 0
*    outAddr != 0:
*      copies min(outMaxLen, VER_LEN) bytes
*      stores VER_LEN at *outActLenAddr if provided
*      R15 = 0 if not truncated, 8 if truncated
*
*  RENT: version string is a constant; no writable static used.
***********************************************************************

         PRINT GEN
         OPTABLE ZOP

         COPY  'src/reg_equates.inc'
         COPY  'src/mpmcq_dsects.inc'
         COPY  'src/mpmcq_save.mac'

MPMCQVER CSECT
MPMCQVER AMODE 31
MPMCQVER RMODE ANY

         ENTRY GETVERSION
         USING MPMCQVER,R15

* Assemble-time stamped product string (immutable).
VER_STR  DC    C'MPMC stack build &SYSDATE &SYSTIME'
VER_END  DS    0C
VER_LEN  EQU   VER_END-VER_STR

GV_WLEN  EQU   72                          save area only

***********************************************************************
* GETVERSION(outAddr, outMaxLen, outActLenAddr)
***********************************************************************
GETVERSION DS 0H
         MPMCQ_ENTER GV_WLEN
         USING MPMCQVER,12

         LT    R3,GVER_OUTADDR(R1)         load+test; 0 => return string ptr
         L     R4,GVER_OUTMAX(R1)

* Pointer-only request: return internal address/length in R1/R0.
         JNZ   GV_DO_COPY
         LA    R1,VER_STR
         LA    R0,VER_LEN
         XR    R15,R15
         MPMCQ_RETURN_R01 R15,GV_WLEN      preserves R0/R1/R15 across LM

GV_DO_COPY DS 0H
* Always report the full logical length when the caller provided a slot.
         LT    R5,GVER_OUTACTLENADDR(R1)
         JZ    GV_LEN_DONE
         LA    R0,VER_LEN
         ST    R0,0(R5)
GV_LEN_DONE DS 0H

* copyLen = min(outMaxLen, VER_LEN); RC=8 if truncated.
         LA    R0,VER_LEN
         LR    R6,R0
         CR    R4,R6
         JNL   GV_FITS
         LR    R6,R4                       truncated copy length
         LA    R7,8                        RC=truncated
         J     GV_HAVE_LEN
GV_FITS  DS 0H
         XR    R7,R7                       RC=0
GV_HAVE_LEN DS 0H

* MVCL with equal dest/src lengths avoids zero-padding.
         LR    R8,R3                       dest addr
         LR    R9,R6                       dest len
         LA    R10,VER_STR                 src addr
         LR    R11,R6                      src len
         MVCL  R8,R10

         LR    R15,R7                      restore RC after MVCL scratch
         MPMCQ_RETURN R15,GV_WLEN

         END   MPMCQVER

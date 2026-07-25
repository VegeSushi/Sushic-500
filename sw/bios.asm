; Sushic-500 BIOS & REPL (MC6847 Shared Memory Version)
VRAM_START = $0400 ; Screen memory base address mapped in hardware
KBD_DATA = $C002
KBD_STAT = $C003

CMDBUF = $00  
BUFPTR = $10  
CURSOR = $12  ; 16-bit pointer for current screen position

.segment "CODE"

SYS_CLEAR_VRAM: JMP DO_CLEAR_VRAM  ; $D000
SYS_PRINT_CHAR: JMP DO_PRINT_CHAR  ; $D003
SYS_READ_KEY:   JMP DO_READ_KEY    ; $D006

RESET:
    SEI
    CLD
    LDX #$FF
    TXS

    JSR DO_CLEAR_VRAM

    ; --- Print Boot Message ---
    LDX #0
PRINT_BOOT:
    LDA BOOT_MSG, X
    BEQ BOOT_DONE
    JSR DO_PRINT_CHAR
    INX
    JMP PRINT_BOOT

BOOT_DONE:
    ; Continue to REPL initialization

REPL_INIT:
    LDA #0
    STA BUFPTR
    
    ; Print the input prompt
    LDA #'>'
    JSR DO_PRINT_CHAR

REPL_LOOP:
    JSR DO_READ_KEY     
    CMP #$0D            
    BEQ PARSE_CMD
    
    JSR DO_PRINT_CHAR
    LDX BUFPTR
    STA CMDBUF, X
    INC BUFPTR
    JMP REPL_LOOP

PARSE_CMD:
    LDX BUFPTR
    LDA #0
    STA CMDBUF, X

    LDA CMDBUF
    CMP #'C'
    BNE CMD_NOT_FOUND
    LDA CMDBUF+1
    CMP #'A'
    BNE CMD_NOT_FOUND
    LDA CMDBUF+2
    CMP #'R'
    BNE CMD_NOT_FOUND
    LDA CMDBUF+3
    CMP #'T'
    BNE CMD_NOT_FOUND

    JSR $8000
    JMP REPL_INIT

CMD_NOT_FOUND:
    LDA #' '
    JSR DO_PRINT_CHAR
    LDA #'?'
    JSR DO_PRINT_CHAR
    JMP REPL_INIT

DO_READ_KEY:
WaitKey:
    LDA KBD_STAT
    AND #$01
    BEQ WaitKey
    LDA KBD_DATA        
    PHA                 
WaitRelease:
    LDA KBD_STAT        
    AND #$01
    BNE WaitRelease
    PLA                 
    RTS

DO_PRINT_CHAR:
    ; Write character to (CURSOR) memory pointer
    LDY #0
    STA (CURSOR), Y
    
    ; Increment Cursor
    INC CURSOR
    BNE SkipIncHigh
    INC CURSOR+1
SkipIncHigh:
    RTS

DO_CLEAR_VRAM:
    LDA #$00
    STA CURSOR
    LDA #$04
    STA CURSOR+1
    LDA #$20        ; space
    LDX #0
ClearLoop1:
    STA $0400, X
    STA $0500, X
    INX
    BNE ClearLoop1
    RTS

; --- Boot Data ---
BOOT_MSG:
    .asciiz "SUSHIC-500 SHELL"

.segment "VECTORS"
.word 0000      ; NMI
.word RESET     ; RESET
.word 0000      ; IRQ
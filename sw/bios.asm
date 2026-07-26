; Sushic-500 BIOS & REPL (MC6847 Shared Memory Version)
VRAM_START = $0400     ; Screen memory base address mapped in hardware
KBD_DATA   = $C002
KBD_STAT   = $C003

CMDBUF = $00       ; 16 bytes reserved for command input ($00-$0F)
CURSOR = $12       ; 16-bit pointer for current screen position ($12-$13)
STRPTR = $14       ; 16-bit pointer used for printing strings ($14-$15)
TEMP_A = $16       ; Temporary storage to preserve A register

; --- New Zero Page Variables for Syscalls ---
INP_PTR = $17      ; 16-bit pointer for string input buffer
INP_MAX = $19      ; 1 byte: max length for string input
INP_LEN = $1A      ; 1 byte: current length of string input

.segment "CODE"

; --- Syscall Jump Table ---
SYS_CLEAR_VRAM: JMP DO_CLEAR_VRAM  ; $D000 - Clear VRAM
SYS_PRINT_CHAR: JMP DO_PRINT_CHAR  ; $D003 - Print char in A
SYS_READ_KEY:   JMP DO_READ_KEY    ; $D006 - Read single key to A
SYS_PRINT_STR:  JMP DO_PRINT_STR   ; $D009 - Print null-terminated string (A=Low, Y=High)
SYS_NEWLINE:    JMP DO_NEWLINE     ; $D00C - Advance cursor to next line
SYS_READ_STR:   JMP DO_READ_STR    ; $D00F - Read string to (A=Low, Y=High), max len in X
SYS_SET_CURSOR: JMP DO_SET_CURSOR  ; $D012 - Set cursor to X (col), Y (row)
SYS_PRINT_HEX:  JMP DO_PRINT_HEX   ; $D015 - Print A as 2-digit hex

RESET:
    SEI
    CLD
    LDX #$FF
    TXS

    JSR DO_CLEAR_VRAM

    ; --- Print Boot Message ---
    LDA #<BOOT_MSG
    LDY #>BOOT_MSG
    JSR DO_PRINT_STR
    JSR DO_NEWLINE

BOOT_DONE:
    ; Fallthrough to REPL initialization

REPL_INIT:
    ; Print the input prompt
    LDA #'>'
    JSR DO_PRINT_CHAR

    ; --- Use the new Read String Syscall ---
    LDA #<CMDBUF       ; Low byte of buffer
    LDY #>CMDBUF       ; High byte of buffer
    LDX #$0F           ; Max 15 characters
    JSR DO_READ_STR    ; Handles typing, echoing, backspace, and waits for Enter
    
    LDA CMDBUF         ; Check first char
    BEQ REPL_INIT      ; If empty command, just show prompt again
    JMP PARSE_CMD

PARSE_CMD:
    ; CHECK "CART"
    LDA CMDBUF
    CMP #'C'
    BNE CHECK_HELP
    LDA CMDBUF+1
    CMP #'A'
    BNE CHECK_HELP
    LDA CMDBUF+2
    CMP #'R'
    BNE CHECK_HELP
    LDA CMDBUF+3
    CMP #'T'
    BNE CHECK_HELP
    JSR $8000          ; Execute cartridge
    JSR DO_NEWLINE
    JMP REPL_INIT

CHECK_HELP:
    ; CHECK "HELP"
    LDA CMDBUF
    CMP #'H'
    BNE CHECK_CLS
    LDA CMDBUF+1
    CMP #'E'
    BNE CHECK_CLS
    LDA CMDBUF+2
    CMP #'L'
    BNE CHECK_CLS
    LDA CMDBUF+3
    CMP #'P'
    BNE CHECK_CLS
    LDA #<HELP_MSG
    LDY #>HELP_MSG
    JSR DO_PRINT_STR
    JSR DO_NEWLINE
    JMP REPL_INIT

CHECK_CLS:
    ; CHECK "CLS"
    LDA CMDBUF
    CMP #'C'
    BNE CMD_NOT_FOUND
    LDA CMDBUF+1
    CMP #'L'
    BNE CMD_NOT_FOUND
    LDA CMDBUF+2
    CMP #'S'
    BNE CMD_NOT_FOUND
    JSR DO_CLEAR_VRAM
    JMP REPL_INIT

CMD_NOT_FOUND:
    ; --- Incorrect Command Execution ---
    LDA #'?'
    JSR DO_PRINT_CHAR
    JSR DO_NEWLINE     ; New line after error indicator
    JMP REPL_INIT

; ---------------------------------------------------------
; SYSCALL: Read a full string into memory (handles backspace)
; In: A = Buffer Low, Y = Buffer High, X = Max length
; ---------------------------------------------------------
DO_READ_STR:
    STA INP_PTR
    STY INP_PTR+1
    STX INP_MAX
    LDA #0
    STA INP_LEN
_ReadLoop:
    JSR DO_READ_KEY
    CMP #$0D           ; Enter key
    BEQ _ReadEnter
    CMP #$08           ; Backspace key
    BEQ _ReadBackspace

    ; Check limit
    LDX INP_LEN
    CPX INP_MAX
    BCS _ReadLoop      ; If at max length, ignore key

    ; Store and echo character
    JSR DO_PRINT_CHAR
    LDY INP_LEN
    STA (INP_PTR), Y
    INC INP_LEN
    JMP _ReadLoop

_ReadBackspace:
    LDA INP_LEN
    BEQ _ReadLoop      ; Nothing to delete, ignore

    DEC INP_LEN

    ; Step cursor back one cell
    LDA CURSOR
    BNE _SkipDec1
    DEC CURSOR+1
_SkipDec1:
    DEC CURSOR

    LDA #' '
    JSR DO_PRINT_CHAR  ; Overwrite the glyph with a space (moves cursor right)

    ; Step cursor back again to sit on the blank cell
    LDA CURSOR
    BNE _SkipDec2
    DEC CURSOR+1
_SkipDec2:
    DEC CURSOR
    JMP _ReadLoop

_ReadEnter:
    JSR DO_NEWLINE
    LDY INP_LEN
    LDA #0             ; Null-terminate the string
    STA (INP_PTR), Y
    RTS

; ---------------------------------------------------------
; SYSCALL: Set Cursor position
; In: X = Column (0-31), Y = Row (0-15)
; ---------------------------------------------------------
DO_SET_CURSOR:
    PHA
    LDA #$00
    STA CURSOR
    LDA #$04           ; VRAM base high byte ($0400)
    STA CURSOR+1
_SetCurYLoop:
    CPY #0
    BEQ _SetCurAddX
    ; Add 32 (one row) to CURSOR
    LDA CURSOR
    CLC
    ADC #32
    STA CURSOR
    BCC _SkipIncY
    INC CURSOR+1
_SkipIncY:
    DEY
    JMP _SetCurYLoop
_SetCurAddX:
    TXA
    CLC
    ADC CURSOR
    STA CURSOR
    BCC _SkipIncX
    INC CURSOR+1
_SkipIncX:
    PLA
    RTS

; ---------------------------------------------------------
; SYSCALL: Print Accumulator as 2-digit Hexadecimal
; ---------------------------------------------------------
DO_PRINT_HEX:
    PHA                ; Save original A
    LSR                ; Shift top 4 bits down
    LSR 
    LSR 
    LSR 
    JSR _PrintNybble   ; Print high nybble
    PLA                ; Restore A
    PHA                ; Save again for caller
    AND #$0F           ; Isolate bottom 4 bits
    JSR _PrintNybble   ; Print low nybble
    PLA                ; Restore original A
    RTS
_PrintNybble:
    CMP #10
    BMI _IsDigit
    CLC
    ADC #7             ; Shift up to ASCII 'A'-'F'
_IsDigit:
    ADC #'0'
    JMP DO_PRINT_CHAR  ; Print and return

; ---------------------------------------------------------
; Legacy / Core IO Routines
; ---------------------------------------------------------
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

DO_PRINT_STR:
    STA STRPTR
    STY STRPTR+1
    LDY #0
StrLoop:
    LDA (STRPTR), Y
    BEQ StrDone
    JSR DO_PRINT_CHAR
    INY
    BNE StrLoop
StrDone:
    RTS

DO_PRINT_CHAR:
    ; --- BIOS Prologue: Save Registers ---
    STA TEMP_A
    TYA
    PHA
    TXA
    PHA
    ; -------------------------------------
    LDA TEMP_A
    CMP #$0D
    BEQ _DoNewline

    ; Write character to (CURSOR) memory pointer
    LDY #0
    STA (CURSOR), Y
    
    ; Increment Cursor
    INC CURSOR
    BNE _SkipIncHigh
    INC CURSOR+1
_SkipIncHigh:
    ; Check if we exceeded VRAM ($0600)
    LDA CURSOR+1
    CMP #$06
    BCC _PrintDone
    JSR DO_SCROLL_UP
    JMP _PrintDone

_DoNewline:
    JSR DO_NEWLINE

_PrintDone:
    ; --- BIOS Epilogue: Restore Registers ---
    PLA
    TAX
    PLA
    TAY
    LDA TEMP_A
    ; ----------------------------------------
    RTS

DO_NEWLINE:
    LDA CURSOR
    AND #$E0
    CLC
    ADC #$20
    STA CURSOR
    BCC CheckScroll
    INC CURSOR+1
CheckScroll:
    LDA CURSOR+1
    CMP #$06
    BCC NewlineDone
    JSR DO_SCROLL_UP
NewlineDone:
    RTS

DO_SCROLL_UP:
    LDX #0
Scrl1:
    LDA $0420, X
    STA $0400, X
    INX
    BNE Scrl1
Scrl2:
    LDA $0520, X
    STA $0500, X
    INX
    CPX #$E0
    BNE Scrl2

    LDA #$20
    LDX #0
ClearLast:
    STA $05E0, X
    INX
    CPX #$20
    BNE ClearLast

    LDA #$E0
    STA CURSOR
    LDA #$05
    STA CURSOR+1
    RTS

DO_CLEAR_VRAM:
    LDA #$00
    STA CURSOR
    LDA #$04
    STA CURSOR+1
    LDA #$20
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
HELP_MSG:
    .asciiz "CMDS: CART CLS HELP"

.segment "VECTORS"
.word 0000      ; NMI
.word RESET     ; RESET
.word 0000      ; IRQ
; Sushic-500 BIOS & REPL (MC6847 Shared Memory Version)
VRAM_START = $0400     ; Screen memory base address mapped in hardware
KBD_DATA   = $C002
KBD_STAT   = $C003

CMDBUF = $00       ; 16 bytes reserved for command input ($00-$0F)
BUFPTR = $10       ; 1 byte
CURSOR = $12       ; 16-bit pointer for current screen position ($12-$13)
STRPTR = $14       ; 16-bit pointer used for printing strings ($14-$15)
TEMP_A = $16       ; Temporary storage to preserve A register

.segment "CODE"

; --- Syscall Jump Table ---
SYS_CLEAR_VRAM: JMP DO_CLEAR_VRAM  ; $D000
SYS_PRINT_CHAR: JMP DO_PRINT_CHAR  ; $D003
SYS_READ_KEY:   JMP DO_READ_KEY    ; $D006
SYS_PRINT_STR:  JMP DO_PRINT_STR   ; $D009 - Print null-terminated string (A=Low, Y=High)
SYS_NEWLINE:    JMP DO_NEWLINE     ; $D00C - Advance cursor to next line

RESET:
    SEI
    CLD
    LDX #$FF
    TXS

    JSR DO_CLEAR_VRAM

    ; --- Print Boot Message using new Syscall ---
    LDA #<BOOT_MSG
    LDY #>BOOT_MSG
    JSR DO_PRINT_STR
    JSR DO_NEWLINE

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
    BEQ ENTER_PRESSED
    CMP #$08
    BEQ DO_BACKSPACE

    ; Prevent buffer overflow (limit to 15 characters)
    LDX BUFPTR
    CPX #$0F
    BCS REPL_LOOP

    JSR DO_PRINT_CHAR   ; A is now safely preserved by DO_PRINT_CHAR
    LDX BUFPTR
    STA CMDBUF, X       ; CMDBUF now receives the correct typed character!
    INC BUFPTR
    JMP REPL_LOOP

DO_BACKSPACE:
    LDA BUFPTR
    BEQ REPL_LOOP        ; nothing to delete, ignore

    DEC BUFPTR

    ; step cursor back one cell
    LDA CURSOR
    BNE SkipDecHigh
    DEC CURSOR+1
SkipDecHigh:
    DEC CURSOR

    LDA #' '
    JSR DO_PRINT_CHAR    ; overwrite the glyph with a space...

    ; ...then step cursor back again so we're positioned on that blank cell
    LDA CURSOR
    BNE SkipDecHigh2
    DEC CURSOR+1
SkipDecHigh2:
    DEC CURSOR

    JMP REPL_LOOP

ENTER_PRESSED:
    JSR DO_NEWLINE       ; Visual newline immediately when user hits Enter
    
    LDA BUFPTR
    BEQ REPL_INIT        ; If empty command, just show prompt again
    JMP PARSE_CMD

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

    ; --- Successful Command Execution ---
    JSR $8000
    JSR DO_NEWLINE       ; New line after successfully returning from CART
    JMP REPL_INIT

CMD_NOT_FOUND:
    ; --- Incorrect Command Execution ---
    LDA #'?'
    JSR DO_PRINT_CHAR
    JSR DO_NEWLINE       ; New line after error indicator
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
    STA TEMP_A           ; Save A
    TYA
    PHA                  ; Save Y
    TXA
    PHA                  ; Save X
    ; -------------------------------------

    LDA TEMP_A           ; Recover A for comparison
    CMP #$0D             ; Check for carriage return character
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
    TAX                  ; Restore X
    PLA
    TAY                  ; Restore Y
    LDA TEMP_A           ; Restore A
    ; ----------------------------------------
    RTS

DO_NEWLINE:
    ; Fast math to jump to the start of the next 32-column line
    LDA CURSOR
    AND #$E0
    CLC
    ADC #$20
    STA CURSOR
    BCC CheckScroll
    INC CURSOR+1
CheckScroll:
    LDA CURSOR+1
    CMP #$06             ; Did we hit $0600 (end of 512-byte text memory)?
    BCC NewlineDone
    JSR DO_SCROLL_UP
NewlineDone:
    RTS

DO_SCROLL_UP:
    ; Shift VRAM up by 32 bytes (1 line)
    LDX #0
Scrl1:
    LDA $0420, X         ; Move $0420-$051F up 1 page
    STA $0400, X
    INX
    BNE Scrl1
Scrl2:
    LDA $0520, X         ; Move $0520-$05FF up 
    STA $0500, X
    INX
    CPX #$E0             ; End at $05DF (256 - 32 = 224 or $E0)
    BNE Scrl2

    ; Clear the newly created bottom line
    LDA #$20             ; Space character
    LDX #0
ClearLast:
    STA $05E0, X
    INX
    CPX #$20
    BNE ClearLast

    ; Reset cursor to start of bottom line
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
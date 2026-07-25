; Sushic-500 System Calls
SYS_CLEAR_VRAM = $D000
SYS_PRINT_CHAR = $D003

.segment "CODE"

CART_START:
    JSR SYS_CLEAR_VRAM    
    LDX #0                

PRINT_LOOP:
    LDA HELLO_MSG, X      
    BEQ DONE              
    JSR SYS_PRINT_CHAR    
    INX                   
    JMP PRINT_LOOP        

DONE:
    JMP DONE

HELLO_MSG:
    .asciiz "HELLO WORLD FROM THE SUSHIC-500 CARTRIDGE!"
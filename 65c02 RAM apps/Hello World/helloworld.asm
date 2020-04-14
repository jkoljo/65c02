;-------------------------------------------------------------------------
;  65c02 Breadboard project - Hello World RAM app
;-------------------------------------------------------------------------

;-------------------------------------------------------------------------
;  Physical mappings
;  $0 - $FF Zero Page
;  $0100-$01FF Stack
;  $0200-$3FFF RAM
;  $5000 	   Serial port
;  $6000-$600F VIA #1
;  $8000-$FFFF ROM
;-------------------------------------------------------------------------

V_RTC_SEC       = $0                    ; RTC time variables
V_RTC_MIN       = $1
V_RTC_HR        = $2

V_P_STR_LO      = $3                    ; String address pointer, used for printing
V_P_STR_HI      = $4                    ; String address pointer, used for printing
S_DATA_RDY      = $5                    ; Data available from serial bus, used by NMI
S_IN_BYTE       = $6                    ; Input byte from serial bus, used by NMI
S_BYTE_COUNT    = $7                    ; Incoming byte counter, used by serial test app

V_DISP_CHANGED  = $8                    ; Has bootloader menu state changed (need to redraw)
V_JUMP_REQ      = $9                    ; Is there a jump request from user
V_KEYSTROKE     = $10                   ; User keystroke variable
V_LCD_SELECTION = $11                   ; Current menu item
V_JMP_SELECTION = $12                   ; Selected item
V_IN_SUBMENU    = $13                   ; Are we in main menu (or builtin app menu)
V_MAX_ENTRIES   = $14                   ; Number of entries in current submenu

CURR_BLOCK      = $15                   ; Current payload # being received over serial
CURR_ADDR_L     = $16                   ; Address to write payload byte to
CURR_ADDR_H     = $17                   ; Address to write payload byte to
CHECKSUM        = $18                   ; Checksum, calculated per 128-byte payload

USR_PROG        = $0200                 ; Start of user program storage in RAM
	
ACIA_DATA		= $5000
ACIA_STATUS 	= $5001
ACIA_CMD 		= $5002
PORTB 			= $6000
PORTA 			= $6001
DDRB 			= $6002
DDRA 			= $6003
T2CL 			= $6008
T2CH 			= $6009
SR 				= $600A
ACR 			= $600B
PCR 			= $600C
IFR 			= $600D
IER 			= $600E


;-------------------------------------------------------------------------
;  Constants
;-------------------------------------------------------------------------

LCD_NUM_MASK 	= %00110000

LCD_E  			= %10000000 			; In PORTA
LCD_RW 			= %01000000	
LCD_RS 			= %00100000	
LCD_BUSY    	= %00001000	
	
KEYS_MASK 		= %00011100	
KEY_ENTER 		= %00000100 			; In PORTA
KEY_UP 			= %00001000		
KEY_DN 			= %00010000			
		
SR_IDLE 		= %00000011 			; In PORTA, no conversion triggered, SR in parallel listen mode
SR_CONVERT  	= %00000001		
SR_LATCH 		= %00000010		
		
GP0 			= %01000000 			; Spare I/O of PORTA..
GP1				= %00100000		
GP2				= %00010000		
			
DDRA_BITS 		= %11100011		
DDRB_BITS 		= %00001111		
		
LCD_CLR_BITS 	= %00000001 			; LCD clear command
		
MMENU_ENTRIES  	= 3 					; Number of entries in bootloader menu (0-indexed)
BMENU_ENTRIES  	= 2						; Number of entries in the builtin app menu (0-indexed)

SOH 			= 1 					; Start of heading
ENQ 			= 5						; Enquiry
ACK 			= 6 					; Acknowledge
NAK				= 21 					; Negative acknowledge
EOT 			= 26 					; End of transfer


;-------------------------------------------------------------------------
;  Set assembler location counter to match current memory mapping
;-------------------------------------------------------------------------

				.org $0200 			; Location counter $0200, start location for RAM apps


;-------------------------------------------------------------------------
;  App to print Hello World and stop
;-------------------------------------------------------------------------

APP_HELLO_RAM:	LDA #>str_helloworld
  				STA V_P_STR_HI
  				LDA #<str_helloworld
  				STA V_P_STR_LO
  				JSR LCD_P_STR
	 			STP


;-------------------------------------------------------------------------
;  Subroutine to print a string to LCD, addressed indirectly, pointer at $10, $11
;  Leaves Y loaded with length of printed string
;-------------------------------------------------------------------------

LCD_P_STR:		LDY #0 					; Use Y to index through chars
.lpstr0: 		LDA (V_P_STR_LO),Y 		; Print individual char
  				CMP #255
  				BEQ .lpstr1 			; Print finished if terminating char 255 found
  				JSR LCD_PRINT
  				INY
  				JMP .lpstr0 			
.lpstr1:		INY 					; Y += 1 to match printed char count
				RTS


;-------------------------------------------------------------------------
;  Subroutine to print whatever to LCD
;-------------------------------------------------------------------------

LCD_PRINT:      PHA                     ; First send 4 MSB
                LSR A
                LSR A
                LSR A
                LSR A
                AND #%00001111
                STA PORTB
                LDA #(LCD_RS | SR_IDLE) 
                STA PORTA               ; Set RS; Clear RW/E bits
                LDA #(LCD_RS | LCD_E | SR_IDLE) 
                STA PORTA               ; Set E bit to send instruction
                LDA #(LCD_RS | SR_IDLE) 
                STA PORTA               ; Clear E bits
                PLA                     ; Then send 4 LSB
                AND #%00001111
                STA PORTB
                LDA #(LCD_RS | LCD_E | SR_IDLE) 
                STA PORTA               ; Set E bit to send instruction
                LDA #(LCD_RS | SR_IDLE) 
                STA PORTA               ; Clear E bits
                RTS


;-------------------------------------------------------------------------
;  String storage
;-------------------------------------------------------------------------

str_helloworld:
	db "Hello world!                            From RAM $0200",255


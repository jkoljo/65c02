;-------------------------------------------------------------------------
;  Application to test serial port output capability
;-------------------------------------------------------------------------

APP_S_OUT_TEST:	LDA #>str_serialout_title
  				STA V_P_STR_HI	
  				LDA #<str_serialout_title
  				STA V_P_STR_LO
  				JSR LCD_P_STR
  				JMP SER_OUT_TEST


;-------------------------------------------------------------------------
;  Subroutine to output title string continuously
;-------------------------------------------------------------------------

SER_OUT_TEST:	LDA #>str_uboot_title1	; Print SW title as test string
  				STA V_P_STR_HI	
  				LDA #<str_uboot_title1
  				STA V_P_STR_LO
  				JSR SER_P_STR
  				LDA #10 				; Ascii for \n
  				STA SERIAL
  				WAI 					; Sleep ~1s
  				JMP SER_OUT_TEST
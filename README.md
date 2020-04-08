# 65c02
Bits and pieces for a breadboard computer project

- 65c02 µboot, a small bootloader that provides a UI and xmodem-ish connectivity for loading apps to ram from a PC.

- Teensy 65c02 coprocessor, a Teensy 4.0 program to emulate an ACIA, but much faster. Keeps up with 1 MHz 65c02 clock when Teensy is clocked to at least 720 MHz.

- 65c02 Teensy Master PCB, a level shifter to enable fast bidirectional communcation between Teensy 4.0 and the 65c02.
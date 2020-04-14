# 65c02
Bits and pieces for a breadboard computer project

- 65c02 µboot, a small bootloader that provides a UI and xmodem-ish connectivity for loading apps to ram from a PC.

- 65c02 Teensy Master PCB, a level shifter to enable fast bidirectional communcation between Teensy 4.0 and the 65c02.

- J-Modem sender, a Python-based binary transfer app

- Teensy 65c02 coprocessor, a Teensy 4.0 program to emulate an ACIA, but much faster. Keeps up with 1 MHz 65c02 clock. With 912 MHz Teensy speed, it runs fast enough that any number of input/output bytes do not overload Teensy. Continuous data transfers at around 9000-10000 bytes per second work great. Microchess by Peter Jennings transfers in around 0.55-0.60 seconds.

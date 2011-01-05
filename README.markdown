Beacon - Extreme Feedback Device based on Arduino + Dioder
==========================================================

## Description

Beacon is an arduino sketch + assemblage designed to show the status of a continuous integration system through
a set of IKEA Dioder lights.

It was designed to be the simplest way to implement a Extreme Feedback Device with a small incremental budget.

It uses a TLC5940 chip to control the leds without the need to use Darlington pairs, that reduces the necessary components
from 24 (2 transistors * 4 Bars * 3 Color Components) to 2 (TLC5940 + 2k Resistor).

## Instructions

1. Get a multicolor IKEA DIODER Lighting strip
2. Get a Arduino UNO / MEGA / MEGA 2560
    * The UNO is the budget choice, but it requires some hardware hacks to work with an ethernet shield
    * The Mega[2560] is simpler to assemble, has room for future functionality, but it is pricier
    * The project was tested on a Arduino Diecimilia and a Arduino Mega - old version, it runs on a 16k Arduino, so, you can
      use an older Arduino.
3. Hardware part list
    * 1x Standard Breadboard
    * 1x TLC5940 chip
    * 1x 2K Resistor
    * 4x "Polarized 4 pin male headers" (google for this)
    * Single-strand wire in assorted colors (see schematics)
4. Install the Arduino IDE
5. Get the TLC5940 Arduino library from http://code.google.com/p/tlc5940arduino/
6. Apply the changes described in the README file inside the Arduino sketch folder to the Ethernet and TLC libraries in the
   Arduino installation.
7. Open the arduino sketch and upload it to the arduino (don't forget to either disable ethernet or create the ipconfig.h file).
8. Use the diagram in the fritzing folder and the README in the Arduino project folder for assembly instructions.
9. Use a 12V transformer to power the arduino. Using the supplied instructions, the lights don't have to be powered separately.

After assembling the board and uploading the sketch, powering the arduino will set the lights to test mode: each set of
leds will be lit one by one on each bar. To send commands to the arduino, open the Serial Monitor (on the Arduino IDE) and send the
commands (without the quotes): "g!.w;" and then "b.p;" or "r.a;"

If you decide to give up after steps 1 or 2, you still have a cool lamp and possibly a nice start for other projects.

If you get to this point, you can already use or dioder lights as an XFD device (even on the breadboard.)

If you are going for the long run:

1. (Optional) Get an Arduino Ethernet Shield (v5 is easier to use with an Arduino Mega)
    * Use a v4 shield if you already have one, or if you want to go cheaper (while stocks last)
    * Use a v5 shield if you are using an Arduino Mega
2. Do the same assembly on a stripboard. Part list:
    * 1x Stripboard (Big/small enough to use as a shield)
    * 1x DIP28 Socket (Don't solder the TLC directly to the board)
    * 1x "Shield stacking headers for Arduino" or similar (Check the adafruit site)

## Hello World using the USB/serial port

The processing folder contains a project that changes colors on the bars and shows the alert mode.

## Using with Hudson

The node.js folder contains a script that updates the arduino (via ethernet).

## Caveat Emptor

Use this assembly at your own risk. I take no responsability in any hardware damage resulting of this
project.

## LICENSE:

(The MIT License)

Copyright (c) 2010 Luis Reis

Permission is hereby granted, free of charge, to any person obtaining
a copy of this software and associated documentation files (the
'Software'), to deal in the Software without restriction, including
without limitation the rights to use, copy, modify, merge, publish,
distribute, sublicense, and/or sell copies of the Software, and to
permit persons to whom the Software is furnished to do so, subject to
the following conditions:

The above copyright notice and this permission notice shall be
included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED 'AS IS', WITHOUT WARRANTY OF ANY KIND,
EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

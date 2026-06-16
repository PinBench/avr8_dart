# avr8_dart

A Dart library that implements the AVR 8-bit architecture, enabling you to simulate Arduino and ATmega/ATtiny microcontrollers directly in Dart and Flutter. 

This is a direct, 1-to-1 port of the official [avr8js](https://github.com/wokwi/avr8js) library (created by Uri Shaked), achieving 100% test coverage and parity with the original TypeScript project.

## Features

- **Core CPU Simulation**: Complete implementation of the AVR 8-bit instruction set.
- **Peripheral Simulation**: Fully functional simulations for common AVR peripherals:
  - GPIO
  - Timers (8-bit and 16-bit, including ATtiny support)
  - USART (Serial)
  - SPI
  - TWI (I2C)
  - ADC
  - EEPROM
  - Watchdog
- **No Dependencies**: Written in pure Dart. It works perfectly in Flutter web, mobile, and desktop applications.

## How to Use This Library

This library simulates the inner workings of the AVR CPU core and its internal peripherals. To use it, you need to provide pre-compiled machine code (a `.hex` file compiled via `avr-gcc` or the Arduino IDE) and implement the functional simulations of any external hardware connected to the pins (like LEDs, buttons, or screens).

A rough conceptual diagram:
```
Compiled .hex code --> avr8_dart <--> Glue code <--> External hardware UI simulation
```

### Basic Example

Here is a minimal example demonstrating how to set up the CPU, load a program, and execute it cycle by cycle.

```dart
import 'dart:typed_data';
import 'package:avr8_dart/avr8_dart.dart';

void main() {
  // 1. Create the CPU with 16KB of Flash memory
  final program = Uint16List(0x2000); 
  
  // (In a real app, you would load an Intel HEX file into `program` here)
  
  final cpu = CPU(program);

  // 2. Initialize peripherals (e.g., Timer and USART)
  AVRTimer(cpu, timer0Config);
  final usart = AVRUSART(cpu, usart0Config, 16000000);
  
  // Listen for serial output
  usart.onByteTransmit = (int byte) {
    print('Serial Output: ${String.fromCharCode(byte)}');
  };

  // 3. Run the simulation
  // Execute instructions in a loop
  for (int i = 0; i < 1000; i++) {
    avrInstruction(cpu);
    cpu.tick();
  }
}
```

## Running the Tests

The project maintains 100% test parity with the original `avr8js` library, ensuring accurate behavioral simulation across all edge cases.

To run the full suite of tests (344 tests):

```bash
dart test
```

## Project Status

`avr8_dart` is fully functional and covers the complete `ATmega328p` (Arduino Uno) simulation architecture. It also supports `ATtiny85` hardware configurations. 

See the [CHANGELOG.md](CHANGELOG.md) and [VERSION.md](VERSION.md) for detailed reference version tracking.

## Acknowledgements

All architectural credit goes to [Uri Shaked](https://github.com/urish) and the Wokwi team for the brilliant design of the original [avr8js](https://github.com/wokwi/avr8js) library.

## License

Copyright (C) 2019-2025 Uri Shaked (Original TS)  
Copyright (C) 2026 Burhan Khanzada (Dart Port)  

This code is released under the terms of the MIT license.

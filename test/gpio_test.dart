import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:avr8_dart/src/cpu/cpu.dart';
import 'package:avr8_dart/src/cpu/instruction.dart';
import 'package:avr8_dart/src/peripherals/gpio.dart';

// CPU registers
const SREG = 95;

// GPIO registers
const PINB = 0x23;
const DDRB = 0x24;
const PORTB = 0x25;
const PIND = 0x29;
const DDRD = 0x2a;
const PORTD = 0x2b;
const EIFR = 0x3c;
const EIMSK = 0x3d;
const PCICR = 0x68;
const EICRA = 0x69;
const PCIFR = 0x3b;
const PCMSK0 = 0x6b;

// Register bit names
const INT0 = 0;
const ISC00 = 0;
const ISC01 = 1;
const PCIE0 = 0;
const PCINT3 = 3;

// Pin names
const PB0 = 0;
const PB1 = 1;
const PB3 = 3;
const PB4 = 4;
const PD2 = 2;

// Interrupt vector addresses
const PC_INT_INT0 = 2;
const PC_INT_PCINT0 = 6;

void main() {
  group('GPIO', () {
    test('should invoke the listeners when the port is written to', () {
      final cpu = CPU(Uint16List(1024));
      final port = AVRIOPort(cpu, portBConfig);
      
      int? lastValue;
      int? lastOldValue;
      port.addListener((int value, int oldValue) {
        lastValue = value;
        lastOldValue = oldValue;
      });
      
      cpu.writeData(DDRB, 0x0f);
      cpu.writeData(PORTB, 0x55);
      expect(lastValue, equals(0x55));
      expect(lastOldValue, equals(0));
      expect(cpu.data[0x23], equals(0x5)); // PINB should return port value
    });

    test('should invoke the listeners when DDR changes (issue #28)', () {
      final cpu = CPU(Uint16List(1024));
      final port = AVRIOPort(cpu, portBConfig);

      int? lastValue;
      int? lastOldValue;
      cpu.writeData(PORTB, 0x55);
      port.addListener((int value, int oldValue) {
        lastValue = value;
        lastOldValue = oldValue;
      });

      cpu.writeData(DDRB, 0xf0);
      expect(lastValue, equals(0x55));
      expect(lastOldValue, equals(0x55));
    });

    test('should invoke the listeners when pullup register enabled (issue #62)', () {
      final cpu = CPU(Uint16List(1024));
      final port = AVRIOPort(cpu, portBConfig);

      int? lastValue;
      int? lastOldValue;
      port.addListener((int value, int oldValue) {
        lastValue = value;
        lastOldValue = oldValue;
      });

      cpu.writeData(PORTB, 0x55);
      expect(lastValue, equals(0x55));
      expect(lastOldValue, equals(0));
    });

    test('should toggle the pin when writing to the PIN register', () {
      final cpu = CPU(Uint16List(1024));
      final port = AVRIOPort(cpu, portBConfig);

      int? lastValue;
      int? lastOldValue;
      port.addListener((int value, int oldValue) {
        lastValue = value;
        lastOldValue = oldValue;
      });

      cpu.writeData(DDRB, 0x0f);
      cpu.writeData(PORTB, 0x55);
      cpu.writeData(PINB, 0x01);
      
      expect(lastValue, equals(0x54));
      expect(lastOldValue, equals(0x55));
      expect(cpu.data[PINB], equals(0x4)); // PINB should return port value
    });

    test('should only affect one pin when writing to PIN using SBI (issue #103)', () {
      final progMem = Uint16List(1024);
      progMem[0] = 0xe488; // ldi r24, 0x48
      progMem[1] = 0xb98a; // out DDRD, r24
      progMem[2] = 0xb98b; // out PORTD, r24
      progMem[3] = 0x9a4e; // sbi PIND, 6
      progMem[4] = 0x9598; // break

      final cpu = CPU(progMem);
      final portD = AVRIOPort(cpu, portDConfig);

      int? lastValue;
      int? lastOldValue;
      portD.addListener((int value, int oldValue) {
        lastValue = value;
        lastOldValue = oldValue;
      });

      // Setup: pins 6, 3 are output, set to HIGH
      for (var i = 0; i < 3; i++) {
        avrInstruction(cpu);
      }
      expect(lastValue, equals(0x48));
      expect(lastOldValue, equals(0x0));
      expect(cpu.data[PORTD], equals(0x48));

      // Reset listener
      lastValue = null;
      lastOldValue = null;

      // Now we toggle pin 6
      avrInstruction(cpu);
      
      expect(lastValue, equals(0x08));
      expect(lastOldValue, equals(0x48));
      expect(cpu.data[PORTD], equals(0x8));
    });

    test('should update the PIN register on output compare (OCR) match (issue #102)', () {
      final cpu = CPU(Uint16List(1024));
      final port = AVRIOPort(cpu, portBConfig);
      
      cpu.writeData(DDRB, 1 << 1);
      port.timerOverridePin(1, PinOverrideMode.Set);
      expect(port.pinState(1), equals(PinState.High));
      expect(cpu.data[PINB], equals(1 << 1));
      
      port.timerOverridePin(1, PinOverrideMode.Clear);
      expect(port.pinState(1), equals(PinState.Low));
      expect(cpu.data[PINB], equals(0));
    });

    group('removeListener', () {
      test('should remove the given listener', () {
        final cpu = CPU(Uint16List(1024));
        final port = AVRIOPort(cpu, portBConfig);
        
        int callCount = 0;
        void listener(int value, int oldValue) {
          callCount++;
        }
        
        port.addListener(listener);
        cpu.writeData(DDRB, 0x0f);
        port.removeListener(listener);
        cpu.writeData(PORTB, 0x99);
        expect(callCount, equals(1));
      });
    });

    group('pinState', () {
      test('should return PinState.High when the pin set to output and HIGH', () {
        final cpu = CPU(Uint16List(1024));
        final port = AVRIOPort(cpu, portBConfig);
        cpu.writeData(DDRB, 0x1);
        cpu.writeData(PORTB, 0x1);
        expect(port.pinState(PB0), equals(PinState.High));
      });

      test('should return PinState.Low when the pin set to output and LOW', () {
        final cpu = CPU(Uint16List(1024));
        final port = AVRIOPort(cpu, portBConfig);
        cpu.writeData(DDRB, 0x8);
        cpu.writeData(PORTB, 0xf7);
        expect(port.pinState(PB3), equals(PinState.Low));
      });

      test('should return PinState.Input by default (reset state)', () {
        final cpu = CPU(Uint16List(1024));
        final port = AVRIOPort(cpu, portBConfig);
        expect(port.pinState(PB1), equals(PinState.Input));
      });

      test('should return PinState.InputPullUp when the pin is set to input with pullup', () {
        final cpu = CPU(Uint16List(1024));
        final port = AVRIOPort(cpu, portBConfig);
        cpu.writeData(DDRB, 0);
        cpu.writeData(PORTB, 0x2);
        expect(port.pinState(PB1), equals(PinState.InputPullUp));
      });

      test('should reflect the current port state when called inside a listener', () {
        final cpu = CPU(Uint16List(1024));
        final port = AVRIOPort(cpu, portBConfig);
        
        expect(port.pinState(PB0), equals(PinState.Input));
        cpu.writeData(DDRB, 0x01);

        int callCount = 0;
        port.addListener((int value, int oldValue) {
          expect(port.pinState(PB0), equals(PinState.High));
          callCount++;
        });
        
        cpu.writeData(PORTB, 0x01);
        expect(callCount, equals(1));
      });

      test('should reflect the current port state when called inside a listener after DDR change', () {
        final cpu = CPU(Uint16List(1024));
        final port = AVRIOPort(cpu, portBConfig);
        
        int callCount = 0;
        port.addListener((int value, int oldValue) {
          expect(port.pinState(PB0), equals(PinState.Low));
          callCount++;
        });
        
        expect(port.pinState(PB0), equals(PinState.Input));
        cpu.writeData(DDRB, 0x01);
        expect(callCount, equals(1));
      });
    });

    group('setPin', () {
      test('should set the value of the given pin', () {
        final cpu = CPU(Uint16List(1024));
        final port = AVRIOPort(cpu, portBConfig);
        cpu.writeData(DDRB, 0);
        port.setPin(PB4, true);
        expect(cpu.data[0x23], equals(0x10));
        port.setPin(PB4, false);
        expect(cpu.data[0x23], equals(0x0));
      });

      test('should only update PIN register when pin in Input mode', () {
        final cpu = CPU(Uint16List(1024));
        final port = AVRIOPort(cpu, portBConfig);
        cpu.writeData(DDRB, 0x10);
        cpu.writeData(PORTB, 0x0);
        port.setPin(PB4, true);
        expect(cpu.data[PINB], equals(0x0));
        cpu.writeData(DDRB, 0x0);
        expect(cpu.data[PINB], equals(0x10));
      });
    });

    group('External interrupt', () {
      test('should generate INT0 interrupt on rising edge', () {
        final cpu = CPU(Uint16List(1024));
        final port = AVRIOPort(cpu, portDConfig);
        cpu.writeData(EIMSK, 1 << INT0);
        cpu.writeData(EICRA, (1 << ISC01) | (1 << ISC00));

        expect(cpu.data[EIFR], equals(0));
        port.setPin(PD2, true);
        expect(cpu.data[EIFR], equals(1 << INT0));

        cpu.data[SREG] = 0x80; // SREG: I------- (enable interrupts)
        cpu.tick();
        expect(cpu.pc, equals(PC_INT_INT0));
        expect(cpu.cycles, equals(2));
        expect(cpu.data[EIFR], equals(0));

        port.setPin(PD2, false);
        expect(cpu.data[EIFR], equals(0));
      });

      test('should generate INT0 interrupt on falling edge', () {
        final cpu = CPU(Uint16List(1024));
        final port = AVRIOPort(cpu, portDConfig);
        cpu.writeData(EIMSK, 1 << INT0);
        cpu.writeData(EICRA, 1 << ISC01);

        expect(cpu.data[EIFR], equals(0));
        port.setPin(PD2, true);
        expect(cpu.data[EIFR], equals(0));
        port.setPin(PD2, false);
        expect(cpu.data[EIFR], equals(1 << INT0));

        cpu.data[SREG] = 0x80; // SREG: I------- (enable interrupts)
        cpu.tick();
        expect(cpu.pc, equals(PC_INT_INT0));
        expect(cpu.cycles, equals(2));
        expect(cpu.data[EIFR], equals(0));
      });

      test('should generate INT0 interrupt on level change', () {
        final cpu = CPU(Uint16List(1024));
        final port = AVRIOPort(cpu, portDConfig);
        cpu.writeData(EIMSK, 1 << INT0);
        cpu.writeData(EICRA, 1 << ISC00);

        expect(cpu.data[EIFR], equals(0));
        port.setPin(PD2, true);
        expect(cpu.data[EIFR], equals(1 << INT0));
        cpu.writeData(EIFR, 1 << INT0);
        expect(cpu.data[EIFR], equals(0));
        port.setPin(PD2, false);
        expect(cpu.data[EIFR], equals(1 << INT0));
      });

      test('should a sticky INT0 interrupt while the pin level is low', () {
        final cpu = CPU(Uint16List(1024));
        final port = AVRIOPort(cpu, portDConfig);
        cpu.writeData(EIMSK, 1 << INT0);
        cpu.writeData(EICRA, 0);
        expect(cpu.data[EIFR], equals(0));

        port.setPin(PD2, true);
        expect(cpu.data[EIFR], equals(0));

        port.setPin(PD2, false);
        expect(cpu.data[EIFR], equals(1 << INT0));

        // This is a sticky interrupt, verify we can't clear the flag:
        cpu.writeData(EIFR, 1 << INT0);
        expect(cpu.data[EIFR], equals(1 << INT0));

        cpu.data[SREG] = 0x80; // SREG: I------- (enable interrupts)
        cpu.tick();
        expect(cpu.pc, equals(PC_INT_INT0));
        expect(cpu.cycles, equals(2));

        // Flag shouldn't be cleared, as the interrupt is sticky
        expect(cpu.data[EIFR], equals(1 << INT0));

        // But it will be cleared as soon as the pin goes high.
        port.setPin(PD2, true);
        expect(cpu.data[EIFR], equals(0));
      });
    });

    group('Pin change interrupts (PCINT)', () {
      test('should generate a pin change interrupt when PB3 (PCINT3) goes high', () {
        final cpu = CPU(Uint16List(1024));
        final port = AVRIOPort(cpu, portBConfig);
        cpu.writeData(PCICR, 1 << PCIE0);
        cpu.writeData(PCMSK0, 1 << PCINT3);

        port.setPin(PB3, true);
        expect(cpu.data[PCIFR], equals(1 << PCIE0));

        cpu.data[SREG] = 0x80; // SREG: I-------
        cpu.tick();
        expect(cpu.pc, equals(PC_INT_PCINT0));
        expect(cpu.cycles, equals(2));
        expect(cpu.data[PCIFR], equals(0));
      });

      test('should generate a pin change interrupt when PB3 (PCINT3) goes low', () {
        final cpu = CPU(Uint16List(1024));
        final port = AVRIOPort(cpu, portBConfig);

        port.setPin(PB3, true);
        cpu.writeData(PCICR, 1 << PCIE0);
        cpu.writeData(PCMSK0, 1 << PCINT3);
        expect(cpu.data[PCIFR], equals(0));

        port.setPin(PB3, false);
        expect(cpu.data[PCIFR], equals(1 << PCIE0));

        cpu.data[SREG] = 0x80; // SREG: I-------
        cpu.tick();
        expect(cpu.pc, equals(PC_INT_PCINT0));
        expect(cpu.cycles, equals(2));
        expect(cpu.data[PCIFR], equals(0));
      });

      test('should clear the interrupt flag when writing to PCIFR', () {
        final cpu = CPU(Uint16List(1024));
        final port = AVRIOPort(cpu, portBConfig);
        cpu.writeData(PCICR, 1 << PCIE0);
        cpu.writeData(PCMSK0, 1 << PCINT3);

        port.setPin(PB3, true);
        expect(cpu.data[PCIFR], equals(1 << PCIE0));

        cpu.writeData(PCIFR, 1 << PCIE0);
        expect(cpu.data[PCIFR], equals(0));
      });
    });
  });
}

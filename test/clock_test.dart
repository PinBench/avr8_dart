import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:avr8_dart/src/cpu/cpu.dart';
import 'package:avr8_dart/src/peripherals/clock.dart';

// Clock Registers
const CLKPC = 0x61;

// Register bit names
const CLKPCE = 128;

void main() {
  group('Clock', () {
    test('should set the prescaler when double-writing CLKPC', () {
      final cpu = CPU(Uint16List(0x1000));
      final clock = AVRClock(cpu, 16000000, clockConfig);
      cpu.writeData(CLKPC, CLKPCE);
      cpu.writeData(CLKPC, 3); // Divide by 8 (2^3)
      expect(clock.frequency, equals(2000000)); // 2MHz
      expect(cpu.readData(CLKPC), equals(3));
    });

    test('should not update the prescaler if CLKPCE was not set CLKPC', () {
      final cpu = CPU(Uint16List(0x1000));
      final clock = AVRClock(cpu, 16000000, clockConfig);
      cpu.writeData(CLKPC, 3); // Divide by 8 (2^3)
      expect(clock.frequency, equals(16000000)); // still 16MHz
      expect(cpu.readData(CLKPC), equals(0));
    });

    test(
        'should not update the prescaler if more than 4 cycles passed since setting CLKPCE',
        () {
      final cpu = CPU(Uint16List(0x1000));
      final clock = AVRClock(cpu, 16000000, clockConfig);
      cpu.writeData(CLKPC, CLKPCE);
      cpu.cycles += 6;
      cpu.writeData(CLKPC, 3); // Divide by 8 (2^3)
      expect(clock.frequency, equals(16000000)); // still 16MHz
      expect(cpu.readData(CLKPC), equals(0));
    });

    group('prescaler property', () {
      test('should return the current prescaler value', () {
        final cpu = CPU(Uint16List(0x1000));
        final clock = AVRClock(cpu, 16000000, clockConfig);
        cpu.writeData(CLKPC, CLKPCE);
        cpu.writeData(CLKPC, 5); // Divide by 32 (2^5)
        cpu.cycles = 16000000;
        expect(clock.prescaler, equals(32));
      });
    });

    group('time properties', () {
      test(
          'should return current number of microseconds, derived from base freq + prescaler',
          () {
        final cpu = CPU(Uint16List(0x1000));
        final clock = AVRClock(cpu, 16000000, clockConfig);
        cpu.writeData(CLKPC, CLKPCE);
        cpu.writeData(CLKPC, 2); // Divide by 4 (2^2)
        cpu.cycles = 16000000;
        expect(clock.timeMillis, equals(4000)); // 4 seconds
      });

      test(
          'should return current number of milliseconds, derived from base freq + prescaler',
          () {
        final cpu = CPU(Uint16List(0x1000));
        final clock = AVRClock(cpu, 16000000, clockConfig);
        cpu.writeData(CLKPC, CLKPCE);
        cpu.writeData(CLKPC, 2); // Divide by 4 (2^2)
        cpu.cycles = 16000000;
        expect(clock.timeMicros, equals(4e6)); // 4 seconds
      });

      test(
          'should return current number of nanoseconds, derived from base freq + prescaler',
          () {
        final cpu = CPU(Uint16List(0x1000));
        final clock = AVRClock(cpu, 16000000, clockConfig);
        cpu.writeData(CLKPC, CLKPCE);
        cpu.writeData(CLKPC, 2); // Divide by 4 (2^2)
        cpu.cycles = 16000000;
        expect(clock.timeNanos, equals(4e9)); // 4 seconds
      });

      test(
          'should correctly calculate time when changing the prescale value at runtime',
          () {
        final cpu = CPU(Uint16List(0x1000));
        final clock = AVRClock(cpu, 16000000, clockConfig);
        cpu.cycles = 16000000; // run 1 second at 16MHz
        cpu.writeData(CLKPC, CLKPCE);
        cpu.writeData(CLKPC, 2); // Divide by 4 (2^2)
        cpu.cycles += (2 * 4e6).toInt(); // run 2 more seconds at 4MhZ
        expect(clock.timeMillis, equals(3000)); // 3 seconds in total

        cpu.writeData(CLKPC, CLKPCE);
        cpu.writeData(CLKPC, 1); // Divide by 2 (2^1)
        cpu.cycles += (0.5 * 8e6).toInt(); // run 0.5 more seconds at 8MhZ
        expect(clock.timeMillis, equals(3500)); // 3.5 seconds in total
      });
    });
  });
}

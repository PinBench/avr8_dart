import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:avr8_dart/src/cpu/cpu.dart';
import 'package:avr8_dart/src/cpu/interrupt.dart';

void main() {
  group('avrInterrupt', () {
    test('should execute interrupt handler', () {
      final cpu = CPU(Uint16List(0x8000));
      cpu.pc = 0x520;
      cpu.data[94] = 0;
      cpu.data[93] = 0x80; // SP <- 0x80
      cpu.data[95] = 0x81; // SREG <- I------C
      avrInterrupt(cpu, 5);
      expect(cpu.cycles, equals(2));
      expect(cpu.pc, equals(5));
      expect(cpu.data[93], equals(0x7e)); // SP
      expect(cpu.data[0x80], equals(0x20)); // Return addr low
      expect(cpu.data[0x7f], equals(0x5)); // Return addr high
      expect(cpu.data[95], equals(0x01)); // SREG: -------C
    });

    test(
        'should push a 3-byte return address when running in 22-bit PC mode (issue #58)',
        () {
      final cpu = CPU(Uint16List(0x80000));
      expect(cpu.pc22Bits, isTrue);

      cpu.pc = 0x10520;
      cpu.data[94] = 0;
      cpu.data[93] = 0x80; // SP <- 0x80
      cpu.data[95] = 0x81; // SREG <- I------C

      avrInterrupt(cpu, 5);
      expect(cpu.cycles, equals(2));
      expect(cpu.pc, equals(5));
      expect(cpu.data[93], equals(0x7d)); // SP should decrement by 3
      expect(cpu.data[0x80], equals(0x20)); // Return addr low
      expect(cpu.data[0x7f], equals(0x05)); // Return addr high
      expect(cpu.data[0x7e], equals(0x1)); // Return addr extended
      expect(cpu.data[95], equals(0x01)); // SREG: -------C
    });
  });
}

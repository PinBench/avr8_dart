import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:avr8_dart/src/cpu/cpu.dart';
import 'package:avr8_dart/src/peripherals/eeprom.dart';

// EEPROM Registers
const EECR = 0x3f;
const EEDR = 0x40;
const EEARL = 0x41;
const EEARH = 0x42;
const SREG = 95;

// Register bit names
const EERE = 1;
const EEPE = 2;
const EEMPE = 4;
const EERIE = 8;
const EEPM0 = 16;
const EEPM1 = 32;

void main() {
  group('EEPROM', () {
    group('Reading the EEPROM', () {
      test('should return 0xff when reading from an empty location', () {
        final cpu = CPU(Uint16List(0x1000));
        AVREEPROM(cpu, EEPROMMemoryBackend(1024));
        cpu.writeData(EEARL, 0);
        cpu.writeData(EEARH, 0);
        cpu.writeData(EECR, EERE);
        cpu.tick();
        expect(cpu.cycles, equals(4));
        expect(cpu.data[EEDR], equals(0xff));
      });

      test('should return the value stored at the given EEPROM address', () {
        final cpu = CPU(Uint16List(0x1000));
        final eepromBackend = EEPROMMemoryBackend(1024);
        AVREEPROM(cpu, eepromBackend);
        eepromBackend.memory[0x250] = 0x42;
        cpu.writeData(EEARL, 0x50);
        cpu.writeData(EEARH, 0x2);
        cpu.writeData(EECR, EERE);
        cpu.tick();
        expect(cpu.data[EEDR], equals(0x42));
      });
    });

    group('Writing to the EEPROM', () {
      test('should write a byte to the given EEPROM address', () {
        final cpu = CPU(Uint16List(0x1000));
        final eepromBackend = EEPROMMemoryBackend(1024);
        AVREEPROM(cpu, eepromBackend);
        cpu.writeData(EEDR, 0x55);
        cpu.writeData(EEARL, 15);
        cpu.writeData(EEARH, 0);
        cpu.writeData(EECR, EEMPE);
        cpu.writeData(EECR, EEPE);
        cpu.tick();
        expect(cpu.cycles, equals(2));
        expect(eepromBackend.memory[15], equals(0x55));
        expect(cpu.data[EECR] & EEPE, equals(EEPE));
      });

      // asmProgram tests deferred to Phase 3

      test('should clear the EEPE bit and fire an interrupt when write has been completed', () {
        final cpu = CPU(Uint16List(0x1000));
        final eepromBackend = EEPROMMemoryBackend(1024);
        AVREEPROM(cpu, eepromBackend);
        cpu.writeData(EEDR, 0x55);
        cpu.writeData(EEARL, 15);
        cpu.writeData(EEARH, 0);
        cpu.writeData(EECR, EEMPE);
        cpu.data[SREG] = 0x80; // SREG: I-------
        cpu.writeData(EECR, EEPE | EERIE);
        cpu.cycles += 1000;
        cpu.tick();
        // At this point, write shouldn't be complete yet
        expect(cpu.data[EECR] & EEPE, equals(EEPE));
        expect(cpu.pc, equals(0));
        cpu.cycles += 10000000;
        // And now, 10 million cycles later, it should.
        cpu.tick();
        expect(eepromBackend.memory[15], equals(0x55));
        expect(cpu.data[EECR] & EEPE, equals(0));
        expect(cpu.pc, equals(0x2c)); // EEPROM Ready interrupt
      });

      test('should clear the fire an interrupt when there is a pending interrupt and the interrupt flag is enabled (issue #110)', () {
        final cpu = CPU(Uint16List(0x1000));
        final eepromBackend = EEPROMMemoryBackend(1024);
        AVREEPROM(cpu, eepromBackend);
        cpu.writeData(EEDR, 0x55);
        cpu.writeData(EEARL, 15);
        cpu.writeData(EEARH, 0);
        cpu.writeData(EECR, EEMPE);
        cpu.data[SREG] = 0x80; // SREG: I-------
        cpu.writeData(EECR, EEPE);
        cpu.cycles += 1000;
        cpu.tick();
        // At this point, write shouldn't be complete yet
        expect(cpu.data[EECR] & EEPE, equals(EEPE));
        expect(cpu.pc, equals(0));
        cpu.cycles += 10000000;
        // And now, 10 million cycles later, it should.
        cpu.tick();
        expect(eepromBackend.memory[15], equals(0x55));
        expect(cpu.data[EECR] & EEPE, equals(0));
        cpu.writeData(EECR, EERIE);
        cpu.tick();
        expect(cpu.pc, equals(0x2c)); // EEPROM Ready interrupt
      });

      test('should skip the write if EEMPE is clear', () {
        final cpu = CPU(Uint16List(0x1000));
        final eepromBackend = EEPROMMemoryBackend(1024);
        AVREEPROM(cpu, eepromBackend);
        cpu.writeData(EEDR, 0x55);
        cpu.writeData(EEARL, 15);
        cpu.writeData(EEARH, 0);
        cpu.writeData(EECR, EEMPE);
        cpu.cycles = 8; // waiting for more than 4 cycles should clear EEMPE
        cpu.tick();
        cpu.writeData(EECR, EEPE);
        cpu.tick();
        // Ensure that nothing was written, and EEPE bit is clear
        expect(cpu.cycles, equals(8));
        expect(eepromBackend.memory[15], equals(0xff));
        expect(cpu.data[EECR] & EEPE, equals(0));
      });

      test('should skip the write if another write is already in progress', () {
        final cpu = CPU(Uint16List(0x1000));
        final eepromBackend = EEPROMMemoryBackend(1024);
        AVREEPROM(cpu, eepromBackend);

        // Write 0x55 to address 15
        cpu.writeData(EEDR, 0x55);
        cpu.writeData(EEARL, 15);
        cpu.writeData(EEARH, 0);
        cpu.writeData(EECR, EEMPE);
        cpu.writeData(EECR, EEPE);
        cpu.tick();
        expect(cpu.cycles, equals(2));

        // Write 0x66 to address 16 (first write is still in progress)
        cpu.writeData(EEDR, 0x66);
        cpu.writeData(EEARL, 16);
        cpu.writeData(EEARH, 0);
        cpu.writeData(EECR, EEMPE);
        cpu.writeData(EECR, EEPE);
        cpu.tick();

        // Ensure that second write didn't happen
        expect(cpu.cycles, equals(2));
        expect(eepromBackend.memory[15], equals(0x55));
        expect(eepromBackend.memory[16], equals(0xff));
      });

      test('should write two bytes sucessfully', () {
        final cpu = CPU(Uint16List(0x1000));
        final eepromBackend = EEPROMMemoryBackend(1024);
        AVREEPROM(cpu, eepromBackend);

        // Write 0x55 to address 15
        cpu.writeData(EEDR, 0x55);
        cpu.writeData(EEARL, 15);
        cpu.writeData(EEARH, 0);
        cpu.writeData(EECR, EEMPE);
        cpu.writeData(EECR, EEPE);
        cpu.tick();
        expect(cpu.cycles, equals(2));

        // wait long enough time for the first write to finish
        cpu.cycles += 10000000;
        cpu.tick();

        // Write 0x66 to address 16
        cpu.writeData(EEDR, 0x66);
        cpu.writeData(EEARL, 16);
        cpu.writeData(EEARH, 0);
        cpu.writeData(EECR, EEMPE);
        cpu.writeData(EECR, EEPE);
        cpu.tick();

        // Ensure both writes took place
        expect(cpu.cycles, equals(10000004));
        expect(eepromBackend.memory[15], equals(0x55));
        expect(eepromBackend.memory[16], equals(0x66));
      });
    });
  });
}

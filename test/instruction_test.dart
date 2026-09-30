import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:avr8_dart/src/utils/assembler.dart';
import 'package:avr8_dart/src/cpu/cpu.dart';
import 'package:avr8_dart/src/cpu/instruction.dart';

const r0 = 0;
const r1 = 1;
const r2 = 2;
const r3 = 3;
const r4 = 4;
const r5 = 5;
const r6 = 6;
const r7 = 7;
const r8 = 8;
const r16 = 16;
const r17 = 17;
const r18 = 18;
const r19 = 19;
const r20 = 20;
const r21 = 21;
const r22 = 22;
const r23 = 23;
const r24 = 24;
const r26 = 26;
const r27 = 27;
const r28 = 28;
const r31 = 31;
const X = 26;
const Y = 28;
const Z = 30;
const RAMPZ = 0x5b;
const EIND = 0x5c;
const SP = 93;
const SPH = 94;
const SREG = 95;

const SREG_C = 0x01;
const SREG_Z = 0x02;
const SREG_N = 0x04;
const SREG_V = 0x08;
const SREG_S = 0x10;
const SREG_H = 0x20;
const SREG_I = 0x80;

void main() {
  group('avrInstruction', () {
    late CPU cpu;

    setUp(() {
      cpu = CPU(Uint16List(0x8000));
    });

    void loadProgram(List<String> instructions) {
      final res = assemble(instructions.join('\n'));
      if (res.errors.isNotEmpty) {
        throw Exception('Assembly failed: \${res.errors}');
      }
      cpu.progBytes.setAll(0, res.bytes);
    }

    test('should execute `ADC r0, r1` instruction when carry is on', () {
      loadProgram(['ADC r0, r1']);
      cpu.data[r0] = 10;
      cpu.data[r1] = 20;
      cpu.data[SREG] = SREG_C;
      avrInstruction(cpu);
      expect(cpu.pc, equals(1));
      expect(cpu.cycles, equals(1));
      expect(cpu.data[r0], equals(31));
      expect(cpu.data[SREG], equals(0));
    });

    test(
        'should execute `ADC r0, r1` instruction when carry is on and the result overflows',
        () {
      loadProgram(['ADC r0, r1']);
      cpu.data[r0] = 10;
      cpu.data[r1] = 245;
      cpu.data[SREG] = SREG_C;
      avrInstruction(cpu);
      expect(cpu.pc, equals(1));
      expect(cpu.cycles, equals(1));
      expect(cpu.data[r0], equals(0));
      expect(cpu.data[SREG], equals(SREG_H | SREG_Z | SREG_C));
    });

    test('should execute `ADD r0, r1` instruction when result overflows', () {
      loadProgram(['ADD r0, r1']);
      cpu.data[r0] = 11;
      cpu.data[r1] = 245;
      avrInstruction(cpu);
      expect(cpu.pc, equals(1));
      expect(cpu.cycles, equals(1));
      expect(cpu.data[r0], equals(0));
      expect(cpu.data[SREG], equals(SREG_H | SREG_Z | SREG_C));
    });

    test('should execute `ADD r0, r1` instruction when carry is on', () {
      loadProgram(['ADD r0, r1']);
      cpu.data[r0] = 11;
      cpu.data[r1] = 244;
      cpu.data[SREG] = SREG_C;
      avrInstruction(cpu);
      expect(cpu.pc, equals(1));
      expect(cpu.cycles, equals(1));
      expect(cpu.data[r0], equals(255));
      expect(cpu.data[SREG], equals(SREG_S | SREG_N));
    });

    test(
        'should execute `ADD r0, r1` instruction when carry is on and the result overflows',
        () {
      loadProgram(['ADD r0, r1']);
      cpu.data[r0] = 11;
      cpu.data[r1] = 245;
      cpu.data[SREG] = SREG_C;
      avrInstruction(cpu);
      expect(cpu.pc, equals(1));
      expect(cpu.cycles, equals(1));
      expect(cpu.data[r0], equals(0));
      expect(cpu.data[SREG], equals(SREG_H | SREG_Z | SREG_C));
    });

    test('should execute `BCLR 2` instruction', () {
      loadProgram(['BCLR 2']);
      cpu.data[SREG] = 0xff;
      avrInstruction(cpu);
      expect(cpu.pc, equals(1));
      expect(cpu.cycles, equals(1));
      expect(cpu.data[SREG], equals(0xfb));
    });

    test('should execute `BLD r4, 7` instruction', () {
      loadProgram(['BLD r4, 7']);
      cpu.data[r4] = 0x15;
      cpu.data[SREG] = 0x40;
      avrInstruction(cpu);
      expect(cpu.pc, equals(1));
      expect(cpu.cycles, equals(1));
      expect(cpu.data[r4], equals(0x95));
      expect(cpu.data[SREG], equals(0x40));
    });

    test('should execute `BRBC 0, +8` instruction when SREG.C is clear', () {
      loadProgram(['BRBC 0, +8']);
      cpu.data[SREG] = SREG_V;
      avrInstruction(cpu);
      expect(cpu.pc, equals(1 + 8 ~/ 2));
      expect(cpu.cycles, equals(2));
    });

    test('should execute `BRBC 0, +8` instruction when SREG.C is set', () {
      loadProgram(['BRBC 0, +8']);
      cpu.data[SREG] = SREG_C;
      avrInstruction(cpu);
      expect(cpu.pc, equals(1));
      expect(cpu.cycles, equals(1));
    });

    test('should execute `BRBS 3, 92` instruction when SREG.V is set', () {
      loadProgram(['BRBS 3, 92']);
      cpu.data[SREG] = SREG_V;
      avrInstruction(cpu);
      expect(cpu.pc, equals(1 + 92 ~/ 2));
      expect(cpu.cycles, equals(2));
    });

    test('should execute `BRBS 3, -4` instruction when SREG.V is set', () {
      loadProgram(['BRBS 3, -4']);
      cpu.data[SREG] = SREG_V;
      avrInstruction(cpu);
      avrInstruction(cpu);
      expect(cpu.pc, equals(0));
      expect(cpu.cycles, equals(3));
    });

    test('should execute `BRBS 3, -4` instruction when SREG.V is clear', () {
      loadProgram(['BRBS 3, -4']);
      cpu.data[SREG] = 0x0;
      avrInstruction(cpu);
      expect(cpu.pc, equals(1));
      expect(cpu.cycles, equals(1));
    });

    test('should execute `CALL` instruction', () {
      loadProgram(['CALL 0xb8']);
      cpu.data[SPH] = 0;
      cpu.data[SP] = 150;
      avrInstruction(cpu);
      expect(cpu.pc, equals(0x5c));
      expect(cpu.cycles, equals(4));
      expect(cpu.data[150], equals(2));
      expect(cpu.data[SP], equals(148));
    });

    test(
        'should push 3-byte return address when executing `CALL` instruction on device with >128k flash',
        () {
      cpu = CPU(Uint16List(0x20000));
      loadProgram(['CALL 0xb8']);
      cpu.data[SPH] = 0;
      cpu.data[SP] = 150;
      avrInstruction(cpu);
      expect(cpu.pc, equals(0x5c));
      expect(cpu.cycles, equals(5));
      expect(cpu.data[150], equals(2));
      expect(cpu.data[SP], equals(147));
    });

    test('should execute `CBI 0x0c, 5`', () {
      loadProgram(['CBI 0x0c, 5']);
      cpu.data[0x2c] = 0xFF;
      avrInstruction(cpu);
      expect(cpu.pc, equals(1));
      expect(cpu.cycles, equals(1));
      expect(cpu.data[0x2c], equals(0xDF));
    });

    test(
        'should execute `CP r28, r16` and leave V clear when nothing overflows',
        () {
      // 0x23 - 0x27: negative and borrowing, but no signed overflow. V used to
      // be set on every CP (a bool compared with 0), so S came out wrong and
      // every signed branch after a CP went the other way — which is how
      // avr-libc's isinf() said "inf" for 1.5 and Serial.print(1.5) printed it.
      loadProgram(['CP r28, r16']);
      cpu.data[r28] = 0x23;
      cpu.data[r16] = 0x27;
      cpu.data[SREG] = SREG_I;
      avrInstruction(cpu);
      expect(cpu.pc, equals(1));
      expect(cpu.cycles, equals(1));
      // H is left out: it is not what this pins, and this port derives it from
      // a different bit than the hardware does.
      expect(
          cpu.data[SREG] & ~SREG_H, equals(SREG_I | SREG_S | SREG_N | SREG_C));
    });

    test('should execute `CP r28, r16` and set V on signed overflow', () {
      // 0x80 - 0x01 = 0x7F: -128 - 1 overflows.
      loadProgram(['CP r28, r16']);
      cpu.data[r28] = 0x80;
      cpu.data[r16] = 0x01;
      avrInstruction(cpu);
      expect(cpu.data[SREG] & ~SREG_H, equals(SREG_V | SREG_S));
    });

    test('should execute `CPC r27, r18` instruction', () {
      loadProgram(['CPC r27, r18']);
      cpu.data[r18] = 0x1;
      cpu.data[r27] = 0x1;
      avrInstruction(cpu);
      expect(cpu.pc, equals(1));
      expect(cpu.cycles, equals(1));
      expect(cpu.data[SREG], equals(0));
    });

    test('should execute `CPC r24, r1` instruction and set', () {
      loadProgram(['CPC r24, r1']);
      cpu.data[r1] = 0;
      cpu.data[r24] = 0;
      cpu.data[SREG] = SREG_I | SREG_C;
      avrInstruction(cpu);
      expect(cpu.pc, equals(1));
      expect(cpu.cycles, equals(1));
      expect(
          cpu.data[SREG], equals(SREG_I | SREG_H | SREG_S | SREG_N | SREG_C));
    });

    test('should execute `CPI r26, 0x9` instruction', () {
      loadProgram(['CPI r26, 0x9']);
      cpu.data[r26] = 0x8;
      avrInstruction(cpu);
      expect(cpu.pc, equals(1));
      expect(cpu.cycles, equals(1));
      expect(cpu.data[SREG], equals(SREG_H | SREG_S | SREG_N | SREG_C));
    });

    test('should execute `CPSE r2, r3` when r2 != r3', () {
      loadProgram(['CPSE r2, r3']);
      cpu.data[r2] = 10;
      cpu.data[r3] = 11;
      avrInstruction(cpu);
      expect(cpu.pc, equals(1));
      expect(cpu.cycles, equals(1));
    });

    test('should execute `CPSE r2, r3` when r2 == r3', () {
      loadProgram(['CPSE r2, r3']);
      cpu.data[r2] = 10;
      cpu.data[r3] = 10;
      avrInstruction(cpu);
      expect(cpu.pc, equals(2));
      expect(cpu.cycles, equals(2));
    });

    test(
        'should execute `CPSE r2, r3` when r2 == r3 and followed by 2-word instruction',
        () {
      loadProgram(['CPSE r2, r3', 'CALL 8']);
      cpu.data[r2] = 10;
      cpu.data[r3] = 10;
      avrInstruction(cpu);
      expect(cpu.pc, equals(3));
      expect(cpu.cycles, equals(3));
    });

    test('should execute `EICALL` instruction', () {
      cpu = CPU(Uint16List(0x20000));
      loadProgram(['EICALL']);
      cpu.data[SPH] = 0;
      cpu.data[SP] = 0x80;
      cpu.data[EIND] = 1;
      cpu.dataView.setUint16(Z, 0x1234, Endian.little);
      avrInstruction(cpu);
      expect(cpu.pc, equals(0x11234));
      expect(cpu.cycles, equals(4));
      expect(cpu.data[SP], equals(0x80 - 3));
      expect(cpu.data[0x80], equals(1));
    });

    test('should execute `EIJMP` instruction', () {
      cpu = CPU(Uint16List(0x20000));
      loadProgram(['EIJMP']);
      cpu.data[EIND] = 1;
      cpu.dataView.setUint16(Z, 0x1040, Endian.little);
      avrInstruction(cpu);
      expect(cpu.pc, equals(0x11040));
      expect(cpu.cycles, equals(2));
    });

    test('should execute `ELPM` instruction', () {
      cpu = CPU(Uint16List(0x20000));
      loadProgram(['ELPM']);
      cpu.data[Z] = 0x50;
      cpu.data[RAMPZ] = 0x2;
      cpu.progBytes[0x20050] = 0x62;
      avrInstruction(cpu);
      expect(cpu.data[r0], equals(0x62));
      expect(cpu.pc, equals(1));
      expect(cpu.cycles, equals(3));
    });

    test('should execute `ELPM r5, Z` instruction', () {
      cpu = CPU(Uint16List(0x20000));
      loadProgram(['ELPM r5, Z']);
      cpu.data[Z] = 0x11;
      cpu.data[RAMPZ] = 0x1;
      cpu.progBytes[0x10011] = 0x99;
      avrInstruction(cpu);
      expect(cpu.data[r5], equals(0x99));
      expect(cpu.pc, equals(1));
      expect(cpu.cycles, equals(3));
    });

    test('should execute `ELPM r6, Z+` instruction', () {
      cpu = CPU(Uint16List(0x20000));
      loadProgram(['ELPM r6, Z+']);
      cpu.dataView.setUint16(Z, 0xffff, Endian.little);
      cpu.data[RAMPZ] = 0x2;
      cpu.progBytes[0x2ffff] = 0x22;
      avrInstruction(cpu);
      expect(cpu.pc, equals(1));
      expect(cpu.cycles, equals(3));
      expect(cpu.data[r6], equals(0x22));
      expect(cpu.dataView.getUint16(Z, Endian.little), equals(0x0));
      expect(cpu.data[RAMPZ], equals(3));
    });

    test('should clamp RAMPZ when executing `ELPM r6, Z+` instruction', () {
      cpu = CPU(Uint16List(0x20000));
      loadProgram(['ELPM r6, Z+']);
      cpu.dataView.setUint16(Z, 0xffff, Endian.little);
      cpu.data[RAMPZ] = 0x3;
      avrInstruction(cpu);
      expect(cpu.data[RAMPZ], equals(0x0));
    });

    test('should execute `ICALL` instruction', () {
      loadProgram(['ICALL']);
      cpu.data[SPH] = 0;
      cpu.data[SP] = 0x80;
      cpu.dataView.setUint16(Z, 0x2020, Endian.little);
      avrInstruction(cpu);
      expect(cpu.cycles, equals(3));
      expect(cpu.pc, equals(0x2020));
      expect(cpu.data[0x80], equals(1));
      expect(cpu.data[SP], equals(0x7e));
    });

    test(
        'should push 3-byte return address when executing `ICALL` instruction on device with >128k flash',
        () {
      cpu = CPU(Uint16List(0x20000));
      loadProgram(['ICALL']);
      cpu.data[SPH] = 0;
      cpu.data[SP] = 0x80;
      cpu.dataView.setUint16(Z, 0x2020, Endian.little);
      avrInstruction(cpu);
      expect(cpu.cycles, equals(4));
      expect(cpu.pc, equals(0x2020));
      expect(cpu.data[0x80], equals(1));
      expect(cpu.data[SP], equals(0x7d));
    });

    test('should execute `IJMP` instruction', () {
      loadProgram(['IJMP']);
      cpu.dataView.setUint16(Z, 0x1040, Endian.little);
      avrInstruction(cpu);
      expect(cpu.cycles, equals(2));
      expect(cpu.pc, equals(0x1040));
    });

    test('should execute `IN r5, 0xb` instruction', () {
      loadProgram(['IN r5, 0xb']);
      cpu.data[0x2b] = 0xaf;
      avrInstruction(cpu);
      expect(cpu.cycles, equals(1));
      expect(cpu.pc, equals(1));
      expect(cpu.data[r5], equals(0xaf));
    });

    test('should execute `INC r5` instruction', () {
      loadProgram(['INC r5']);
      cpu.data[r5] = 0x7f;
      avrInstruction(cpu);
      expect(cpu.data[r5], equals(0x80));
      expect(cpu.pc, equals(1));
      expect(cpu.cycles, equals(1));
      expect(cpu.data[SREG], equals(SREG_N | SREG_V));
    });

    test('should execute `INC r5` instruction when r5 == 0xff', () {
      loadProgram(['INC r5']);
      cpu.data[r5] = 0xff;
      avrInstruction(cpu);
      expect(cpu.data[r5], equals(0));
      expect(cpu.pc, equals(1));
      expect(cpu.cycles, equals(1));
      expect(cpu.data[SREG], equals(SREG_Z));
    });

    test('should execute `JMP 0xb8` instruction', () {
      loadProgram(['JMP 0xb8']);
      avrInstruction(cpu);
      expect(cpu.pc, equals(0x5c));
      expect(cpu.cycles, equals(3));
    });

    test('should execute `LAC Z, r19` instruction', () {
      loadProgram(['LAC Z, r19']);
      cpu.data[r19] = 0x02;
      cpu.dataView.setUint16(Z, 0x100, Endian.little);
      cpu.data[0x100] = 0x96;
      avrInstruction(cpu);
      expect(cpu.pc, equals(1));
      expect(cpu.cycles, equals(1));
      expect(cpu.data[r19], equals(0x96));
      expect(cpu.dataView.getUint16(Z, Endian.little), equals(0x100));
      expect(cpu.data[0x100], equals(0x94));
    });

    test('should execute `LAS Z, r17` instruction', () {
      loadProgram(['LAS Z, r17']);
      cpu.data[r17] = 0x11;
      cpu.data[Z] = 0x80;
      cpu.data[0x80] = 0x44;
      avrInstruction(cpu);
      expect(cpu.pc, equals(1));
      expect(cpu.cycles, equals(1));
      expect(cpu.data[r17], equals(0x44));
      expect(cpu.data[Z], equals(0x80));
      expect(cpu.data[0x80], equals(0x55));
    });

    test('should execute `LAT Z, r0` instruction', () {
      loadProgram(['LAT Z, r0']);
      cpu.data[r0] = 0x33;
      cpu.data[Z] = 0x80;
      cpu.data[0x80] = 0x66;
      avrInstruction(cpu);
      expect(cpu.pc, equals(1));
      expect(cpu.cycles, equals(1));
      expect(cpu.data[r0], equals(0x66));
      expect(cpu.data[Z], equals(0x80));
      expect(cpu.data[0x80], equals(0x55));
    });

    test('should execute `LD r1, X` instruction', () {
      loadProgram(['LD r1, X']);
      cpu.data[0xc0] = 0x15;
      cpu.data[X] = 0xc0;
      avrInstruction(cpu);
      expect(cpu.pc, equals(1));
      expect(cpu.cycles, equals(2));
      expect(cpu.data[r1], equals(0x15));
      expect(cpu.data[X], equals(0xc0));
    });

    test('should execute `LD r17, X+` instruction', () {
      loadProgram(['LD r17, X+']);
      cpu.data[0xc0] = 0x15;
      cpu.data[X] = 0xc0;
      avrInstruction(cpu);
      expect(cpu.pc, equals(1));
      expect(cpu.cycles, equals(2));
      expect(cpu.data[r17], equals(0x15));
      expect(cpu.data[X], equals(0xc1));
    });

    test('should execute `LD r1, -X` instruction', () {
      loadProgram(['LD r1, -X']);
      cpu.data[0x98] = 0x22;
      cpu.data[X] = 0x99;
      avrInstruction(cpu);
      expect(cpu.pc, equals(1));
      expect(cpu.cycles, equals(2));
      expect(cpu.data[r1], equals(0x22));
      expect(cpu.data[X], equals(0x98));
    });

    test('should execute `LD r8, Y` instruction', () {
      loadProgram(['LD r8, Y']);
      cpu.data[0xc0] = 0x15;
      cpu.data[Y] = 0xc0;
      avrInstruction(cpu);
      expect(cpu.pc, equals(1));
      expect(cpu.cycles, equals(2));
      expect(cpu.data[8], equals(0x15));
      expect(cpu.data[Y], equals(0xc0));
    });

    test('should execute `LD r3, Y+` instruction', () {
      loadProgram(['LD r3, Y+']);
      cpu.data[0xc0] = 0x15;
      cpu.data[Y] = 0xc0;
      avrInstruction(cpu);
      expect(cpu.pc, equals(1));
      expect(cpu.cycles, equals(2));
      expect(cpu.data[r3], equals(0x15));
      expect(cpu.data[Y], equals(0xc1));
    });

    test('should execute `LD r0, -Y` instruction', () {
      loadProgram(['LD r0, -Y']);
      cpu.data[0x98] = 0x22;
      cpu.data[Y] = 0x99;
      avrInstruction(cpu);
      expect(cpu.pc, equals(1));
      expect(cpu.cycles, equals(2));
      expect(cpu.data[r0], equals(0x22));
      expect(cpu.data[Y], equals(0x98));
    });

    test('should execute `LDD r4, Y+2` instruction', () {
      loadProgram(['LDD r4, Y+2']);
      cpu.data[0x82] = 0x33;
      cpu.data[Y] = 0x80;
      avrInstruction(cpu);
      expect(cpu.pc, equals(1));
      expect(cpu.cycles, equals(2));
      expect(cpu.data[r4], equals(0x33));
      expect(cpu.data[Y], equals(0x80));
    });

    test('should execute `LD r5, Z` instruction', () {
      loadProgram(['LD r5, Z']);
      cpu.data[0xcc] = 0xf5;
      cpu.data[Z] = 0xcc;
      avrInstruction(cpu);
      expect(cpu.pc, equals(1));
      expect(cpu.cycles, equals(2));
      expect(cpu.data[r5], equals(0xf5));
      expect(cpu.data[Z], equals(0xcc));
    });

    test('should execute `LD r7, Z+` instruction', () {
      loadProgram(['LD r7, Z+']);
      cpu.data[0xc0] = 0x25;
      cpu.data[Z] = 0xc0;
      avrInstruction(cpu);
      expect(cpu.pc, equals(1));
      expect(cpu.cycles, equals(2));
      expect(cpu.data[r7], equals(0x25));
      expect(cpu.data[Z], equals(0xc1));
    });

    test('should execute `LD r0, -Z` instruction', () {
      loadProgram(['LD r0, -Z']);
      cpu.data[0x9e] = 0x66;
      cpu.data[Z] = 0x9f;
      avrInstruction(cpu);
      expect(cpu.pc, equals(1));
      expect(cpu.cycles, equals(2));
      expect(cpu.data[r0], equals(0x66));
      expect(cpu.data[Z], equals(0x9e));
    });

    test('should execute `LDD r15, Z+31` instruction', () {
      loadProgram(['LDD r15, Z+31']);
      cpu.data[0x9f] = 0x33;
      cpu.data[Z] = 0x80;
      avrInstruction(cpu);
      expect(cpu.pc, equals(1));
      expect(cpu.cycles, equals(2));
      expect(cpu.data[15], equals(0x33));
      expect(cpu.data[Z], equals(0x80));
    });

    test('should execute `LDI r28, 0xff` instruction', () {
      loadProgram(['LDI r28, 0xff']);
      avrInstruction(cpu);
      expect(cpu.pc, equals(0x1));
      expect(cpu.cycles, equals(1));
      expect(cpu.data[Y], equals(0xff));
    });

    test('should execute `LDS r5, 0x150` instruction', () {
      loadProgram(['LDS r5, 0x150']);
      cpu.data[0x150] = 0x7a;
      avrInstruction(cpu);
      expect(cpu.pc, equals(0x2));
      expect(cpu.cycles, equals(2));
      expect(cpu.data[r5], equals(0x7a));
    });

    test('should execute `LPM` instruction', () {
      loadProgram(['LPM']);
      cpu.progMem[0x40] = 0xa0;
      cpu.data[Z] = 0x80;
      avrInstruction(cpu);
      expect(cpu.pc, equals(1));
      expect(cpu.cycles, equals(3));
      expect(cpu.data[r0], equals(0xa0));
      expect(cpu.data[Z], equals(0x80));
    });

    test('should execute `LPM r2, Z` instruction', () {
      loadProgram(['LPM r2, Z']);
      cpu.progMem[0x40] = 0xa0;
      cpu.data[Z] = 0x80;
      avrInstruction(cpu);
      expect(cpu.pc, equals(1));
      expect(cpu.cycles, equals(3));
      expect(cpu.data[r2], equals(0xa0));
      expect(cpu.data[Z], equals(0x80));
    });

    test('should execute `LPM r1, Z+` instruction', () {
      loadProgram(['LPM r1, Z+']);
      cpu.progMem[0x40] = 0xa0;
      cpu.data[Z] = 0x80;
      avrInstruction(cpu);
      expect(cpu.pc, equals(1));
      expect(cpu.cycles, equals(3));
      expect(cpu.data[r1], equals(0xa0));
      expect(cpu.data[Z], equals(0x81));
    });

    test('should execute `LSR r7` instruction', () {
      loadProgram(['LSR r7']);
      cpu.data[r7] = 0x45;
      avrInstruction(cpu);
      expect(cpu.pc, equals(1));
      expect(cpu.cycles, equals(1));
      expect(cpu.data[r7], equals(0x22));
      expect(cpu.data[SREG], equals(SREG_S | SREG_V | SREG_C));
    });

    test('should execute `MOV r7, r8` instruction', () {
      loadProgram(['MOV r7, r8']);
      cpu.data[r8] = 0x45;
      avrInstruction(cpu);
      expect(cpu.pc, equals(1));
      expect(cpu.cycles, equals(1));
      expect(cpu.data[r7], equals(0x45));
    });

    test('should execute `MOVW r26, r22` instruction', () {
      loadProgram(['MOVW r26, r22']);
      cpu.data[r22] = 0x45;
      cpu.data[r23] = 0x9a;
      avrInstruction(cpu);
      expect(cpu.pc, equals(1));
      expect(cpu.cycles, equals(1));
      expect(cpu.data[X], equals(0x45));
      expect(cpu.data[r27], equals(0x9a));
    });

    test('should execute `MUL r5, r6` instruction', () {
      loadProgram(['MUL r5, r6']);
      cpu.data[r5] = 100;
      cpu.data[r6] = 5;
      avrInstruction(cpu);
      expect(cpu.pc, equals(1));
      expect(cpu.cycles, equals(2));
      expect(cpu.dataView.getUint16(0, Endian.little), equals(500));
      expect(cpu.data[SREG], equals(0));
    });

    test(
        'should execute `MUL r5, r6` instruction and update carry flag when numbers are big',
        () {
      loadProgram(['MUL r5, r6']);
      cpu.data[r5] = 200;
      cpu.data[r6] = 200;
      avrInstruction(cpu);
      expect(cpu.pc, equals(1));
      expect(cpu.cycles, equals(2));
      expect(cpu.dataView.getUint16(0, Endian.little), equals(40000));
      expect(cpu.data[SREG], equals(SREG_C));
    });

    test('should execute `MUL r0, r1` and update the zero flag', () {
      loadProgram(['MUL r0, r1']);
      cpu.data[r0] = 0;
      cpu.data[r1] = 9;
      avrInstruction(cpu);
      expect(cpu.pc, equals(1));
      expect(cpu.cycles, equals(2));
      expect(cpu.dataView.getUint16(0, Endian.little), equals(0));
      expect(cpu.data[SREG], equals(SREG_Z));
    });

    test('should execute `MULS r18, r19` instruction', () {
      loadProgram(['MULS r18, r19']);
      cpu.data[r18] = -5 & 0xFF;
      cpu.data[r19] = 100;
      avrInstruction(cpu);
      expect(cpu.pc, equals(1));
      expect(cpu.cycles, equals(2));
      expect(cpu.dataView.getInt16(0, Endian.little), equals(-500));
      expect(cpu.data[SREG], equals(SREG_C));
    });

    test('should execute `MULSU r16, r17` instruction', () {
      loadProgram(['MULSU r16, r17']);
      cpu.data[r16] = -5 & 0xFF;
      cpu.data[r17] = 200;
      avrInstruction(cpu);
      expect(cpu.pc, equals(1));
      expect(cpu.cycles, equals(2));
      expect(cpu.dataView.getInt16(0, Endian.little), equals(-1000));
      expect(cpu.data[SREG], equals(SREG_C));
    });

    test('should execute `NEG r20` instruction', () {
      loadProgram(['NEG r20']);
      cpu.data[r20] = 0x56;
      avrInstruction(cpu);
      expect(cpu.pc, equals(1));
      expect(cpu.cycles, equals(1));
      expect(cpu.data[20], equals(0xaa));
      expect(cpu.data[SREG], equals(SREG_S | SREG_N | SREG_C));
    });

    test('should execute `NOP` instruction', () {
      loadProgram(['NOP']);
      avrInstruction(cpu);
      expect(cpu.pc, equals(1));
      expect(cpu.cycles, equals(1));
    });

    test('should execute `OUT 0x3f, r1` instruction', () {
      loadProgram(['OUT 0x3f, r1']);
      cpu.data[r1] = 0x5a;
      avrInstruction(cpu);
      expect(cpu.pc, equals(0x1));
      expect(cpu.cycles, equals(1));
      expect(cpu.data[0x5f], equals(0x5a));
    });

    test('should execute `POP r26` instruction', () {
      loadProgram(['POP r26']);
      cpu.data[SPH] = 0;
      cpu.data[SP] = 0xff;
      cpu.data[0x100] = 0x1a;
      avrInstruction(cpu);
      expect(cpu.pc, equals(0x1));
      expect(cpu.cycles, equals(2));
      expect(cpu.data[X], equals(0x1a));
      expect(cpu.dataView.getUint16(SP, Endian.little), equals(0x100));
    });

    test('should execute `PUSH r11` instruction', () {
      loadProgram(['PUSH r11']);
      cpu.data[11] = 0x2a;
      cpu.data[SPH] = 0;
      cpu.data[SP] = 0xff;
      avrInstruction(cpu);
      expect(cpu.pc, equals(0x1));
      expect(cpu.cycles, equals(2));
      expect(cpu.data[0xff], equals(0x2a));
      expect(cpu.dataView.getUint16(SP, Endian.little), equals(0xfe));
    });

    test('should execute `RCALL .+6` instruction', () {
      loadProgram(['RCALL 6']);
      cpu.data[SPH] = 0;
      cpu.data[SP] = 0x80;
      avrInstruction(cpu);
      expect(cpu.pc, equals(4));
      expect(cpu.cycles, equals(3));
      expect(cpu.dataView.getUint16(0x80, Endian.little), equals(1));
      expect(cpu.data[SP], equals(0x7e));
    });

    test('should execute `RCALL .-4` instruction', () {
      loadProgram(['NOP', 'RCALL -4']);
      cpu.data[SPH] = 0;
      cpu.data[SP] = 0x80;
      avrInstruction(cpu);
      avrInstruction(cpu);
      expect(cpu.pc, equals(0));
      expect(cpu.cycles, equals(4));
      expect(cpu.dataView.getUint16(0x80, Endian.little), equals(2));
      expect(cpu.data[SP], equals(0x7e));
    });

    test(
        'should push 3-byte return address when executing `RCALL` instruction on device with >128k flash',
        () {
      cpu = CPU(Uint16List(0x20000));
      loadProgram(['RCALL 6']);
      cpu.data[SPH] = 0;
      cpu.data[SP] = 0x80;
      cpu.dataView.setUint16(Z, 0x2020, Endian.little);
      avrInstruction(cpu);
      expect(cpu.pc, equals(4));
      expect(cpu.cycles, equals(4));
      expect(cpu.dataView.getUint16(0x80, Endian.little), equals(1));
      expect(cpu.data[SP], equals(0x7d));
    });

    test('should execute `RET` instruction', () {
      loadProgram(['RET']);
      cpu.data[SPH] = 0;
      cpu.data[SP] = 0x90;
      cpu.data[0x92] = 16;
      avrInstruction(cpu);
      expect(cpu.pc, equals(16));
      expect(cpu.cycles, equals(4));
      expect(cpu.data[SP], equals(0x92));
    });

    test('should execute `RET` instruction on device with >128k flash', () {
      cpu = CPU(Uint16List(0x20000));
      loadProgram(['RET']);
      cpu.data[SPH] = 0;
      cpu.data[SP] = 0x90;
      cpu.data[0x91] = 0x1;
      cpu.data[0x93] = 0x16;
      avrInstruction(cpu);
      expect(cpu.pc, equals(0x10016));
      expect(cpu.cycles, equals(5));
      expect(cpu.data[SP], equals(0x93));
    });

    test('should execute `RETI` instruction', () {
      loadProgram(['RETI']);
      cpu.data[SPH] = 0;
      cpu.data[SP] = 0xc0;
      cpu.data[0xc2] = 200;
      avrInstruction(cpu);
      expect(cpu.pc, equals(200));
      expect(cpu.cycles, equals(4));
      expect(cpu.data[SP], equals(0xc2));
      expect(cpu.data[SREG], equals(SREG_I));
    });

    test('should execute `RETI` instruction on device with >128k flash', () {
      cpu = CPU(Uint16List(0x20000));
      loadProgram(['RETI']);
      cpu.data[SPH] = 0;
      cpu.data[SP] = 0xc0;
      cpu.data[0xc1] = 0x1;
      cpu.data[0xc3] = 0x30;
      avrInstruction(cpu);
      expect(cpu.pc, equals(0x10030));
      expect(cpu.cycles, equals(5));
      expect(cpu.data[SP], equals(0xc3));
      expect(cpu.data[SREG], equals(SREG_I));
    });

    test('should execute `RJMP 2` instruction', () {
      loadProgram(['RJMP 2']);
      avrInstruction(cpu);
      expect(cpu.pc, equals(2));
      expect(cpu.cycles, equals(2));
    });

    test('should execute `ROR r0` instruction', () {
      loadProgram(['ROR r0']);
      cpu.data[r0] = 0x11;
      avrInstruction(cpu);
      expect(cpu.pc, equals(1));
      expect(cpu.cycles, equals(1));
      expect(cpu.data[r0], equals(0x08));
      expect(cpu.data[SREG], equals(SREG_S | SREG_V | SREG_C));
    });

    test(
        'should execute `SBC r0, r1` instruction when carry is on and result overflows',
        () {
      loadProgram(['SBC r0, r1']);
      cpu.data[r0] = 0;
      cpu.data[r1] = 10;
      cpu.data[95] = SREG_C;
      avrInstruction(cpu);
      expect(cpu.pc, equals(1));
      expect(cpu.cycles, equals(1));
      expect(cpu.data[r0], equals(245));
      expect(cpu.data[SREG], equals(SREG_H | SREG_S | SREG_N | SREG_C));
    });

    test('should execute `SBCI r23, 3`', () {
      loadProgram(['SBCI r23, 3']);
      cpu.data[r23] = 3;
      cpu.data[SREG] = SREG_I | SREG_C;
      avrInstruction(cpu);
      expect(cpu.pc, equals(1));
      expect(cpu.cycles, equals(1));
      expect(
          cpu.data[SREG], equals(SREG_I | SREG_H | SREG_S | SREG_N | SREG_C));
    });

    test('should execute `SBI 0x0c, 5`', () {
      loadProgram(['SBI 0x0c, 5']);
      cpu.data[0x2c] = 0x0F;
      avrInstruction(cpu);
      expect(cpu.pc, equals(1));
      expect(cpu.cycles, equals(2));
      expect(cpu.data[0x2c], equals(0x2F));
    });

    test('should execute `SBIS 0x0c, 5` when bit is clear', () {
      loadProgram(['SBIS 0x0c, 5']);
      cpu.data[0x2c] = 0x0F;
      avrInstruction(cpu);
      expect(cpu.pc, equals(1));
      expect(cpu.cycles, equals(1));
    });

    test('should execute `SBIS 0x0c, 5` when bit is set', () {
      loadProgram(['SBIS 0x0c, 5']);
      cpu.data[0x2c] = 0x2F;
      avrInstruction(cpu);
      expect(cpu.pc, equals(2));
      expect(cpu.cycles, equals(2));
    });

    test(
        'should execute `SBIS 0x0c, 5` when bit is set and followed by 2-word instruction',
        () {
      loadProgram(['SBIS 0x0c, 5', 'CALL 0xb8']);
      cpu.data[0x2c] = 0x2F;
      avrInstruction(cpu);
      expect(cpu.pc, equals(3));
      expect(cpu.cycles, equals(3));
    });

    test('should execute `ST X, r1` instruction', () {
      loadProgram(['ST X, r1']);
      cpu.data[r1] = 0x5a;
      cpu.data[X] = 0x9a;
      avrInstruction(cpu);
      expect(cpu.pc, equals(1));
      expect(cpu.cycles, equals(2));
      expect(cpu.data[0x9a], equals(0x5a));
      expect(cpu.data[X], equals(0x9a));
    });

    test('should execute `ST X+, r1` instruction', () {
      loadProgram(['ST X+, r1']);
      cpu.data[r1] = 0x5a;
      cpu.data[X] = 0x9a;
      avrInstruction(cpu);
      expect(cpu.pc, equals(1));
      expect(cpu.cycles, equals(2));
      expect(cpu.data[0x9a], equals(0x5a));
      expect(cpu.data[X], equals(0x9b));
    });

    test('should execute `ST -X, r17` instruction', () {
      loadProgram(['ST -X, r17']);
      cpu.data[r17] = 0x88;
      cpu.data[X] = 0x99;
      avrInstruction(cpu);
      expect(cpu.pc, equals(1));
      expect(cpu.cycles, equals(2));
      expect(cpu.data[0x98], equals(0x88));
      expect(cpu.data[X], equals(0x98));
    });

    test('should execute `ST Y, r2` instruction', () {
      loadProgram(['ST Y, r2']);
      cpu.data[r2] = 0x5b;
      cpu.data[Y] = 0x9a;
      avrInstruction(cpu);
      expect(cpu.pc, equals(1));
      expect(cpu.cycles, equals(2));
      expect(cpu.data[0x9a], equals(0x5b));
      expect(cpu.data[Y], equals(0x9a));
    });

    test('should execute `ST Y+, r1` instruction', () {
      loadProgram(['ST Y+, r1']);
      cpu.data[r1] = 0x5a;
      cpu.data[Y] = 0x9a;
      avrInstruction(cpu);
      expect(cpu.pc, equals(1));
      expect(cpu.cycles, equals(2));
      expect(cpu.data[0x9a], equals(0x5a));
      expect(cpu.data[Y], equals(0x9b));
    });

    test('should execute `ST -Y, r1` instruction', () {
      loadProgram(['ST -Y, r1']);
      cpu.data[r1] = 0x5a;
      cpu.data[Y] = 0x9a;
      avrInstruction(cpu);
      expect(cpu.pc, equals(1));
      expect(cpu.cycles, equals(2));
      expect(cpu.data[0x99], equals(0x5a));
      expect(cpu.data[Y], equals(0x99));
    });

    test('should execute `STD Y+17, r0` instruction', () {
      loadProgram(['STD Y+17, r0']);
      cpu.data[r0] = 0xba;
      cpu.data[Y] = 0x9a;
      avrInstruction(cpu);
      expect(cpu.pc, equals(1));
      expect(cpu.cycles, equals(2));
      expect(cpu.data[0x9a + 17], equals(0xba));
      expect(cpu.data[Y], equals(0x9a));
    });

    test('should execute `ST Z, r16` instruction', () {
      loadProgram(['ST Z, r16']);
      cpu.data[r16] = 0xdf;
      cpu.data[Z] = 0x40;
      avrInstruction(cpu);
      expect(cpu.pc, equals(1));
      expect(cpu.cycles, equals(2));
      expect(cpu.data[0x40], equals(0xdf));
      expect(cpu.data[Z], equals(0x40));
    });

    test('should execute `ST Z+, r0` instruction', () {
      loadProgram(['ST Z+, r0']);
      cpu.data[r0] = 0x55;
      cpu.dataView.setUint16(Z, 0x155, Endian.little);
      avrInstruction(cpu);
      expect(cpu.pc, equals(1));
      expect(cpu.cycles, equals(2));
      expect(cpu.data[0x155], equals(0x55));
      expect(cpu.dataView.getUint16(Z, Endian.little), equals(0x156));
    });

    test('should execute `ST -Z, r16` instruction', () {
      loadProgram(['ST -Z, r16']);
      cpu.data[r16] = 0x5a;
      cpu.data[Z] = 0xff;
      avrInstruction(cpu);
      expect(cpu.pc, equals(1));
      expect(cpu.cycles, equals(2));
      expect(cpu.data[0xfe], equals(0x5a));
      expect(cpu.data[Z], equals(0xfe));
    });

    test('should execute `STD Z+1, r0` instruction', () {
      loadProgram(['STD Z+1, r0']);
      cpu.data[r0] = 0xcc;
      cpu.data[Z] = 0x50;
      avrInstruction(cpu);
      expect(cpu.pc, equals(1));
      expect(cpu.cycles, equals(2));
      expect(cpu.data[0x51], equals(0xcc));
      expect(cpu.data[Z], equals(0x50));
    });

    test('should execute `STS 0x151, r31` instruction', () {
      loadProgram(['STS 0x151, r31']);
      cpu.data[r31] = 0x80;
      avrInstruction(cpu);
      expect(cpu.pc, equals(2));
      expect(cpu.cycles, equals(2));
      expect(cpu.data[0x151], equals(0x80));
    });

    test('should execute `SUB r0, r1` instruction when result overflows', () {
      loadProgram(['SUB r0, r1']);
      cpu.data[r0] = 0;
      cpu.data[r1] = 10;
      avrInstruction(cpu);
      expect(cpu.pc, equals(1));
      expect(cpu.cycles, equals(1));
      expect(cpu.data[r0], equals(246));
      expect(cpu.data[SREG], equals(SREG_S | SREG_N | SREG_C));
    });

    test('should execute `SWAP r1` instruction', () {
      loadProgram(['SWAP r1']);
      cpu.data[r1] = 0xa5;
      avrInstruction(cpu);
      expect(cpu.pc, equals(1));
      expect(cpu.cycles, equals(1));
      expect(cpu.data[r1], equals(0x5a));
    });

    test('should execute `WDR` instruction and call `cpu.onWatchdogReset`', () {
      loadProgram(['WDR']);
      bool called = false;
      cpu.onWatchdogReset = () {
        called = true;
      };
      expect(called, isFalse);
      avrInstruction(cpu);
      expect(called, isTrue);
    });

    test('should execute `XCH Z, r21` instruction', () {
      loadProgram(['XCH Z, r21']);
      cpu.data[r21] = 0xa1;
      cpu.data[Z] = 0x50;
      cpu.data[0x50] = 0xb9;
      avrInstruction(cpu);
      expect(cpu.pc, equals(1));
      expect(cpu.cycles, equals(1));
      expect(cpu.data[r21], equals(0xb9));
      expect(cpu.data[0x50], equals(0xa1));
    });
  });
}

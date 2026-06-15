import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:avr8_dart/src/utils/assembler.dart';

Uint8List bytes(String hex) {
  final result = Uint8List(hex.length ~/ 2);
  for (int i = 0; i < hex.length; i += 2) {
    result[i ~/ 2] = int.parse(hex.substring(i, i + 2), radix: 16);
  }
  return result;
}

void main() {
  group('AVR assembler', () {
    test('should assemble ADD instruction', () {
      final res = assemble('ADD r16, r11');
      expect(res.bytes, equals(bytes('0b0d')));
      expect(res.errors, isEmpty);
      expect(res.lines.length, equals(1));
      expect(res.lines[0].text, equals('ADD r16, r11'));
      expect(res.labels, isEmpty);
    });

    test('should support labels', () {
      expect(assemble('loop: JMP loop').bytes, equals(bytes('0c940000')));
    });

    test('should support mutli-line programs', () {
      final input = '''
        start: 
        LDI r16, 15
        EOR r16, r0
        BREQ start
      ''';
      expect(assemble(input).bytes, equals(bytes('0fe00025e9f3')));
    });

    test('should successfully assemble an empty program', () {
      final res = assemble('');
      expect(res.bytes, equals(Uint8List(0)));
      expect(res.errors, isEmpty);
      expect(res.lines, isEmpty);
      expect(res.labels, isEmpty);
    });

    test('should return an empty byte array in case of program error', () {
      final res = assemble('LDI r15, 20');
      expect(res.bytes, equals(Uint8List(0)));
      expect(res.errors.length, equals(1));
      expect(res.errors[0], equals('Line 0: Rd out of range: 16<>31'));
      expect(res.lines, isEmpty);
      expect(res.labels, isEmpty);
    });

    test('should correctly assemble `ADC r0, r1`', () {
      expect(assemble('ADC r0, r1').bytes, equals(bytes('011c')));
    });

    test('should correctly assemble `BCLR 2`', () {
      expect(assemble('BCLR 2').bytes, equals(bytes('a894')));
    });

    test('should correctly assemble `BLD r4, 7`', () {
      expect(assemble('BLD r4, 7').bytes, equals(bytes('47f8')));
    });

    test('should correctly assemble `BRBC 0, +8`', () {
      expect(assemble('BRBC 0, +8').bytes, equals(bytes('20f4')));
    });

    test('should correctly assemble `BRBS 3, 92`', () {
      expect(assemble('BRBS 3, 92').bytes, equals(bytes('73f1')));
    });

    test('should correctly assemble `BRBS 3, -4`', () {
      expect(assemble('BRBS 3, -4').bytes, equals(bytes('f3f3')));
    });

    test('should correctly assemble BREQ with forward label target', () {
      expect(assemble('BREQ next \n next:').bytes, equals(bytes('01f0')));
    });

    test('should correctly assemble BRNE with forward label target', () {
      expect(assemble('BRNE next \n next:').bytes, equals(bytes('01f4')));
    });

    test('should correctly assemble `CBI 0xc, 5`', () {
      expect(assemble('CBI 0xc, 5').bytes, equals(bytes('6598')));
    });

    test('should correctly assemble `CALL 0xb8`', () {
      expect(assemble('CALL 0xb8').bytes, equals(bytes('0e945c00')));
    });

    test('should correctly assemble `CPC r27, r18`', () {
      expect(assemble('CPC r27, r18').bytes, equals(bytes('b207')));
    });

    test('should correctly assemble `CPC r24, r1`', () {
      expect(assemble('CPC r24, r1').bytes, equals(bytes('8105')));
    });

    test('should correctly assemble `CPI r26, 0x9`', () {
      expect(assemble('CPI r26, 0x9').bytes, equals(bytes('a930')));
    });

    test('should correctly assemble `CPSE r2, r3`', () {
      expect(assemble('CPSE r2, r3').bytes, equals(bytes('2310')));
    });

    test('should correctly assemble `ICALL`', () {
      expect(assemble('ICALL').bytes, equals(bytes('0995')));
    });

    test('should correctly assemble `IJMP`', () {
      expect(assemble('IJMP').bytes, equals(bytes('0994')));
    });

    test('should correctly assemble `IN r5, 0xb`', () {
      expect(assemble('IN r5, 0xb').bytes, equals(bytes('5bb0')));
    });

    test('should correctly assemble `INC r5`', () {
      expect(assemble('INC r5').bytes, equals(bytes('5394')));
    });

    test('should correctly assemble `JMP 0xb8`', () {
      expect(assemble('JMP 0xb8').bytes, equals(bytes('0c945c00')));
    });

    test('should correctly assemble `LAC r19`', () {
      expect(assemble('LAC Z, r19').bytes, equals(bytes('3693')));
    });

    test('should correctly assemble `LAS Z, r17`', () {
      expect(assemble('LAS Z, r17').bytes, equals(bytes('1593')));
    });

    test('should correctly assemble `LAT Z, r0`', () {
      expect(assemble('LAT Z, r0').bytes, equals(bytes('0792')));
    });

    test('should correctly assemble `LDI r28, 0xff`', () {
      expect(assemble('LDI r28, 0xff').bytes, equals(bytes('cfef')));
    });

    test('should correctly assemble `LDS r5, 0x150`', () {
      expect(assemble('LDS r5, 0x150').bytes, equals(bytes('50905001')));
    });

    test('should correctly assemble `LD r1, X`', () {
      expect(assemble('LD r1, X').bytes, equals(bytes('1c90')));
    });

    test('should correctly assemble `LD r17, X+`', () {
      expect(assemble('LD r17, X+').bytes, equals(bytes('1d91')));
    });

    test('should correctly assemble `LD r1, -X`', () {
      expect(assemble('LD r1, -X').bytes, equals(bytes('1e90')));
    });

    test('should correctly assemble `LD r8, Y`', () {
      expect(assemble('LD r8, Y').bytes, equals(bytes('8880')));
    });

    test('should correctly assemble `LD r3, Y+`', () {
      expect(assemble('LD r3, Y+').bytes, equals(bytes('3990')));
    });

    test('should correctly assemble `LD r0, -Y`', () {
      expect(assemble('LD r0, -Y').bytes, equals(bytes('0a90')));
    });

    test('should correctly assemble `LDD r4, Y+2`', () {
      expect(assemble('LDD r4, Y+2').bytes, equals(bytes('4a80')));
    });

    test('should correctly assemble `LD r5, Z`', () {
      expect(assemble('LD r5, Z').bytes, equals(bytes('5080')));
    });

    test('should correctly assemble `LD r7, Z+`', () {
      expect(assemble('LD r7, Z+').bytes, equals(bytes('7190')));
    });

    test('should correctly assemble `LD r0, -Z`', () {
      expect(assemble('LD r0, -Z').bytes, equals(bytes('0290')));
    });

    test('should correctly assemble `LDD r15, Z+31`', () {
      expect(assemble('LDD r15, Z+31').bytes, equals(bytes('f78c')));
    });

    test('should correctly assemble `LPM`', () {
      expect(assemble('LPM').bytes, equals(bytes('c895')));
    });

    test('should correctly assemble `LPM r2, Z`', () {
      expect(assemble('LPM r2, Z').bytes, equals(bytes('2490')));
    });

    test('should correctly assemble `LPM r1, Z+`', () {
      expect(assemble('LPM r1, Z+').bytes, equals(bytes('1590')));
    });

    test('should correctly assemble `LSR r7`', () {
      expect(assemble('LSR r7').bytes, equals(bytes('7694')));
    });

    test('should correctly assemble `MOV r7, r8`', () {
      expect(assemble('MOV r7, r8').bytes, equals(bytes('782c')));
    });

    test('should correctly assemble `MOVW r26, r22`', () {
      expect(assemble('MOVW r26, r22').bytes, equals(bytes('db01')));
    });

    test('should correctly assemble `MUL r5, r6`', () {
      expect(assemble('MUL r5, r6').bytes, equals(bytes('569c')));
    });

    test('should correctly assemble `MULS r18, r19`', () {
      expect(assemble('MULS r18, r19').bytes, equals(bytes('2302')));
    });

    test('should correctly assemble `MULSU r16, r17`', () {
      expect(assemble('MULSU r16, r17').bytes, equals(bytes('0103')));
    });

    test('should correctly assemble `NEG r20`', () {
      expect(assemble('NEG r20').bytes, equals(bytes('4195')));
    });

    test('should correctly assemble `NOP`', () {
      expect(assemble('NOP').bytes, equals(bytes('0000')));
    });

    test('should correctly assemble `OR r5, r2`', () {
      expect(assemble('OR r5, r2').bytes, equals(bytes('5228')));
    });

    test('should correctly assemble `ORI r22, 0x81`', () {
      expect(assemble('ORI r22, 0x81').bytes, equals(bytes('6168')));
    });

    test('should correctly assemble `OUT 0x3f, r1`', () {
      expect(assemble('OUT 0x3f, r1').bytes, equals(bytes('1fbe')));
    });

    test('should correctly assemble `POP r26`', () {
      expect(assemble('POP r26').bytes, equals(bytes('af91')));
    });

    test('should correctly assemble `PUSH r11`', () {
      expect(assemble('PUSH r11').bytes, equals(bytes('bf92')));
    });

    test('should correctly assemble `RCALL +6`', () {
      expect(assemble('RCALL +6').bytes, equals(bytes('03d0')));
    });

    test('should correctly assemble `RCALL -4`', () {
      expect(assemble('RCALL -4').bytes, equals(bytes('fedf')));
    });

    test('should correctly assemble `RET`', () {
      expect(assemble('RET').bytes, equals(bytes('0895')));
    });

    test('should correctly assemble `RETI`', () {
      expect(assemble('RETI').bytes, equals(bytes('1895')));
    });

    test('should correctly assemble `RJMP 2`', () {
      expect(assemble('RJMP 2').bytes, equals(bytes('01c0')));
    });

    test('should correctly assemble `ROR r0`', () {
      expect(assemble('ROR r0').bytes, equals(bytes('0794')));
    });

    test('should correctly assemble `SBCI r23, 3`', () {
      expect(assemble('SBCI r23, 3').bytes, equals(bytes('7340')));
    });

    test('should correctly assemble `SBI 0x0c, 5`', () {
      expect(assemble('SBI 0x0c, 5').bytes, equals(bytes('659a')));
    });

    test('should correctly assemble `SBIS 0x0c, 5`', () {
      expect(assemble('SBIS 0x0c, 5').bytes, equals(bytes('659b')));
    });

    test('should correctly assemble `SBIW r28, 2`', () {
      expect(assemble('SBIW r28, 2').bytes, equals(bytes('2297')));
    });

    test('should correctly assemble `SLEEP`', () {
      expect(assemble('SLEEP').bytes, equals(bytes('8895')));
    });

    test('should correctly assemble `SPM`', () {
      expect(assemble('SPM').bytes, equals(bytes('e895')));
    });

    test('should correctly assemble `SPM Z+`', () {
      expect(assemble('SPM Z+').bytes, equals(bytes('f895')));
    });

    test('should correctly assemble `STS 0x151, r31`', () {
      expect(assemble('STS 0x151, r31').bytes, equals(bytes('f0935101')));
    });

    test('should correctly assemble `ST X, r1`', () {
      expect(assemble('ST X, r1').bytes, equals(bytes('1c92')));
    });

    test('should correctly assemble `ST X+, r1`', () {
      expect(assemble('ST X+, r1').bytes, equals(bytes('1d92')));
    });

    test('should correctly assemble `ST -X, r17`', () {
      expect(assemble('ST -X, r17').bytes, equals(bytes('1e93')));
    });

    test('should correctly assemble `ST Y, r2`', () {
      expect(assemble('ST Y, r2').bytes, equals(bytes('2882')));
    });

    test('should correctly assemble `ST Y+, r1`', () {
      expect(assemble('ST Y+, r1').bytes, equals(bytes('1992')));
    });

    test('should correctly assemble `ST -Y, r1`', () {
      expect(assemble('ST -Y, r1').bytes, equals(bytes('1a92')));
    });

    test('should correctly assemble `STD Y+17, r0`', () {
      expect(assemble('STD Y+17, r0').bytes, equals(bytes('098a')));
    });

    test('should correctly assemble `ST Z, r16`', () {
      expect(assemble('ST Z, r16').bytes, equals(bytes('0083')));
    });

    test('should correctly assemble `ST Z+, r0`', () {
      expect(assemble('ST Z+, r0').bytes, equals(bytes('0192')));
    });

    test('should correctly assemble `ST -Z, r16`', () {
      expect(assemble('ST -Z, r16').bytes, equals(bytes('0293')));
    });

    test('should correctly assemble `STD Z+1, r0`', () {
      expect(assemble('STD Z+1, r0').bytes, equals(bytes('0182')));
    });

    test('should correctly assemble `SWAP r1`', () {
      expect(assemble('SWAP r1').bytes, equals(bytes('1294')));
    });

    test('should correctly assemble `XCH Z, r21`', () {
      expect(assemble('XCH Z, r21').bytes, equals(bytes('5493')));
    });
  });
}

import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:avr8_dart/src/cpu/cpu.dart';
import 'package:avr8_dart/src/peripherals/gpio.dart';
import 'package:avr8_dart/src/peripherals/timer.dart';
import 'test_utils.dart';

// CPU registers
const R1 = 1;
const R17 = 17;
const R18 = 18;
const R19 = 19;
const R20 = 20;
const R21 = 21;
const R22 = 22;
const SREG = 95;

// Timer 0 Registers
const TIFR0 = 0x35;
const TCCR0A = 0x44;
const TCCR0B = 0x45;
const TCNT0 = 0x46;
const OCR0A = 0x47;
const OCR0B = 0x48;
const TIMSK0 = 0x6e;
const TIMSK1 = 0x6f;

// Timer 1 Registers
const TIFR1 = 0x36;
const TCCR1A = 0x80;
const TCCR1B = 0x81;
const TCCR1C = 0x82;
const TCNT1 = 0x84;
const TCNT1H = 0x85;
const ICR1 = 0x86;
const ICR1H = 0x87;
const OCR1A = 0x88;
const OCR1AH = 0x89;
const OCR1B = 0x8a;
const OCR1C = 0x8c;
const OCR1CH = 0x8d;

// Timer 2 Registers
const TCCR2B = 0xb1;
const TCNT2 = 0xb2;

// Register bit names
const TOV0 = 1;
const TOV1 = 1;
const OCIE0A = 2;
const OCIE0B = 4;
const TOIE0 = 1;
const OCF0A = 2;
const OCF0B = 4;
const OCF1A = 1 << 1;
const OCF1B = 1 << 2;
const OCF1C = 1 << 3;
const WGM00 = 1;
const WGM10 = 1;
const WGM01 = 2;
const WGM11 = 2;
const WGM12 = 8;
const WGM13 = 16;
const CS00 = 1;
const CS01 = 2;
const CS02 = 4;
const CS10 = 1;
const CS21 = 2;
const CS22 = 4;
const COM0B1 = 1 << 5;
const COM1C0 = 1 << 2;
const FOC0B = 1 << 6;
const FOC1C = 1 << 5;

const T0 = 4; // PD4 on ATmega328p

void main() {
  group('timer', () {
    test('should update timer every tick when prescaler is 1', () {
      final cpu = CPU(Uint16List(0x1000));
      AVRTimer(cpu, timer0Config);
      cpu.writeData(TCCR0B, CS00); // Set prescaler to 1
      cpu.cycles = 1;
      cpu.tick();
      cpu.cycles = 2;
      cpu.tick();
      final tcnt = cpu.readData(TCNT0);
      expect(tcnt, equals(1));
    });

    test('should update timer every 64 ticks when prescaler is 3', () {
      final cpu = CPU(Uint16List(0x1000));
      AVRTimer(cpu, timer0Config);
      cpu.writeData(TCCR0B, CS01 | CS00); // Set prescaler to 64
      cpu.cycles = 1;
      cpu.tick();
      cpu.cycles = 1 + 64;
      cpu.tick();
      final tcnt = cpu.readData(TCNT0);
      expect(tcnt, equals(1));
    });

    test('should not update timer if it has been disabled', () {
      final cpu = CPU(Uint16List(0x1000));
      AVRTimer(cpu, timer0Config);
      cpu.writeData(TCCR0B, 0); // No prescaler (timer disabled)
      cpu.cycles = 1;
      cpu.tick();
      cpu.cycles = 100000;
      cpu.tick();
      final tcnt = cpu.readData(TCNT0);
      expect(tcnt, equals(0)); // TCNT should stay 0
    });

    test('should set the TOV flag when timer wraps above TOP value', () {
      final cpu = CPU(Uint16List(0x1000));
      AVRTimer(cpu, timer0Config);
      cpu.writeData(TCNT0, 0xff);
      cpu.writeData(TCCR0B, CS00); // Set prescaler to 1

      cpu.cycles = 1;
      cpu.tick();
      expect(cpu.readData(TCNT0), equals(0xff));
      expect(cpu.data[TIFR0] & TOV0, equals(0));

      cpu.cycles++;
      cpu.tick();
      expect(cpu.readData(TCNT0), equals(0));
      expect(cpu.data[TIFR0] & TOV0, equals(TOV0));
    });

    test('should set the TOV if timer overflows past TOP without reaching TOP',
        () {
      final cpu = CPU(Uint16List(0x1000));
      AVRTimer(cpu, timer0Config);
      cpu.writeData(TCNT0, 0xfe);
      cpu.writeData(TCCR0B, CS00); // Set prescaler to 1
      cpu.cycles = 1;
      cpu.tick();
      expect(cpu.readData(TCNT0), equals(0xfe));
      cpu.cycles += 4;
      cpu.tick();
      expect(cpu.readData(TCNT0), equals(0x2));
      expect(cpu.data[TIFR0] & TOV0, equals(TOV0));
    });

    test(
        'should clear the TOV flag when writing 1 to the TOV bit, and not trigger the interrupt',
        () {
      final cpu = CPU(Uint16List(0x1000));
      AVRTimer(cpu, timer0Config);
      cpu.writeData(TCNT0, 0xff);
      cpu.writeData(TCCR0B, CS00); // Set prescaler to 1
      cpu.cycles = 1;
      cpu.tick();
      cpu.cycles = 2;
      cpu.tick();
      expect(cpu.data[TIFR0] & TOV0, equals(TOV0));
      cpu.writeData(TIFR0, TOV0);
      expect(cpu.data[TIFR0] & TOV0, equals(0));
    });

    test('should set TOV if timer overflows in FAST PWM mode', () {
      final cpu = CPU(Uint16List(0x1000));
      AVRTimer(cpu, timer0Config);
      cpu.writeData(TCNT0, 0xff);
      cpu.writeData(TCCR0B, CS00); // Set prescaler to 1
      cpu.cycles = 1;
      cpu.tick();
      cpu.writeData(OCR0A, 0x7f);
      cpu.writeData(TCCR0A, WGM01 | WGM00); // WGM: Fast PWM
      cpu.cycles = 2;
      cpu.tick();
      final tcnt = cpu.readData(TCNT0);
      expect(tcnt, equals(0));
      expect(cpu.data[TIFR0] & TOV0, equals(TOV0));
    });

    test(
        'should generate an overflow interrupt if timer overflows and interrupts enabled',
        () {
      final cpu = CPU(Uint16List(0x1000));
      AVRTimer(cpu, timer0Config);
      cpu.writeData(TCNT0, 0xff);
      cpu.writeData(TCCR0B, CS00); // Set prescaler to 1
      cpu.cycles = 1;
      cpu.tick();
      cpu.writeData(TIMSK0, TOIE0);
      cpu.data[SREG] = 0x80; // SREG: I-------
      cpu.cycles = 2;
      cpu.tick();
      final tcnt = cpu.readData(TCNT0);
      expect(
          tcnt,
          equals(
              2)); // TCNT should be 2 (one tick above + 2 cycles for interrupt)
      expect(cpu.data[TIFR0] & TOV0, equals(0));
      expect(cpu.pc, equals(0x20));
      expect(cpu.cycles, equals(4));
    });

    test('should support overriding TIFR/TOV and TIMSK/TOIE bits (issue #64)',
        () {
      final cpu = CPU(Uint16List(0x1000));
      AVRTimer(
          cpu,
          AVRTimerConfig(
            bits: timer0Config.bits,
            dividers: timer0Config.dividers,
            captureInterrupt: timer0Config.captureInterrupt,
            compAInterrupt: timer0Config.compAInterrupt,
            compBInterrupt: timer0Config.compBInterrupt,
            compCInterrupt: timer0Config.compCInterrupt,
            ovfInterrupt: timer0Config.ovfInterrupt,
            TCCRA: timer0Config.TCCRA,
            TCCRB: timer0Config.TCCRB,
            TCCRC: timer0Config.TCCRC,
            TCNT: timer0Config.TCNT,
            OCRA: timer0Config.OCRA,
            OCRB: timer0Config.OCRB,
            OCRC: timer0Config.OCRC,
            ICR: timer0Config.ICR,
            TIFR: timer0Config.TIFR,
            TIMSK: timer0Config.TIMSK,
            compPortA: timer0Config.compPortA,
            compPinA: timer0Config.compPinA,
            compPortB: timer0Config.compPortB,
            compPinB: timer0Config.compPinB,
            compPortC: timer0Config.compPortC,
            compPinC: timer0Config.compPinC,
            externalClockPort: timer0Config.externalClockPort,
            externalClockPin: timer0Config.externalClockPin,
            TOV: 2,
            OCFA: 2,
            OCFB: 8,
            OCFC: timer0Config.OCFC,
            TOIE: 2,
            OCIEA: 16,
            OCIEB: 8,
            OCIEC: timer0Config.OCIEC,
          ));
      cpu.writeData(TCNT0, 0xff);
      cpu.writeData(TCCR0B, CS00); // Set prescaler to 1
      cpu.cycles = 1;
      cpu.tick();
      cpu.writeData(TIMSK0, 2);
      cpu.data[SREG] = 0x80; // SREG: I-------
      cpu.cycles = 2;
      cpu.tick();
      final tcnt = cpu.readData(TCNT0);
      expect(
          tcnt,
          equals(
              2)); // TCNT should be 2 (one tick above + 2 cycles for interrupt)
      expect(cpu.data[TIFR0] & 2, equals(0));
      expect(cpu.pc, equals(0x20));
      expect(cpu.cycles, equals(4));
    });

    test(
        'should not generate an overflow interrupt when global interrupts disabled',
        () {
      final cpu = CPU(Uint16List(0x1000));
      AVRTimer(cpu, timer0Config);
      cpu.writeData(TCNT0, 0xff);
      cpu.writeData(TCCR0B, CS00); // Set prescaler to 1
      cpu.cycles = 1;
      cpu.tick();
      cpu.data[TIMSK0] = TOIE0;
      cpu.data[SREG] = 0x0; // SREG: --------
      cpu.cycles = 2;
      cpu.tick();
      expect(cpu.data[TIFR0] & TOV0, equals(TOV0));
      expect(cpu.pc, equals(0));
      expect(cpu.cycles, equals(2));
    });

    test('should not generate an overflow interrupt when TOIE0 is clear', () {
      final cpu = CPU(Uint16List(0x1000));
      AVRTimer(cpu, timer0Config);
      cpu.writeData(TCNT0, 0xff);
      cpu.writeData(TCCR0B, CS00); // Set prescaler to 1
      cpu.cycles = 1;
      cpu.tick();
      cpu.data[TIMSK0] = 0;
      cpu.data[SREG] = 0x80; // SREG: I-------
      cpu.cycles = 2;
      cpu.tick();
      expect(cpu.data[TIFR0] & TOV0, equals(TOV0));
      expect(cpu.pc, equals(0));
      expect(cpu.cycles, equals(2));
    });

    test(
        'should set OCF0A/B flags when OCRA/B == 0 and the timer equals to OCRA (issue #74)',
        () {
      final cpu = CPU(Uint16List(0x1000));
      AVRTimer(cpu, timer0Config);
      cpu.writeData(TCNT0, 0xff);
      cpu.writeData(OCR0A, 0x0);
      cpu.writeData(OCR0B, 0x0);
      cpu.writeData(TCCR0A, 0x0); // WGM: Normal
      cpu.writeData(TCCR0B, CS00); // Set prescaler to 1
      cpu.cycles = 1;
      cpu.tick();
      cpu.cycles = 2;
      cpu.tick();
      expect(cpu.readData(TCNT0), equals(0));
      expect(cpu.data[TIFR0] & (OCF0A | OCF0B), equals(OCF0A | OCF0B));
      expect(cpu.pc, equals(0));
      expect(cpu.cycles, equals(2));
    });

    test(
        'should set the OCF1A flag when OCR1A == 120 and the timer overflowed past 120 in WGM mode 15 (issue #94)',
        () {
      final cpu = CPU(Uint16List(0x1000));
      AVRTimer(cpu, timer1Config);
      cpu.writeData(TCNT1, 118);
      cpu.writeData(OCR1A, 120);
      cpu.writeData(OCR1B, 4); // To avoid getting the OCF1B flag set
      cpu.writeData(TCCR1A, WGM10 | WGM11); // WGM: Fast PWM
      cpu.writeData(TCCR1B, WGM12 | WGM13 | CS10); // Set prescaler to 1
      cpu.cycles = 1;
      cpu.tick();
      cpu.cycles = 5;
      cpu.tick();
      expect(cpu.readData(TCNT1), equals(1));
      expect(cpu.data[TIFR1] & (OCF1A | OCF1B), equals(OCF1A));
      expect(cpu.pc, equals(0));
      expect(cpu.cycles, equals(5));
    });

    test('should set OCF0A flag when timer equals OCRA', () {
      final cpu = CPU(Uint16List(0x1000));
      AVRTimer(cpu, timer0Config);
      cpu.writeData(TCNT0, 0x10);
      cpu.writeData(OCR0A, 0x11);
      cpu.writeData(TCCR0A, 0x0); // WGM: Normal
      cpu.writeData(TCCR0B, CS00); // Set prescaler to 1
      cpu.cycles = 1;
      cpu.tick();
      cpu.cycles = 2;
      cpu.tick();
      expect(cpu.data[TIFR0], equals(OCF0A));
      expect(cpu.pc, equals(0));
      expect(cpu.cycles, equals(2));
    });

    test('should reset the counter in CTC mode if it equals to OCRA', () {
      final cpu = CPU(Uint16List(0x1000));
      AVRTimer(cpu, timer0Config);
      cpu.writeData(TCNT0, 0x10);
      cpu.writeData(OCR0A, 0x11);
      cpu.writeData(TCCR0A, WGM01); // WGM: CTC
      cpu.writeData(TCCR0B, CS00); // Set prescaler to 1
      cpu.cycles = 1;
      cpu.tick();
      cpu.cycles = 3;
      cpu.tick();
      final tcnt = cpu.readData(TCNT0);
      expect(tcnt, equals(0));
      expect(cpu.pc, equals(0));
      expect(cpu.cycles, equals(3));
    });

    test('should not set the TOV bit when TOP < MAX in CTC mode (issue #75)',
        () {
      final cpu = CPU(Uint16List(0x1000));
      AVRTimer(cpu, timer0Config);
      cpu.writeData(TCNT0, 0x1e);
      cpu.writeData(OCR0A, 0x1f);
      cpu.writeData(TCCR0A, WGM01); // WGM: CTC
      cpu.writeData(TCCR0B, CS00); // Set prescaler to 1
      cpu.cycles = 1;
      cpu.tick();
      cpu.cycles++;
      cpu.tick();
      cpu.cycles++;
      cpu.tick();
      final tcnt = cpu.readData(TCNT0);
      expect(tcnt, equals(0));
      expect(cpu.data[TIFR0] & TOV0, equals(0)); // TOV0 clear
    });

    test('should set the TOV bit when TOP == MAX in CTC mode (issue #75)', () {
      final cpu = CPU(Uint16List(0x1000));
      AVRTimer(cpu, timer0Config);
      cpu.writeData(TCNT0, 0xfe);
      cpu.writeData(OCR0A, 0xff);
      cpu.writeData(TCCR0A, WGM01); // WGM: CTC
      cpu.writeData(TCCR0B, CS00); // Set prescaler to 1
      cpu.cycles = 1;
      cpu.tick();

      cpu.cycles++;
      cpu.tick();
      expect(cpu.readData(TCNT0), equals(0xff));
      expect(cpu.data[TIFR0] & TOV0, equals(0)); // TOV clear

      cpu.cycles++;
      cpu.tick();
      expect(cpu.readData(TCNT0), equals(0));
      expect(cpu.data[TIFR0] & TOV0, equals(TOV0)); // TOV set
    });

    test('should not set the TOV bit twice on overflow (issue #80)', () {
      final cpu = CPU(Uint16List(0x1000));
      AVRTimer(cpu, timer0Config);
      cpu.writeData(TCNT0, 0xfe);
      cpu.writeData(OCR0A, 0xff);
      cpu.writeData(TCCR0A, WGM01); // WGM: CTC
      cpu.writeData(TCCR0B, CS00); // Set prescaler to 1

      cpu.cycles = 1;
      cpu.tick();

      cpu.cycles++;
      cpu.tick();
      expect(cpu.readData(TCNT0), equals(0xff));
      expect(cpu.data[TIFR0] & TOV0, equals(0)); // TOV clear

      cpu.cycles++;
      cpu.tick();
      expect(cpu.readData(TCNT0), equals(0));
      expect(cpu.data[TIFR0] & TOV0, equals(TOV0)); // TOV set
    });

    test('should set OCF0B flag when timer equals OCRB', () {
      final cpu = CPU(Uint16List(0x1000));
      AVRTimer(cpu, timer0Config);
      cpu.writeData(TCNT0, 0x10);
      cpu.writeData(OCR0B, 0x11);
      cpu.writeData(TCCR0A, 0x0); // WGM: (Normal)
      cpu.writeData(TCCR0B, CS00); // Set prescaler to 1
      cpu.cycles = 1;
      cpu.tick();
      cpu.cycles = 2;
      cpu.tick();
      expect(cpu.data[TIFR0], equals(OCF0B));
      expect(cpu.pc, equals(0));
      expect(cpu.cycles, equals(2));
    });

    test('should generate Timer Compare A interrupt when TCNT0 == TCNTA', () {
      final cpu = CPU(Uint16List(0x1000));
      AVRTimer(cpu, timer0Config);
      cpu.writeData(TCNT0, 0x20);
      cpu.writeData(OCR0A, 0x21);
      cpu.writeData(TCCR0B, CS00); // Set prescaler to 1
      cpu.writeData(TIMSK0, OCIE0A);
      cpu.writeData(95, 0x80); // SREG: I-------
      cpu.cycles = 1;
      cpu.tick();
      cpu.cycles = 2;
      cpu.tick();
      final tcnt = cpu.readData(TCNT0);
      expect(
          tcnt,
          equals(
              0x23)); // TCNT should be 0x23 (one tick above + 2 cycles for interrupt)
      expect(cpu.data[TIFR0] & OCF0A, equals(0));
      expect(cpu.pc, equals(0x1c));
      expect(cpu.cycles, equals(4));
    });

    test('should not generate Timer Compare A interrupt when OCIEA is disabled',
        () {
      final cpu = CPU(Uint16List(0x1000));
      AVRTimer(cpu, timer0Config);
      cpu.writeData(TCNT0, 0x20);
      cpu.writeData(OCR0A, 0x21);
      cpu.writeData(TCCR0B, CS00); // Set prescaler to 1
      cpu.writeData(TIMSK0, 0);
      cpu.writeData(95, 0x80); // SREG: I-------
      cpu.cycles = 1;
      cpu.tick();
      cpu.cycles = 2;
      cpu.tick();
      final tcnt = cpu.readData(TCNT0);
      expect(tcnt, equals(0x21));
      expect(cpu.pc, equals(0));
      expect(cpu.cycles, equals(2));
    });

    test('should generate Timer Compare B interrupt when TCNT0 == TCNTB', () {
      final cpu = CPU(Uint16List(0x1000));
      AVRTimer(cpu, timer0Config);
      cpu.writeData(TCNT0, 0x20);
      cpu.writeData(OCR0B, 0x21);
      cpu.writeData(TCCR0B, CS00); // Set prescaler to 1
      cpu.writeData(TIMSK0, OCIE0B);
      cpu.writeData(95, 0x80); // SREG: I-------
      cpu.cycles = 1;
      cpu.tick();
      cpu.cycles = 2;
      cpu.tick();
      final tcnt = cpu.readData(TCNT0);
      expect(tcnt,
          equals(0x23)); // TCNT should be 0x23 (0x23 + 2 cycles for interrupt)
      expect(cpu.data[TIFR0] & OCF0B, equals(0));
      expect(cpu.pc, equals(0x1e));
      expect(cpu.cycles, equals(4));
    });

    test(
        'should not increment TCNT on the same cycle of TCNT write (issue #36)',
        () {
      // At the end of this short program, R17 should contain 0x31. Verified against
      // a physical ATmega328p.
      final asm = asmProgram('''
      LDI r16, 0x1    ; TCCR0B = 1 << CS00;
      OUT 0x25, r16
      LDI r16, 0x30   ; TCNT0 <- 0x30
      OUT 0x26, r16
      NOP
      IN r17, 0x26    ; r17 <- TCNT
    ''');
      final cpu = CPU(asm.program);

      AVRTimer(cpu, timer0Config);
      final runner = TestProgramRunner(cpu);
      runner.runInstructions(asm.instructionCount);
      expect(cpu.data[R17], equals(0x31));
    });

    test('timer2 should count every 256 ticks when prescaler is 6 (issue #5)',
        () {
      final cpu = CPU(Uint16List(0x1000));
      AVRTimer(cpu, timer2Config);
      cpu.writeData(TCCR2B, CS22 | CS21); // Set prescaler to 256
      cpu.cycles = 1;
      cpu.tick();

      cpu.cycles = 1 + 511;
      cpu.tick();
      expect(cpu.readData(TCNT2), equals(1));

      cpu.cycles = 1 + 512;
      cpu.tick();
      expect(cpu.readData(TCNT2), equals(2));
    });

    test(
        'should update TCNT as it is being read by a 2-cycle instruction (issue #40)',
        () {
      final asm = asmProgram('''
      LDI r16, 0x1      ; TCCR0B = 1 << CS00
      OUT 0x25, r16
      LDI r16, 0x0      ; TCNT0 <- 0
      OUT 0x26, r16
      NOP
      LDS r1, 0x46      ; r1 <- TCNT0 (2 cycles)
    ''');
      final cpu = CPU(asm.program);

      AVRTimer(cpu, timer0Config);

      final runner = TestProgramRunner(cpu);
      runner.runInstructions(asm.instructionCount);
      expect(cpu.data[R1], equals(2));
    });

    test(
        'should not start counting before the prescaler is first set (issue #41)',
        () {
      final asm = asmProgram('''
      NOP
      NOP
      NOP
      NOP
      LDI r16, 0x1    ; TCCR2B = 1 << CS20;
      STS 0xb1, r16   ; Should start counting after this line
      NOP
      LDS r17, 0xb2   ; TCNT should equal 2 at this point
    ''');
      final cpu = CPU(asm.program);

      AVRTimer(cpu, timer2Config);
      final runner = TestProgramRunner(cpu);
      runner.runInstructions(asm.instructionCount);
      expect(cpu.readData(R17), equals(2));
    });

    test(
        'should not keep counting for one more instruction when the timer is disabled (issue #72)',
        () {
      final asm = asmProgram('''
      EOR r1, r1      ; r1 = 0;
      LDI r16, 0x1    ; TCCR2B = 1 << CS20;
      STS 0xb1, r16   ; Should start counting after this instruction,
      STS 0xb1, r1    ; and stop counting *after* this one.
      NOP
      LDS r17, 0xb2   ; TCNT2 should equal 2 at this point (not counting the NOP)
  ''');
      final cpu = CPU(asm.program);

      AVRTimer(cpu, timer2Config);

      final runner = TestProgramRunner(cpu);
      runner.runInstructions(asm.instructionCount);
      expect(cpu.readData(R17), equals(2));
    });

    test('should clear OC0B pin when writing 1 to FOC0B', () {
      final cpu = CPU(Uint16List(0x1000));
      AVRTimer(cpu, timer0Config);
      cpu.writeData(TCCR0A, COM0B1);

      // Listen to Port B's internal callback
      final portD = AVRIOPort(cpu, portDConfig);

      cpu.writeData(TCCR0B, FOC0B);

      expect(portD.overrideMask & (1 << 5), equals(0));
      expect(portD.overrideValue & (1 << 5), equals(0));
    });

    group('Fast PWM mode', () {
      test('should set OC0A on Compare Match, clear on Bottom (issue #78)', () {
        final asm = asmProgram('''
        LDI r16, 0xfc   ; TCNT0 = 0xfc;
        OUT 0x26, r16
        LDI r16, 0xfe   ; OCR0A = 0xfe;
        OUT 0x27, r16  
        ; WGM: Fast PWM, enable OC0A mode 3 (set on Compare Match, clear on Bottom)
        LDI r16, 0xc3   ; TCCR0A = (1 << COM0A1) | (1 << COM0A0) | (1 << WGM01) | (1 << WGM00);
        OUT 0x24, r16
        LDI r16, 0x1    ; TCCR0B = 1 << CS00;
        OUT 0x25, r16

        NOP             ; TCNT is now 0xfd
      beforeMatch: 
        NOP             ; TCNT is now 0xfe (Compare Match)
      afterMatch:
        NOP             ; TCNT is now 0xff
      beforeBottom:     
        NOP             ; TCNT is now 0x00 (BOTTOM)
      afterBottom:
        NOP
      ''');
        final cpu = CPU(asm.program);
        final labels = asm.labels;

        AVRTimer(cpu, timer0Config);

        // Listen to Port D's internal callback
        final portD = AVRIOPort(cpu, portDConfig);

        final runner = TestProgramRunner(cpu);
        runner.runToAddress(labels['beforeMatch']!);
        expect(cpu.readData(TCNT0), equals(0xfd));

        expect(portD.overrideMask & (1 << 6), equals(0)); // OC0A: Enable

        runner.runToAddress(labels['afterMatch']!);
        expect(cpu.readData(TCNT0), equals(0xfe));

        expect(portD.overrideMask & (1 << 6), equals(0));
        expect(portD.overrideValue & (1 << 6), equals(1 << 6)); // OC0A: Set

        runner.runToAddress(labels['beforeBottom']!);
        expect(cpu.readData(TCNT0), equals(0xff));

        runner.runToAddress(labels['afterBottom']!);
        expect(cpu.readData(TCNT0), equals(0x0));

        expect(portD.overrideMask & (1 << 6), equals(0));
        expect(portD.overrideValue & (1 << 6), equals(0)); // OC0A: Clear
      });

      test('should toggle OC0A on Compare Match when COM0An = 1 (issue #78)',
          () {
        final asm = asmProgram('''
        LDI r16, 0xfc   ; TCNT0 = 0xfc;
        OUT 0x26, r16
        LDI r16, 0xfe   ; OCR0A = 0xfe;
        OUT 0x27, r16  
        ; WGM: Fast PWM, enable OC0A mode 1 (Toggle)
        LDI r16, 0x43   ; TCCR0A = (1 << COM0A0) | (1 << WGM01) | (1 << WGM00);
        OUT 0x24, r16
        LDI r16, 0x09   ; TCCR0B = (1 << WGM02) | (1 << CS00);
        OUT 0x25, r16

        NOP             ; TCNT is now 0xfd
      beforeMatch: 
        NOP             ; TCNT is now 0xfe (Compare Match, TOP)
      afterMatch:
        NOP             ; TCNT is now 0
      afterOverflow:
        NOP
      ''');
        final cpu = CPU(asm.program);
        final labels = asm.labels;

        AVRTimer(cpu, timer0Config);

        // Listen to Port D's internal callback
        final portD = AVRIOPort(cpu, portDConfig);

        final runner = TestProgramRunner(cpu);
        runner.runToAddress(labels['beforeMatch']!);
        expect(cpu.readData(TCNT0), equals(0xfd));

        expect(portD.overrideMask & (1 << 6), equals(0)); // OC0A: Enable

        runner.runToAddress(labels['afterMatch']!);
        expect(cpu.readData(TCNT0), equals(0xfe));

        expect(portD.overrideMask & (1 << 6), equals(0)); // OC0A: Toggle

        runner.runToAddress(labels['afterOverflow']!);
        expect(cpu.readData(TCNT0), equals(0));
      });

      test(
          'should leave OC0A disconnected when COM0An = 1 and WGM02 = 0 (issue #78)',
          () {
        final asm = asmProgram('''
        LDI r16, 0xfc   ; TCNT0 = 0xfc;
        OUT 0x26, r16
        LDI r16, 0xfe   ; OCR0A = 0xfe;
        OUT 0x27, r16  
        ; WGM: Fast PWM mode 7, enable OC0A mode 1 (Toggle)
        LDI r16, 0x43   ; TCCR0A = (1 << COM0A0) | (1 << WGM01) | (1 << WGM00);
        OUT 0x24, r16
        LDI r16, 0x09   ; TCCR0B = (1 << WGM02) | (1 << CS00);
        OUT 0x25, r16
        
      beforeClearWGM02:
        LDI r16, 0x01   ; TCCR0B = (1 << CS00);
        OUT 0x25, r16

      afterClearWGM02:
        NOP
      ''');
        final cpu = CPU(asm.program);
        final labels = asm.labels;

        AVRTimer(cpu, timer0Config);

        // Listen to Port D's internal callback
        final portD = AVRIOPort(cpu, portDConfig);

        final runner = TestProgramRunner(cpu);

        // First, run with the bit set and assert that the Pin Override was enabled (OC0A connected)
        runner.runToAddress(labels['beforeClearWGM02']!);

        expect(portD.overrideMask & (1 << 6), equals(0));

        // Now clear WGM02 and observe that Pin Override was disabled (OC0A disconnected)
        runner.runToAddress(labels['afterClearWGM02']!);
      });
    });

    group('Phase-correct PWM mode', () {
      test('should count up to TOP, down to 0, and then set TOV flag', () {
        final asm = asmProgram('''
        LDI r16, 0x3   ; OCR0A = 0x3;   // <- TOP value
        OUT 0x27, r16  
        ; Set waveform generation mode (WGM) to PWM, Phase Correct, top OCR0A
        LDI r16, 0x1   ; TCCR0A = 1 << WGM00;
        OUT 0x24, r16  
        LDI r16, 0x9   ; TCCR0B = (1 << WGM02) | (1 << CS00);
        OUT 0x25, r16  
        LDI r16, 0x2   ; TCNT0 = 0x2;
        OUT 0x26, r16

        IN r17, 0x26   ; TCNT0 will be 2
        IN r18, 0x26   ; TCNT0 will be 3
        IN r19, 0x26   ; TCNT0 will be 2
        IN r20, 0x26   ; TCNT0 will be 1
        IN r21, 0x26   ; TCNT0 will be 0
        IN r22, 0x26   ; TCNT0 will be 1 (end of test)
      ''');
        final cpu = CPU(asm.program);

        AVRTimer(cpu, timer0Config);

        final runner = TestProgramRunner(cpu);
        runner.runInstructions(asm.instructionCount);

        expect(cpu.readData(R17), equals(2));
        expect(cpu.readData(R18), equals(3));
        expect(cpu.readData(R19), equals(2));
        expect(cpu.readData(R20), equals(1));
        expect(cpu.readData(R21), equals(0));
        expect(cpu.readData(R22), equals(1));
        expect(cpu.data[TIFR0] & TOV0, equals(TOV0));
      });

      test('should clear OC0A when TCNT0=OCR0A and counting up', () {
        final asm = asmProgram('''
        LDI r16, 0xfe   ; OCR0A = 0xfe;   // <- TOP value
        OUT 0x27, r16  
        ; Set waveform generation mode (WGM) to PWM, Phase Correct
        LDI r16, 0x81   ; TCCR0A = (1 << COM0A1) | (1 << WGM00);
        OUT 0x24, r16  
        LDI r16, 0x1   ; TCCR0B = (1 << CS00);
        OUT 0x25, r16  
        LDI r16, 0xfd   ; TCNT0 = 0xfd;
        OUT 0x26, r16  

        NOP   ; TCNT0 will be 0xfe
        NOP   ; TCNT0 will be 0xff
        NOP   ; TCNT0 will be 0xfe again (end of test)
      ''');
        final cpu = CPU(asm.program);

        AVRTimer(cpu, timer0Config);

        // Listen to Port D's internal callback
        final portD = AVRIOPort(cpu, portDConfig);

        final nopCount = asm.lines.where((line) => line.bytes == '0000').length;
        final runner = TestProgramRunner(cpu);
        runner.runInstructions((asm.instructionCount - nopCount).toInt());

        expect(cpu.readData(TCNT0), equals(0xfd));
        expect(portD.overrideMask & (1 << 6), equals(0));

        runner.runInstructions(1);
        expect(cpu.readData(TCNT0), equals(0xfe));
        expect(portD.overrideMask & (1 << 6), equals(0));
        expect(portD.overrideValue & (1 << 6), equals(0));

        runner.runInstructions(1);
        expect(cpu.readData(TCNT0), equals(0xff));

        runner.runInstructions(1);
        expect(cpu.readData(TCNT0), equals(0xfe));
        expect(portD.overrideMask & (1 << 6), equals(0));
        expect(portD.overrideValue & (1 << 6), equals(1 << 6));
      });

      test('should toggle OC0A when TCNT0=OCR0A and COM0An=1 (issue #78)', () {
        final asm = asmProgram('''
        LDI r16, 0xfe   ; OCR0A = 0xfe;   // <- TOP value
        OUT 0x27, r16  
        ; Set waveform generation mode (WGM) to PWM, Phase Correct (mode 5)
        LDI r16, 0x41   ; TCCR0A = (1 << COM0A0) | (1 << WGM00);
        OUT 0x24, r16  
        LDI r16, 0x09   ; TCCR0B = (1 << WGM02) | (1 << CS00);
        OUT 0x25, r16  
        LDI r16, 0xfd   ; TCNT0 = 0xfd;
        OUT 0x26, r16  

      beforeMatch:
        NOP             ; TCNT0 will be 0xfe
      afterMatch:
        NOP
      ''');
        final cpu = CPU(asm.program);
        final labels = asm.labels;

        AVRTimer(cpu, timer0Config);

        // Listen to Port D's internal callback
        final portD = AVRIOPort(cpu, portDConfig);

        final runner = TestProgramRunner(cpu);
        runner.runToAddress(labels['beforeMatch']!);
        expect(cpu.readData(TCNT0), equals(0xfd));
        expect(portD.overrideMask & (1 << 6), equals(0));

        runner.runToAddress(labels['afterMatch']!);
        expect(cpu.readData(TCNT0), equals(0xfe));
        expect(portD.overrideMask & (1 << 6), equals(0));
      });

      test(
          'should leave OC0A disconnected TCNT0=OCR0A and COM0An=1 in WGM mode 1 (issue #78)',
          () {
        final asm = asmProgram('''
        LDI r16, 0xfe   ; OCR0A = 0xfe;   // <- TOP value
        OUT 0x27, r16  
        ; Set waveform generation mode (WGM) to PWM, Phase Correct (mode 1)
        LDI r16, 0x41   ; TCCR0A = (1 << COM0A0) | (1 << WGM00);
        OUT 0x24, r16  
        LDI r16, 0x01   ; TCCR0B = (1 << CS00);
        OUT 0x25, r16  
        LDI r16, 0xfd   ; TCNT0 = 0xfd;
        OUT 0x26, r16  
      ''');
        final cpu = CPU(asm.program);

        AVRTimer(cpu, timer0Config);

        // Listen to Port D's internal callback
        final portD = AVRIOPort(cpu, portDConfig);

        final runner = TestProgramRunner(cpu);
        runner.runInstructions(asm.instructionCount);

        // OC0A stays disconnected: the timer never takes the pin over. In
        // overrideMask a set bit is a pin the timer does not drive (it starts
        // at 0xff), so the bit stays set. avr8js asserted that
        // timerOverridePin was never called.
        expect(portD.overrideMask & (1 << 6), equals(1 << 6));
      });

      test(
          'should not miss Compare Match when executing multi-cycle instruction (issue #79)',
          () {
        final asm = asmProgram('''
        LDI r16, 0x10   ; OCR0A = 0x10;   // <- TOP value
        OUT 0x27, r16  
        ; Set waveform generation mode (WGM) to normal, enable OC0A (Set on match)
        LDI r16, 0xc0   ; TCCR0A = (1 << COM0A1) | (1 << COM0A0);
        OUT 0x24, r16  
        LDI r16, 0x1    ; TCCR0B = (1 << CS00);
        OUT 0x25, r16  
        LDI r16, 0xf    ; TCNT0 = 0xf;
        OUT 0x26, r16  
        RJMP 1          ; TCNT0 will be 0x11 (RJMP takes 2 cycles)
      ''');
        final cpu = CPU(asm.program);

        AVRTimer(cpu, timer0Config);

        // Listen to Port D's internal callback
        final portD = AVRIOPort(cpu, portDConfig);

        final runner = TestProgramRunner(cpu);
        runner.runInstructions(asm.instructionCount);

        expect(cpu.readData(TCNT0), equals(0x11));
        expect(portD.overrideMask & (1 << 6), equals(0));

        // Verify that Compare Match has occured and set the OC0A pin (PD6 on ATmega328p)
        expect(portD.overrideMask & (1 << 6), equals(0));
        expect(portD.overrideValue & (1 << 6), equals(1 << 6));
      });

      test(
          'should only update OCR0A when TCNT0=TOP in PWM Phase Correct mode (issue #76)',
          () {
        final asm = asmProgram('''
        LDI r16, 0x4   ; OCR0A = 0x4;
        OUT 0x27, r16  
        ; Set waveform generation mode (WGM) to PWM, Phase Correct
        LDI r16, 0x01   ; TCCR0A = (1 << WGM00);
        OUT 0x24, r16  
        LDI r16, 0x09   ; TCCR0B = (1 << WGM02) | (1 << CS00);
        OUT 0x25, r16  
        LDI r16, 0x0   ; TCNT0 = 0x0;
        OUT 0x26, r16  

        LDI r16, 0x2    ; OCR0A = 0x2; // TCNT0 should read 0x0
        OUT 0x27, r16   ; // TCNT0 should read 0x1
        NOP             ; // TCNT0 should read 0x2
        NOP             ; // TCNT0 should read 0x3
        IN r17, 0x26    ; R17 = TCNT;  // TCNT0 should read 0x4 (that's old OCR0A / TOP)
        NOP             ; // TCNT0 should read 0x3
        NOP             ; // TCNT0 should read 0x2
        NOP             ; // TCNT0 should read 0x1
        NOP             ; // TCNT0 should read 0x0
        NOP             ; // TCNT0 should read 0x1
        NOP             ; // TCNT0 should read 0x2
        IN r18, 0x26    ; R18 = TCNT; // TCNT0 should read 0x1
      ''');
        final cpu = CPU(asm.program);

        AVRTimer(cpu, timer0Config);

        final runner = TestProgramRunner(cpu);
        runner.runInstructions(asm.instructionCount);

        expect(cpu.readData(R17), equals(0x4));
        expect(cpu.readData(R18), equals(0x1));
      });

      test(
          'should update OCR0A when TCNT0=TOP and TOP=0 in PWM Phase Correct mode (issue #119)',
          () {
        final asm = asmProgram('''
        ; Set waveform generation mode (WGM) to PWM, Phase Correct
        LDI r16, 0x01   ; TCCR0A = (1 << WGM00);
        OUT 0x24, r16
        LDI r16, 0x09   ; TCCR0B = (1 << WGM02) | (1 << CS00);
        OUT 0x25, r16
        LDI r16, 0x0   ; TCNT0 = 0x0;
        OUT 0x26, r16

        IN r17, 0x26    ; R17 = TCNT; // TCNT0 should read 0x0
        IN r18, 0x26    ; R18 = TCNT; // TCNT0 should read 0x0
        LDI r16, 0x2    ; OCR0A = 0x2; // TCNT0 should read 0x1
        OUT 0x27, r16   ; // TCNT0 should read 0x1
        NOP             ; // TCNT0 should read 0x2
        IN r19, 0x26    ; R19 = TCNT; // TCNT0 should read 0x1
      ''');
        final cpu = CPU(asm.program);

        AVRTimer(cpu, timer0Config);

        final runner = TestProgramRunner(cpu);
        runner.runInstructions(asm.instructionCount);

        expect(cpu.readData(R17), equals(0));
        expect(cpu.readData(R18), equals(0));
        expect(cpu.readData(R19), equals(0x1));
      });

      test(
          'should not overrun when TOP < current value in Phase Correct mode (issue #119)',
          () {
        final asm = asmProgram('''
        ; Set waveform generation mode (WGM) to PWM, Phase Correct
        LDI r16, 0x01   ; TCCR0A = (1 << WGM00);
        OUT 0x24, r16
        LDI r16, 0x09   ; TCCR0B = (1 << WGM02) | (1 << CS00);
        OUT 0x25, r16
        LDI r16, 0xff   ; TCNT0 = 0xff;
        OUT 0x26, r16

        IN r17, 0x26    ; R17 = TCNT; // TCNT0 should read 255
      ''');
        final cpu = CPU(asm.program);

        final timer = AVRTimer(cpu, timer0Config);

        final runner = TestProgramRunner(cpu);
        runner.runInstructions(asm.instructionCount);

        expect(cpu.readData(R17), equals(255));
        expect(timer.debugTCNT, equals(0)); // TCNT should wrap
      });
    });

    group('16 bit timers', () {
      test('should increment 16-bit TCNT by 1', () {
        final cpu = CPU(Uint16List(0x1000));
        AVRTimer(cpu, timer1Config);
        cpu.writeData(TCNT1H, 0x22); // TCNT1 <- 0x2233
        cpu.writeData(TCNT1, 0x33); // ...
        final timerLow = cpu.readData(TCNT1);
        final timerHigh = cpu.readData(TCNT1H);
        expect((timerHigh << 8) | timerLow, equals(0x2233));
        cpu.writeData(TCCR1A, 0x0); // WGM: Normal
        cpu.writeData(TCCR1B, CS10); // Set prescaler to 1
        cpu.cycles = 1;
        cpu.tick();
        cpu.cycles = 2;
        cpu.tick();
        cpu.readData(TCNT1);
        expect(cpu.dataView.getUint16(TCNT1, Endian.little),
            equals(0x2234)); // TCNT1 should increment
      });

      test('should set OCF1A flag when timer equals OCRA (16 bit mode)', () {
        final cpu = CPU(Uint16List(0x1000));
        AVRTimer(cpu, timer1Config);
        cpu.writeData(TCNT1H, 0x10); // TCNT1 <- 0x10ee
        cpu.writeData(TCNT1, 0xee); // ...
        cpu.writeData(OCR1AH, 0x10); // OCR1 <- 0x10ef
        cpu.writeData(OCR1A, 0xef); // ...
        cpu.writeData(TCCR1A, 0x0); // WGM: Normal
        cpu.writeData(TCCR1B, CS10); // Set prescaler to 1
        cpu.cycles = 1;
        cpu.tick();
        cpu.cycles = 2;
        cpu.tick();
        expect(
            cpu.data[TIFR1], equals(OCF1A)); // TIFR1 should have OCF1A bit on
        expect(cpu.pc, equals(0));
        expect(cpu.cycles, equals(2));
      });

      test('should set OCF1C flag when timer equals OCRC', () {
        final cpu = CPU(Uint16List(0x1000));
        final OCR1C = 0x8c;
        final OCR1CH = 0x8d;
        final OCF1C = 1 << 3;
        AVRTimer(
            cpu,
            AVRTimerConfig(
              bits: timer1Config.bits,
              dividers: timer1Config.dividers,
              captureInterrupt: timer1Config.captureInterrupt,
              compAInterrupt: timer1Config.compAInterrupt,
              compBInterrupt: timer1Config.compBInterrupt,
              compCInterrupt: timer1Config.compCInterrupt,
              ovfInterrupt: timer1Config.ovfInterrupt,
              TCCRA: timer1Config.TCCRA,
              TCCRB: timer1Config.TCCRB,
              TCCRC: timer1Config.TCCRC,
              TCNT: timer1Config.TCNT,
              OCRA: timer1Config.OCRA,
              OCRB: timer1Config.OCRB,
              ICR: timer1Config.ICR,
              TIFR: timer1Config.TIFR,
              TIMSK: timer1Config.TIMSK,
              compPortA: timer1Config.compPortA,
              compPinA: timer1Config.compPinA,
              compPortB: timer1Config.compPortB,
              compPinB: timer1Config.compPinB,
              externalClockPort: timer1Config.externalClockPort,
              externalClockPin: timer1Config.externalClockPin,
              TOV: timer1Config.TOV,
              OCFA: timer1Config.OCFA,
              OCFB: timer1Config.OCFB,
              TOIE: timer1Config.TOIE,
              OCIEA: timer1Config.OCIEA,
              OCIEB: timer1Config.OCIEB,
              OCIEC: timer1Config.OCIEC,
              OCRC: OCR1C,
              OCFC: OCF1C,
            ));
        cpu.writeData(TCNT1H, 0);
        cpu.writeData(TCNT1, 0x10);
        cpu.writeData(OCR1C, 0x11);
        cpu.writeData(OCR1CH, 0x11);
        cpu.writeData(TCCR1A, 0x0); // WGM: (Normal)
        cpu.writeData(TCCR1B, CS00); // Set prescaler to 1
        cpu.cycles = 1;
        cpu.tick();
        cpu.cycles = 2;
        cpu.tick();
        expect(cpu.data[TIFR1], equals(OCF1C));
        expect(cpu.pc, equals(0));
        expect(cpu.cycles, equals(2));
      });

      test(
          'should generate an overflow interrupt if timer overflows and interrupts enabled',
          () {
        final cpu = CPU(Uint16List(0x1000));
        AVRTimer(cpu, timer1Config);
        cpu.writeData(
            TCCR1A, 0x3); // TCCR1A <- WGM10 | WGM11 (Fast PWM, 10-bit)
        cpu.writeData(TCCR1B, 0x9); // TCCR1B <- WGM12 | CS10
        cpu.writeData(TIMSK1, 0x1); // TIMSK1: TOIE1
        cpu.data[SREG] = 0x80; // SREG: I-------
        cpu.writeData(TCNT1H, 0x3); // TCNT1 <- 0x3ff
        cpu.cycles = 1;
        cpu.tick();
        cpu.writeData(TCNT1, 0xff); // ...
        cpu.cycles++; // This cycle shouldn't be counted
        cpu.tick();
        cpu.cycles++;
        cpu.tick(); // This is where we cause the overflow
        cpu.readData(TCNT1); // Refresh TCNT1
        expect(cpu.dataView.getUint16(TCNT1, Endian.little), equals(2));
        expect(cpu.data[TIFR1] & TOV1, equals(0));
        expect(cpu.pc, equals(0x1a));
        expect(cpu.cycles, equals(5));
      });

      test('should reset the timer once it reaches ICR value in mode 12', () {
        final cpu = CPU(Uint16List(0x1000));
        AVRTimer(cpu, timer1Config);
        cpu.writeData(TCNT1H, 0x50); // TCNT1 <- 0x500f
        cpu.writeData(TCNT1, 0x0f); // ...
        cpu.writeData(ICR1H, 0x50); // ICR1 <- 0x5010
        cpu.writeData(ICR1, 0x10); // ...
        cpu.writeData(
            TCCR1B, WGM13 | WGM12 | CS10); // Set prescaler to 1, WGM: CTC
        cpu.cycles = 1;
        cpu.tick();
        cpu.cycles = 3; // 2 cycles should increment timer twice, beyond ICR1
        cpu.tick();
        cpu.readData(TCNT1); // Refresh TCNT1
        expect(cpu.dataView.getUint16(TCNT1, Endian.little),
            equals(0)); // TCNT should be 0
        expect(cpu.data[TIFR1] & TOV1, equals(0));
        expect(cpu.cycles, equals(3));
      });

      test(
          'should not update the high byte of TCNT if written after the low byte (issue #37)',
          () {
        final cpu = CPU(Uint16List(0x1000));
        AVRTimer(cpu, timer1Config);
        cpu.writeData(TCNT1, 0x22);
        cpu.writeData(TCNT1H, 0x55);
        cpu.cycles = 1;
        cpu.tick();
        final timerLow = cpu.readData(TCNT1);
        final timerHigh = cpu.readData(TCNT1H);
        expect((timerHigh << 8) | timerLow, equals(0x22));
      });

      test(
          'reading from TCNT1H before TCNT1L should return old value (issue #37)',
          () {
        final cpu = CPU(Uint16List(0x1000));
        AVRTimer(cpu, timer1Config);
        cpu.writeData(TCNT1H, 0xff);
        cpu.writeData(TCNT1, 0xff);
        cpu.writeData(TCCR1B, WGM12 | CS10); // Set prescaler to 1, WGM: CTC
        cpu.cycles = 1;
        cpu.tick();
        cpu.cycles = 2;
        cpu.tick();
        // We read the high byte before the low byte, so the high byte should still have
        // the previous value:
        final timerHigh = cpu.readData(TCNT1H);
        final timerLow = cpu.readData(TCNT1);
        expect((timerHigh << 8) | timerLow, equals(0xff00));
      });

      test('should toggle OC1B on Compare Match', () {
        final asm = asmProgram('''
        ; Set waveform generation mode (WGM) to Normal, top 0xFFFF
        LDI r16, 0x10   ; TCCR1A = (1 << COM1B0);
        STS 0x80, r16  
        LDI r16, 0x1    ; TCCR1B = (1 << CS00);
        STS 0x81, r16  
        LDI r16, 0x0    ; OCR1BH = 0x0;
        STS 0x8B, r16  
        LDI r16, 0x4a   ; OCR1BL = 0x4a;
        STS 0x8A, r16  
        LDI r16, 0x0    ; TCNT1H = 0x0;
        STS 0x85, r16  
        LDI r16, 0x49   ; TCNT1L = 0x49;
        STS 0x84, r16  

        NOP   ; TCNT1 will be 0x49
        NOP   ; TCNT1 will be 0x4a
      ''');
        final cpu = CPU(asm.program);

        AVRTimer(cpu, timer1Config);

        // Listen to Port B's internal callback
        final portB = AVRIOPort(cpu, portBConfig);

        final nopCount = asm.lines.where((line) => line.bytes == '0000').length;
        final runner = TestProgramRunner(cpu);
        runner.runInstructions((asm.instructionCount - nopCount).toInt());
        expect(cpu.readData(TCNT1), equals(0x49));
        expect(portB.overrideMask & (1 << 2), equals(0));

        runner.runInstructions(1);
        expect(cpu.readData(TCNT1), equals(0x4a));
        expect(portB.overrideMask & (1 << 2), equals(0));
      });

      test('should toggle OC1C on Compare Match', () {
        final asm = asmProgram('''
        LDI r16, 0x0    ; OCR1CH = 0x0;
        STS 0x8b, r16
        LDI r16, 0x49   ; OCR1CL = 0x49;
        STS 0x8a, r16
        LDI r16, 0x4    ; TCCR1A = 1 << COM1C0; // Toggle OC1C on match
        STS 0x80, r16
        LDI r16, 0x1    ; TCCR1B = 1 << CS10;
        STS 0x81, r16
        LDI r16, 0x0    ; TCNT1H = 0x0;
        STS 0x85, r16
        LDI r16, 0x48   ; TCNT1L = 0x48;
        STS 0x84, r16
        
        NOP             ; TCNT1 will be 0x49
        NOP             ; TCNT1 will be 0x4a
      ''');
        final cpu = CPU(asm.program);

        AVRTimer(
            cpu,
            AVRTimerConfig(
              bits: timer1Config.bits,
              dividers: timer1Config.dividers,
              captureInterrupt: timer1Config.captureInterrupt,
              compAInterrupt: timer1Config.compAInterrupt,
              compBInterrupt: timer1Config.compBInterrupt,
              compCInterrupt: timer1Config.compCInterrupt,
              ovfInterrupt: timer1Config.ovfInterrupt,
              TCCRA: timer1Config.TCCRA,
              TCCRB: timer1Config.TCCRB,
              TCCRC: timer1Config.TCCRC,
              TCNT: timer1Config.TCNT,
              OCRA: timer1Config.OCRA,
              OCRB: timer1Config.OCRB,
              OCRC: 0x8c,
              ICR: timer1Config.ICR,
              TIFR: timer1Config.TIFR,
              TIMSK: timer1Config.TIMSK,
              compPortA: timer1Config.compPortA,
              compPinA: timer1Config.compPinA,
              compPortB: timer1Config.compPortB,
              compPinB: timer1Config.compPinB,
              compPortC: portBConfig.PORT,
              compPinC: 3,
              externalClockPort: timer1Config.externalClockPort,
              externalClockPin: timer1Config.externalClockPin,
              TOV: timer1Config.TOV,
              OCFA: timer1Config.OCFA,
              OCFB: timer1Config.OCFB,
              OCFC: 1 << 3,
              TOIE: timer1Config.TOIE,
              OCIEA: timer1Config.OCIEA,
              OCIEB: timer1Config.OCIEB,
              OCIEC: timer1Config.OCIEC,
            ));
        final portB = AVRIOPort(cpu, portBConfig);

        final nopCount = asm.lines.where((line) => line.bytes == '0000').length;
        final runner = TestProgramRunner(cpu);
        runner.runInstructions((asm.instructionCount - nopCount).toInt());
        expect(cpu.readData(TCNT1), equals(0x48));
        expect(portB.overrideMask & (1 << 3), equals(0));

        runner.runInstructions(1);
        expect(cpu.readData(TCNT1), equals(0x49));
        expect(portB.overrideMask & (1 << 3), equals(0));
      });

      test('should update OCR1A when setting TCNT to 0 (issue #111)', () {
        final asm = asmProgram('''
        CLR r1          ; r1 is our zero register
        LDI r16, 0x0    ; OCR1AH = 0x0;
        STS 0x89, r1    
        LDI r16, 0x8    ; OCR1AL = 0x8;
        STS 0x88, r16  
        ; Set waveform generation mode (WGM) to PWM Phase/Frequency Correct mode (9)
        LDI r16, 0x01   ; TCCR1A = (1 << WGM10);
        STS 0x80, r16  
        LDI r16, 0x11   ; TCCR1B = (1 << WGM13) | (1 << CS00);
        STS 0x81, r16  
        STS 0x85, r1    ; TCNT1H = 0x0;
        STS 0x84, r1    ; TCNT1L = 0x0;
        
        LDI r16, 0x5   ; OCR1AL = 0x5; // TCNT1 should read 0x0
        STS 0x88, r16  ; // TCNT1 should read 0x2 (going up)
        STS 0x84, r1   ; TCNT1L = 0x0;
        LDS r17, 0x84  ; // TCNT1 should read 0x1 (going up)
        LDS r18, 0x84  ; // TCNT1 should read 0x3 (going up)
        LDS r19, 0x84  ; // TCNT1 should read 0x5 (going down)
        LDS r20, 0x84  ; // TCNT1 should read 0x3 (going down)
      ''');
        final cpu = CPU(asm.program);

        AVRTimer(cpu, timer1Config);

        final runner = TestProgramRunner(cpu);
        runner.runInstructions(asm.instructionCount);

        expect(cpu.readData(R17), equals(0x1));
        expect(cpu.readData(R18), equals(0x3));
        expect(cpu.readData(R19), equals(0x5));
        expect(cpu.readData(R20), equals(0x3));
      });

      test('should mask the unused bits of OCR1A when using fixed top values',
          () {
        final cpu = CPU(Uint16List(0x1000));
        AVRTimer(cpu, timer1Config);
        cpu.writeData(TCCR1A, WGM10 | WGM11); // WGM: FastPWM, top 0x3ff
        cpu.writeData(TCCR1B, WGM12);
        cpu.writeData(OCR1AH, 0xff);
        cpu.writeData(OCR1A, 0xff);
        expect(cpu.readData(OCR1A), equals(0xff));
        expect(cpu.readData(OCR1AH), equals(0x03));
      });
    });
  });
  group('External clock', () {
    test('should count on the falling edge of T0 when CS=110', () {
      final cpu = CPU(Uint16List(0x1000));
      final port = AVRIOPort(cpu, portDConfig);
      AVRTimer(cpu, timer0Config);
      cpu.writeData(TCCR0B, CS02 | CS01); // Count on falling edge
      cpu.cycles = 1;
      cpu.tick();

      port.setPin(T0, true); // Rising edge
      cpu.cycles = 2;
      cpu.tick();
      expect(cpu.readData(TCNT0), equals(0));

      port.setPin(T0, false); // Falling edge
      cpu.cycles = 3;
      cpu.tick();
      expect(cpu.readData(TCNT0), equals(1));
    });

    test('should count on the rising edge of T0 when CS=111', () {
      final cpu = CPU(Uint16List(0x1000));
      final port = AVRIOPort(cpu, portDConfig);
      AVRTimer(cpu, timer0Config);
      cpu.writeData(TCCR0B, CS02 | CS01 | CS00); // Count on rising edge
      cpu.cycles = 1;
      cpu.tick();

      port.setPin(T0, true); // Rising edge
      cpu.cycles = 2;
      cpu.tick();
      expect(cpu.readData(TCNT0), equals(1));

      port.setPin(T0, false); // Falling edge
      cpu.cycles = 3;
      cpu.tick();
      expect(cpu.readData(TCNT0), equals(1));
    });
  });
}

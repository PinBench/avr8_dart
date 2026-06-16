import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:avr8_dart/src/cpu/cpu.dart';
import 'package:avr8_dart/src/peripherals/gpio.dart';
import 'package:avr8_dart/src/peripherals/timer_attiny.dart';

const attinyPortB = AVRPortConfig(
  PIN: 0x36,
  DDR: 0x37,
  PORT: 0x38,
  externalInterrupts: [],
);

const TCCR1 = 0x50; // attinyTimer1Config.TCCR1
const TCNT1 = 0x4f; // attinyTimer1Config.TCNT1
const OCR1A = 0x4e; // attinyTimer1Config.OCR1A
const OCR1B = 0x4b; // attinyTimer1Config.OCR1B
const OCR1C = 0x4d; // attinyTimer1Config.OCR1C
const TIFR = 0x58; // attinyTimer1Config.TIFR
const TIMSK = 0x59; // attinyTimer1Config.TIMSK

const TOV1 = 1 << 2; // attinyTimer1Config.TOV1
const OCF1A = 1 << 6; // attinyTimer1Config.OCF1A
const OCF1B = 1 << 5; // attinyTimer1Config.OCF1B
const OCIE1A = 1 << 6; // attinyTimer1Config.OCIE1A

const CTC1 = 1 << 7;
const CS10 = 1;
const CS13 = 1 << 3;

const SREG = 95;

class TimerContext {
  final CPU cpu;
  final ATtinyTimer1 timer;
  TimerContext(this.cpu, this.timer);
}

TimerContext createTimer() {
  final cpu = CPU(Uint16List(0x1000));
  AVRIOPort(cpu, attinyPortB);
  final timer = ATtinyTimer1(cpu, attinyTimer1Config);
  return TimerContext(cpu, timer);
}

void main() {
  group('ATtiny Timer1', () {
    test('should update timer every tick when prescaler is 1 (CS=1)', () {
      final ctx = createTimer();
      final cpu = ctx.cpu;
      cpu.writeData(TCCR1, CS10);
      cpu.cycles = 1;
      cpu.tick();
      cpu.cycles = 2;
      cpu.tick();
      expect(cpu.readData(TCNT1), equals(1));
    });

    test('should update timer every 128 ticks when prescaler is 128 (CS=8)', () {
      final ctx = createTimer();
      final cpu = ctx.cpu;
      cpu.writeData(TCCR1, CS13);
      cpu.cycles = 1;
      cpu.tick();
      cpu.cycles = 1 + 128;
      cpu.tick();
      expect(cpu.readData(TCNT1), equals(1));
    });

    test('should not update timer when disabled (CS=0)', () {
      final ctx = createTimer();
      final cpu = ctx.cpu;
      cpu.writeData(TCCR1, 0);
      cpu.cycles = 100000;
      cpu.tick();
      expect(cpu.readData(TCNT1), equals(0));
    });

    group('CTC mode', () {
      test('should clear timer on OCR1C match when CTC1 is set', () {
        final ctx = createTimer();
        final cpu = ctx.cpu;
        cpu.writeData(OCR1C, 9);
        cpu.writeData(TCCR1, CTC1 | CS10);
        cpu.writeData(TCNT1, 8);
        cpu.cycles = 1;
        cpu.tick();
        cpu.cycles = 1 + 3;
        cpu.tick();
        expect(cpu.readData(TCNT1), equals(1));
      });

      test('should set TOV1 when timer overflows past OCR1C', () {
        final ctx = createTimer();
        final cpu = ctx.cpu;
        cpu.writeData(OCR1C, 9);
        cpu.writeData(TCNT1, 9);
        cpu.writeData(TCCR1, CTC1 | CS10);
        cpu.cycles = 1;
        cpu.tick();
        cpu.cycles = 2;
        cpu.tick();
        expect(cpu.readData(TCNT1), equals(0));
        expect(cpu.data[TIFR] & TOV1, equals(TOV1));
      });

      test('should set OCF1A when timer matches OCR1A', () {
        final ctx = createTimer();
        final cpu = ctx.cpu;
        cpu.writeData(OCR1C, 249);
        cpu.writeData(OCR1A, 5);
        cpu.writeData(TCCR1, CTC1 | CS10);
        cpu.writeData(TCNT1, 4);
        cpu.cycles = 1;
        cpu.tick();
        cpu.cycles = 3;
        cpu.tick();
        expect(cpu.data[TIFR] & OCF1A, equals(OCF1A));
      });

      test('should set OCF1B when timer matches OCR1B', () {
        final ctx = createTimer();
        final cpu = ctx.cpu;
        cpu.writeData(OCR1C, 249);
        cpu.writeData(OCR1B, 10);
        cpu.writeData(TCCR1, CTC1 | CS10);
        cpu.writeData(TCNT1, 9);
        cpu.cycles = 1;
        cpu.tick();
        cpu.cycles = 3;
        cpu.tick();
        expect(cpu.data[TIFR] & OCF1B, equals(OCF1B));
      });

      test('should fire COMPA interrupt when enabled', () {
        final ctx = createTimer();
        final cpu = ctx.cpu;
        cpu.writeData(OCR1C, 249);
        cpu.writeData(OCR1A, 0);
        cpu.writeData(TCCR1, CTC1 | CS10);
        cpu.writeData(TCNT1, 248);
        cpu.writeData(TIMSK, OCIE1A);
        cpu.data[SREG] = 0x80;
        cpu.cycles = 1;
        cpu.tick();
        cpu.cycles = 3;
        cpu.tick();
        expect(cpu.pc, equals(0x03));
      });

      test('should overflow after a full period with prescaler 128', () {
        final ctx = createTimer();
        final cpu = ctx.cpu;
        cpu.writeData(TCCR1, CTC1 | CS13);
        cpu.writeData(OCR1C, 249);
        cpu.writeData(TIMSK, OCIE1A);
        cpu.data[SREG] = 0x80;

        // Full timer period: 250 * 128 = 32000 cycles
        cpu.cycles = 1;
        cpu.tick();
        cpu.cycles = 32001;
        cpu.tick();

        expect(cpu.data[TIFR] & TOV1, isNot(equals(0)));
      });
    });

    group('clearing interrupt flags', () {
      test('should clear TOV1 by writing 1 to TIFR', () {
        final ctx = createTimer();
        final cpu = ctx.cpu;
        cpu.writeData(OCR1C, 9);
        cpu.writeData(TCNT1, 9);
        cpu.writeData(TCCR1, CTC1 | CS10);
        cpu.cycles = 1;
        cpu.tick();
        cpu.cycles = 2;
        cpu.tick();
        expect(cpu.data[TIFR] & TOV1, equals(TOV1));
        cpu.writeData(TIFR, TOV1);
        expect(cpu.data[TIFR] & TOV1, equals(0));
      });
    });
  });
}

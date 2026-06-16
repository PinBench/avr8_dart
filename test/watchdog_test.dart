import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:avr8_dart/src/cpu/cpu.dart';
import 'package:avr8_dart/src/peripherals/clock.dart';
import 'package:avr8_dart/src/peripherals/watchdog.dart';
import 'test_utils.dart';

const R20 = 20;

const MCUSR = 0x54;
const WDRF = 1 << 3;

const WDTCSR = 0x60;
const WDP0 = 1 << 0;
const WDP1 = 1 << 1;
const WDP2 = 1 << 2;
const WDE = 1 << 3;
const WDCE = 1 << 4;
const WDP3 = 1 << 5;
const WDIE = 1 << 6;

const INT_WDT = 0xc;

void main() {
  group('Watchdog', () {
    test('should correctly calculate the prescaler from WDTCSR', () {
      final cpu = CPU(Uint16List(1024));
      final clock = AVRClock(cpu, 16000000, clockConfig);
      final watchdog = AVRWatchdog(cpu, watchdogConfig, clock);
      cpu.writeData(WDTCSR, WDCE | WDE);
      cpu.writeData(WDTCSR, 0);
      expect(watchdog.prescaler, equals(2048));
      cpu.writeData(WDTCSR, WDP2 | WDP1 | WDP0);
      expect(watchdog.prescaler, equals(256 * 1024));
      cpu.writeData(WDTCSR, WDP3 | WDP0);
      expect(watchdog.prescaler, equals(1024 * 1024));
    });

    test('should not change the prescaler unless WDCE is set', () {
      final cpu = CPU(Uint16List(1024));
      final clock = AVRClock(cpu, 16000000, clockConfig);
      final watchdog = AVRWatchdog(cpu, watchdogConfig, clock);
      cpu.writeData(WDTCSR, 0);
      expect(watchdog.prescaler, equals(2048));
      cpu.writeData(WDTCSR, WDP2 | WDP1 | WDP0);
      expect(watchdog.prescaler, equals(2048));

      cpu.writeData(WDTCSR, WDCE | WDE);
      cpu.cycles += 5; // WDCE should expire after 4 cycles
      cpu.writeData(WDTCSR, WDP2 | WDP1 | WDP0);
      expect(watchdog.prescaler, equals(2048));
    });

    test('should reset the CPU when the timer expires', () {
      final asm = asmProgram('''
    ; register addresses
    _REPLACE WDTCSR, $WDTCSR

    ; Setup watchdog
    ldi r16, ${WDE | WDCE}
    sts WDTCSR, r16
    ldi r16, $WDE
    sts WDTCSR, r16
    
    nop

    break
  ''');
      final cpu = CPU(asm.program);
      final clock = AVRClock(cpu, 16000000, clockConfig);
      final watchdog = AVRWatchdog(cpu, watchdogConfig, clock);
      final runner = TestProgramRunner(cpu);

      // Setup: enable watchdog timer
      runner.runInstructions(4);
      expect(watchdog.enabled, isTrue);

      // Now we skip 8ms. Watchdog shouldn't fire, yet
      cpu.cycles += 16000 * 8;
      runner.runInstructions(1);

      // Now we skip an extra 8ms. Watchdog should fire and reset!
      cpu.cycles += 16000 * 8;
      cpu.tick();
      expect(cpu.pc, equals(0));
      expect(cpu.readData(MCUSR), equals(WDRF));
    });

    test('should extend the watchdog timeout when executing a WDR instruction', () {
      final asm = asmProgram('''
    ; register addresses
    _REPLACE WDTCSR, $WDTCSR

    ; Setup watchdog
    ldi r16, ${WDE | WDCE}
    sts WDTCSR, r16
    ldi r16, $WDE
    sts WDTCSR, r16
    
    wdr
    nop

    break
  ''');
      final cpu = CPU(asm.program);
      final clock = AVRClock(cpu, 16000000, clockConfig);
      final watchdog = AVRWatchdog(cpu, watchdogConfig, clock);
      final runner = TestProgramRunner(cpu);

      // Setup: enable watchdog timer
      runner.runInstructions(4);
      expect(watchdog.enabled, isTrue);

      // Now we skip 8ms. Watchdog shouldn't fire, yet
      cpu.cycles += 16000 * 8;
      runner.runInstructions(1);
      expect(cpu.pc, isNot(equals(0)));

      // Now we skip an extra 8ms. We extended the timeout with WDR, so watchdog won't fire yet
      cpu.cycles += 16000 * 8;
      runner.runInstructions(1);
      expect(cpu.pc, isNot(equals(0)));

      // Finally, another 8ms bring us to 16ms since last WDR, and watchdog should fire
      cpu.cycles += 16000 * 8;
      cpu.tick();
      expect(cpu.pc, equals(0));
    });

    test('should fire an interrupt when the watchdog expires and WDIE is set', () {
      final asm = asmProgram('''
    ; register addresses
    _REPLACE WDTCSR, $WDTCSR

    ; Setup watchdog
    ldi r16, ${WDE | WDCE}
    sts WDTCSR, r16
    ldi r16, ${WDE | WDIE}
    sts WDTCSR, r16
    
    nop
    sei

    break
  ''');
      final cpu = CPU(asm.program);
      final clock = AVRClock(cpu, 16000000, clockConfig);
      final watchdog = AVRWatchdog(cpu, watchdogConfig, clock);
      final runner = TestProgramRunner(cpu);

      // Setup: enable watchdog timer
      runner.runInstructions(4);
      expect(watchdog.enabled, isTrue);

      // Now we skip 8ms. Watchdog shouldn't fire, yet
      cpu.cycles += 16000 * 8;
      runner.runInstructions(1);

      // Now we skip an extra 8ms. Watchdog should fire and jump to the interrupt handler
      cpu.cycles += 16000 * 8;
      runner.runInstructions(1);

      expect(cpu.pc, equals(INT_WDT));
      // The watchdog timer should also clean the WDIE bit, so next timeout will reset the MCU.
      expect(cpu.readData(WDTCSR) & WDIE, equals(0));
    });

    test('should not reset the CPU if the watchdog has been disabled', () {
      final asm = asmProgram('''
    ; register addresses
    _REPLACE WDTCSR, $WDTCSR

    ; Setup watchdog
    ldi r16, ${WDE | WDCE}
    sts WDTCSR, r16
    ldi r16, $WDE
    sts WDTCSR, r16
    
    ; disable watchdog
    ldi r16, ${WDE | WDCE}
    sts WDTCSR, r16
    ldi r16, 0
    sts WDTCSR, r16

    ldi r20, 55

    break
  ''');
      final cpu = CPU(asm.program);
      final clock = AVRClock(cpu, 16000000, clockConfig);
      final watchdog = AVRWatchdog(cpu, watchdogConfig, clock);
      final runner = TestProgramRunner(cpu);

      // Setup: enable watchdog timer
      runner.runInstructions(4);
      expect(watchdog.enabled, isTrue);

      // Now we skip 8ms. Watchdog shouldn't fire, yet. We disable it.
      cpu.cycles += 16000 * 8;
      runner.runInstructions(4);

      // Now we skip an extra 20ms. Watchdog shouldn't reset!
      cpu.cycles += 16000 * 20;
      runner.runInstructions(1);
      expect(cpu.pc, isNot(equals(0)));
      expect(cpu.data[R20], equals(55)); // assert that `ldi r20, 55` ran
    });
  });
}

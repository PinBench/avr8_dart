import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:avr8_dart/src/cpu/cpu.dart';
import 'package:avr8_dart/src/peripherals/adc.dart';
import 'test_utils.dart';

const R16 = 16;
const R17 = 17;

const ADMUX = 0x7c;
const REFS0 = 1 << 6;

const ADCSRA = 0x7a;
const ADEN = 1 << 7;
const ADSC = 1 << 6;
const ADPS0 = 1 << 0;
const ADPS1 = 1 << 1;
const ADPS2 = 1 << 2;

const ADCH = 0x79;
const ADCL = 0x78;

void main() {
  group('ADC', () {
    test('should successfuly perform an ADC conversion', () {
      final asm = asmProgram('''
    ; register addresses
    _REPLACE ADMUX, $ADMUX
    _REPLACE ADCSRA, $ADCSRA
    _REPLACE ADCH, $ADCH
    _REPLACE ADCL, $ADCL

    ; Configure mux - channel 0, reference: AVCC with external capacitor at AREF pin
    ldi r24, $REFS0
    sts ADMUX, r24

    ; Start conversion with 128 prescaler
    ldi r24, ${ADEN | ADSC | ADPS0 | ADPS1 | ADPS2}
    sts ADCSRA, r24

    ; Wait until conversion is complete
  waitComplete:
    lds r24, $ADCSRA
    andi r24, $ADSC
    brne waitComplete

    ; Read the result
    lds r16, $ADCL
    lds r17, $ADCH

    break
  ''');
      final cpu = CPU(asm.program);
      final adc = AVRADC(cpu, adcConfig);
      final runner = TestProgramRunner(cpu);

      bool onADCReadCalled = false;
      final originalOnADCRead = adc.onADCRead;
      adc.onADCRead = (config) {
        onADCReadCalled = true;
        expect((config as ADCMuxInputSingleEnded).channel, equals(0));
        expect(config.type, equals(ADCMuxInputType.SingleEnded));
        originalOnADCRead(config);
      };
      adc.channelValues[0] = 2.56; // should result in 2.56/5*1024 = 524

      // Setup
      runner.runInstructions(4);
      expect(onADCReadCalled, isTrue);

      // Run the "waitComplete" loop for a few cycles
      runner.runInstructions(12);

      cpu.cycles += 128 * 25; // skip to the end of the conversion
      cpu.tick();

      // Now read the result
      runner.runInstructions(5);

      final low = cpu.data[R16];
      final high = cpu.data[R17];
      expect((high << 8) | low, equals(524)); // 2.56 volts - see above
    });

    test('should read 0 when the ADC peripheral is not enabled', () {
      final asm = asmProgram('''
    ; register addresses
    _REPLACE ADMUX, $ADMUX
    _REPLACE ADCSRA, $ADCSRA
    _REPLACE ADCH, $ADCH
    _REPLACE ADCL, $ADCL

    ; Load some initial value into r16/r17 to make sure we actually read 0 later
    ldi r16, 0xff
    ldi r17, 0xff

    ; Configure mux - channel 0, reference: AVCC with external capacitor at AREF pin
    ldi r24, $REFS0
    sts ADMUX, r24

    ; Start conversion with 128 prescaler, but without enabling the ADC
    ldi r24, ${ADSC | ADPS0 | ADPS1 | ADPS2}
    sts ADCSRA, r24

    ; Wait until conversion is complete
  waitComplete:
    lds r24, $ADCSRA
    andi r24, $ADSC
    brne waitComplete

    ; Read the result
    lds r16, $ADCL
    lds r17, $ADCH

    break
  ''');
      final cpu = CPU(asm.program);
      final adc = AVRADC(cpu, adcConfig);
      final runner = TestProgramRunner(cpu, (cpu) {
        /* do nothing on break */
      });

      bool onADCReadCalled = false;
      final originalOnADCRead = adc.onADCRead;
      adc.onADCRead = (config) {
        onADCReadCalled = true;
        originalOnADCRead(config);
      };
      adc.channelValues[0] = 2.56; // should result in 2.56/5*1024 = 524

      // Setup
      runner.runInstructions(6);
      expect(onADCReadCalled, isFalse);

      // Run the "waitComplete" loop for a few cycles
      runner.runInstructions(12);

      cpu.cycles += 128 * 25; // skip to the end of the conversion
      cpu.tick();

      // Now read the result
      runner.runToBreak();

      final low = cpu.data[R16];
      final high = cpu.data[R17];
      expect((high << 8) | low, equals(0)); // We should read 0 since the ADC hasn't been enabled
    });
  });
}

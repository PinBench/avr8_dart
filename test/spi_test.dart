import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:avr8_dart/src/cpu/cpu.dart';
import 'package:avr8_dart/src/peripherals/spi.dart';
import 'test_utils.dart';

const R16 = 16;
const R17 = 17;

const FREQ_16MHZ = 16000000;

// CPU registers
const SREG = 95;

// SPI Registers
const SPCR = 0x4c;
const SPSR = 0x4d;
const SPDR = 0x4e;

// Register bit names
const SPR0 = 1;
const SPR1 = 2;
const CPOL = 4;
const CPHA = 8;
const MSTR = 0x10;
const DORD = 0x20;
const SPE = 0x40;
const SPIE = 0x80;
const WCOL = 0x40;
const SPIF = 0x80;
const SPI2X = 1;

void main() {
  group('SPI', () {
    test('should correctly calculate the frequency based on SPCR/SPST values',
        () {
      final cpu = CPU(Uint16List(1024));
      final spi = AVRSPI(cpu, spiConfig, FREQ_16MHZ);

      // Standard SPI speed:
      cpu.writeData(SPSR, 0);
      cpu.writeData(SPCR, 0);
      expect(spi.spiFrequency, equals(FREQ_16MHZ / 4));
      cpu.writeData(SPCR, SPR0);
      expect(spi.spiFrequency, equals(FREQ_16MHZ / 16));
      cpu.writeData(SPCR, SPR1);
      expect(spi.spiFrequency, equals(FREQ_16MHZ / 64));
      cpu.writeData(SPCR, SPR1 | SPR0);
      expect(spi.spiFrequency, equals(FREQ_16MHZ / 128));

      // Double SPI speed:
      cpu.writeData(SPSR, SPI2X);
      cpu.writeData(SPCR, 0);
      expect(spi.spiFrequency, equals(FREQ_16MHZ / 2));
      cpu.writeData(SPCR, SPR0);
      expect(spi.spiFrequency, equals(FREQ_16MHZ / 8));
      cpu.writeData(SPCR, SPR1);
      expect(spi.spiFrequency, equals(FREQ_16MHZ / 32));
      cpu.writeData(SPCR, SPR1 | SPR0);
      expect(spi.spiFrequency, equals(FREQ_16MHZ / 64));
    });

    test(
        'should correctly report the data order (MSB/LSB first), based on SPCR value',
        () {
      final cpu = CPU(Uint16List(1024));
      final spi = AVRSPI(cpu, spiConfig, FREQ_16MHZ);

      cpu.writeData(SPCR, 0);
      expect(spi.dataOrder, equals('msbFirst'));

      cpu.writeData(SPCR, DORD);
      expect(spi.dataOrder, equals('lsbFirst'));
    });

    test('should correctly report the SPI mode, based on SPCR value', () {
      final cpu = CPU(Uint16List(1024));
      final spi = AVRSPI(cpu, spiConfig, FREQ_16MHZ);

      cpu.writeData(SPCR, 0);
      expect(spi.spiMode, equals(0));

      cpu.writeData(SPCR, CPHA);
      expect(spi.spiMode, equals(1));

      cpu.writeData(SPCR, CPOL);
      expect(spi.spiMode, equals(2));

      cpu.writeData(SPCR, CPOL | CPHA);
      expect(spi.spiMode, equals(3));
    });

    test('should indicate slave/master operation, based on SPCR value', () {
      final cpu = CPU(Uint16List(1024));
      final spi = AVRSPI(cpu, spiConfig, FREQ_16MHZ);

      expect(spi.isMaster, isFalse);

      cpu.writeData(SPCR, MSTR);
      expect(spi.isMaster, isTrue);
    });

    test(
        'should call the `onByteTransfer` callback when initiating an SPI trasfer by writing to SPDR',
        () {
      final cpu = CPU(Uint16List(1024));
      final spi = AVRSPI(cpu, spiConfig, FREQ_16MHZ);
      int callCount = 0;
      int? receivedByte;
      spi.onByte = (value) {
        callCount++;
        receivedByte = value;
      };

      cpu.writeData(SPCR, SPE | MSTR);
      cpu.writeData(SPDR, 0x8f);

      expect(callCount, equals(1));
      expect(receivedByte, equals(0x8f));
    });

    test('should ignore SPDR writes when the SPE bit in SPCR is clear', () {
      final cpu = CPU(Uint16List(1024));
      final spi = AVRSPI(cpu, spiConfig, FREQ_16MHZ);
      int callCount = 0;
      spi.onByte = (value) {
        callCount++;
      };

      cpu.writeData(SPCR, MSTR);
      cpu.writeData(SPDR, 0x8f);

      expect(callCount, equals(0));
    });

    test('should transmit a byte successfully (integration)', () {
      // Based on code example from section 19.2 of the datasheet, page 172
      final asm = asmProgram('''
      ; register addresses
      _REPLACE SPCR, ${SPCR - 0x20}
      _REPLACE SPDR, ${SPDR - 0x20}
      _REPLACE SPSR, ${SPSR - 0x20}
      _REPLACE DDR_SPI, 0x4 ; PORTB

      SPI_MasterInit:
        ; Set MOSI and SCK output, all others input
        LDI r17, 0x28
        OUT DDR_SPI, r17
    
        ; Enable SPI, Master, set clock rate fck/16
        LDI r17, 0x51   ; (1<<SPE)|(1<<MSTR)|(1<<SPR0)
        OUT SPCR, r17

      SPI_MasterTransmit:
        LDI r16, 0xb8 ; byte to transmit
        OUT SPDR, r16

      Wait_Transmit:
        IN r16, SPSR
        SBRS r16, 7
        RJMP Wait_Transmit
      
      ; Now read the result into r17
        IN r17, SPDR
        BREAK
    ''');

      final cpu = CPU(asm.program);
      final spi = AVRSPI(cpu, spiConfig, FREQ_16MHZ);

      int? byteReceivedFromAsmCode;

      spi.onByte = (value) {
        byteReceivedFromAsmCode = value;
        cpu.addClockEvent(() => spi.completeTransfer(0x5b), spi.transferCycles);
      };

      final runner = TestProgramRunner(cpu, (cpu) {
        /* do nothing on break */
      });
      runner.runToBreak();

      // 16 cycles per clock * 8 bits = 128
      expect(cpu.cycles, greaterThanOrEqualTo(128));

      expect(byteReceivedFromAsmCode, equals(0xb8));
      expect(cpu.data[R17], equals(0x5b));
    });

    test(
        'should set the WCOL bit in SPSR if writing to SPDR while SPI is already transmitting',
        () {
      final cpu = CPU(Uint16List(1024));
      AVRSPI(cpu, spiConfig, FREQ_16MHZ);

      cpu.writeData(SPCR, SPE | MSTR);
      cpu.writeData(SPDR, 0x50);
      cpu.tick();
      expect(cpu.readData(SPSR) & WCOL, equals(0));

      cpu.writeData(SPDR, 0x51);
      expect(cpu.readData(SPSR) & WCOL, equals(WCOL));
    });

    test(
        'should clear the SPIF bit and fire an interrupt when SPI transfer completes',
        () {
      final cpu = CPU(Uint16List(1024));
      AVRSPI(cpu, spiConfig, FREQ_16MHZ);

      cpu.writeData(SPCR, SPE | SPIE | MSTR);
      cpu.writeData(SPDR, 0x50);
      cpu.data[SREG] = 0x80; // SREG: I-------

      // At this point, write shouldn't be complete yet
      cpu.cycles += 10;
      cpu.tick();
      expect(cpu.pc, equals(0));

      // 100 cycles later, it should (8 bits * 8 cycles per bit = 64).
      cpu.cycles += 100;
      cpu.tick();
      expect(cpu.data[SPSR] & SPIF, equals(0));
      expect(cpu.pc, equals(0x22)); // SPI Ready interrupt
    });

    test('should fire a pending SPI interrupt when SPIE flag is set', () {
      final cpu = CPU(Uint16List(1024));
      AVRSPI(cpu, spiConfig, FREQ_16MHZ);

      cpu.writeData(SPCR, SPE | MSTR);
      cpu.writeData(SPDR, 0x50);
      cpu.data[SREG] = 0x80; // SREG: I-------

      // Wait for transfer to complete (8 bits * 8 cycles per bit = 64).
      cpu.cycles += 64;
      cpu.tick();

      expect(cpu.data[SPSR] & SPIF, equals(SPIF));
      expect(cpu.pc, equals(0)); // Interrupt not taken (yet)

      // Enable the interrupt (SPIE)
      cpu.writeData(SPCR, SPE | MSTR | SPIE);
      cpu.tick();
      expect(cpu.pc, equals(0x22)); // SPI Ready interrupt
      expect(cpu.data[SPSR] & SPIF, equals(0));
    });

    test(
        'should should only update SPDR when tranfer finishes (double buffering)',
        () {
      final cpu = CPU(Uint16List(1024));
      final spi = AVRSPI(cpu, spiConfig, FREQ_16MHZ);
      spi.onByte = (value) {
        cpu.addClockEvent(() => spi.completeTransfer(0x88), spi.transferCycles);
      };

      cpu.writeData(SPCR, SPE | MSTR);
      cpu.writeData(SPDR, 0x8f);

      cpu.cycles = 10;
      cpu.tick();
      expect(cpu.readData(SPDR), equals(0));

      cpu.cycles = 32; // 4 cycles per bit * 8 bits = 32
      cpu.tick();
      expect(cpu.readData(SPDR), equals(0x88));
    });
  });
}

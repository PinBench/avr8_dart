import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:avr8_dart/src/cpu/cpu.dart';
import 'package:avr8_dart/src/peripherals/usart.dart';

const FREQ_16MHZ = 16000000;
const FREQ_11_0529MHZ = 11059200;

// CPU registers
const SREG = 95;

// USART0 Registers
const UCSR0A = 0xc0;
const UCSR0B = 0xc1;
const UCSR0C = 0xc2;
const UBRR0L = 0xc4;
const UBRR0H = 0xc5;
const UDR0 = 0xc6;

// Register bit names
const U2X0 = 2;
const TXEN = 8;
const RXEN = 16;
const UDRIE = 0x20;
const TXCIE = 0x40;
const RXC = 0x80;
const TXC = 0x40;
const UDRE = 0x20;
const USBS = 0x08;
const UPM0 = 0x10;
const UPM1 = 0x20;

// Interrupt address
const PC_INT_UDRE = 0x26;
const PC_INT_TXC = 0x28;
const UCSZ0 = 2;
const UCSZ1 = 4;
const UCSZ2 = 4;

void main() {
  group('USART', () {
    test('should correctly calculate the baudRate from UBRR', () {
      final cpu = CPU(Uint16List(1024));
      final usart = AVRUSART(cpu, usart0Config, FREQ_11_0529MHZ);
      cpu.writeData(UBRR0H, 0);
      cpu.writeData(UBRR0L, 5);
      expect(usart.baudRate, equals(115200));
    });

    test(
        'should correctly calculate the baudRate from UBRR in double-speed mode',
        () {
      final cpu = CPU(Uint16List(1024));
      final usart = AVRUSART(cpu, usart0Config, FREQ_16MHZ);
      cpu.writeData(UBRR0H, 3);
      cpu.writeData(UBRR0L, 64);
      cpu.writeData(UCSR0A, U2X0);
      expect(usart.baudRate, equals(2400));
    });

    test('should call onConfigurationChange when the baudRate changes', () {
      final cpu = CPU(Uint16List(1024));
      final usart = AVRUSART(cpu, usart0Config, FREQ_16MHZ);
      int callCount = 0;
      usart.onConfigurationChange = () {
        callCount++;
      };

      cpu.writeData(UBRR0H, 0);
      expect(callCount, equals(1));

      callCount = 0;
      cpu.writeData(UBRR0L, 5);
      expect(callCount, equals(1));

      callCount = 0;
      cpu.writeData(UCSR0A, U2X0);
      expect(callCount, equals(1));
    });

    group('bitsPerChar', () {
      test('should return 5-bits per byte when UCSZ = 0', () {
        final cpu = CPU(Uint16List(1024));
        final usart = AVRUSART(cpu, usart0Config, FREQ_16MHZ);
        cpu.writeData(UCSR0C, 0);
        expect(usart.bitsPerChar, equals(5));
      });

      test('should return 6-bits per byte when UCSZ = 1', () {
        final cpu = CPU(Uint16List(1024));
        final usart = AVRUSART(cpu, usart0Config, FREQ_16MHZ);
        cpu.writeData(UCSR0C, UCSZ0);
        expect(usart.bitsPerChar, equals(6));
      });

      test('should return 7-bits per byte when UCSZ = 2', () {
        final cpu = CPU(Uint16List(1024));
        final usart = AVRUSART(cpu, usart0Config, FREQ_16MHZ);
        cpu.writeData(UCSR0C, UCSZ1);
        expect(usart.bitsPerChar, equals(7));
      });

      test('should return 8-bits per byte when UCSZ = 3', () {
        final cpu = CPU(Uint16List(1024));
        final usart = AVRUSART(cpu, usart0Config, FREQ_16MHZ);
        cpu.writeData(UCSR0C, UCSZ0 | UCSZ1);
        expect(usart.bitsPerChar, equals(8));
      });

      test('should return 9-bits per byte when UCSZ = 7', () {
        final cpu = CPU(Uint16List(1024));
        final usart = AVRUSART(cpu, usart0Config, FREQ_16MHZ);
        cpu.writeData(UCSR0C, UCSZ0 | UCSZ1);
        cpu.writeData(UCSR0B, UCSZ2);
        expect(usart.bitsPerChar, equals(9));
      });

      test('should call onConfigurationChange when bitsPerChar change', () {
        final cpu = CPU(Uint16List(1024));
        final usart = AVRUSART(cpu, usart0Config, FREQ_16MHZ);
        int callCount = 0;
        usart.onConfigurationChange = () {
          callCount++;
        };

        cpu.writeData(UCSR0C, UCSZ0 | UCSZ1);
        expect(callCount, equals(1));

        callCount = 0;
        cpu.writeData(UCSR0B, UCSZ2);
        expect(callCount, equals(1));

        callCount = 0;
        cpu.writeData(UCSR0B, UCSZ2);
        expect(callCount, equals(0));
      });
    });

    group('stopBits', () {
      test('should return 1 when USBS = 0', () {
        final cpu = CPU(Uint16List(1024));
        final usart = AVRUSART(cpu, usart0Config, FREQ_16MHZ);
        expect(usart.stopBits, equals(1));
      });

      test('should return 2 when USBS = 1', () {
        final cpu = CPU(Uint16List(1024));
        final usart = AVRUSART(cpu, usart0Config, FREQ_16MHZ);
        cpu.writeData(UCSR0C, USBS);
        expect(usart.stopBits, equals(2));
      });
    });

    group('parityEnabled', () {
      test('should return false when UPM1 = 0', () {
        final cpu = CPU(Uint16List(1024));
        final usart = AVRUSART(cpu, usart0Config, FREQ_16MHZ);
        expect(usart.parityEnabled, isFalse);
      });

      test('should return true when UPM1 = 1', () {
        final cpu = CPU(Uint16List(1024));
        final usart = AVRUSART(cpu, usart0Config, FREQ_16MHZ);
        cpu.writeData(UCSR0C, UPM1);
        expect(usart.parityEnabled, isTrue);
      });
    });

    group('parityOdd', () {
      test('should return false when UPM0 = 0', () {
        final cpu = CPU(Uint16List(1024));
        final usart = AVRUSART(cpu, usart0Config, FREQ_16MHZ);
        expect(usart.parityOdd, isFalse);
      });

      test('should return true when UPM0 = 1', () {
        final cpu = CPU(Uint16List(1024));
        final usart = AVRUSART(cpu, usart0Config, FREQ_16MHZ);
        cpu.writeData(UCSR0C, UPM0);
        expect(usart.parityOdd, isTrue);
      });
    });

    test('should invoke onByteTransmit when UDR0 is written to', () {
      final cpu = CPU(Uint16List(1024));
      final usart = AVRUSART(cpu, usart0Config, FREQ_16MHZ);
      int? transmittedByte;
      usart.onByteTransmit = (value) {
        transmittedByte = value;
      };
      cpu.writeData(UCSR0B, TXEN);
      cpu.writeData(UDR0, 0x61);
      expect(transmittedByte, equals(0x61));
    });

    group('txEnable/rxEnable', () {
      test('txEnable should equal true when the transitter is enabled', () {
        final cpu = CPU(Uint16List(1024));
        final usart = AVRUSART(cpu, usart0Config, FREQ_16MHZ);
        usart.onByteTransmit = (v) {};
        expect(usart.txEnable, isFalse);
        cpu.writeData(UCSR0B, TXEN);
        expect(usart.txEnable, isTrue);
      });

      test('rxEnable should equal true when the receiver is enabled', () {
        final cpu = CPU(Uint16List(1024));
        final usart = AVRUSART(cpu, usart0Config, FREQ_16MHZ);
        usart.onByteTransmit = (v) {};
        expect(usart.rxEnable, isFalse);
        cpu.writeData(UCSR0B, RXEN);
        expect(usart.rxEnable, isTrue);
      });
    });

    group('tick()', () {
      test('should trigger data register empty interrupt if UDRE is set', () {
        final cpu = CPU(Uint16List(1024));
        AVRUSART(cpu, usart0Config, FREQ_16MHZ);
        cpu.writeData(UCSR0B, UDRIE | TXEN);
        cpu.data[SREG] = 0x80; // SREG: I-------
        cpu.tick();
        expect(cpu.pc, equals(PC_INT_UDRE));
        expect(cpu.cycles, equals(2));
        expect(cpu.data[UCSR0A] & UDRE, equals(0));
      });

      test('should trigger data TX Complete interrupt if TXCIE is set', () {
        final cpu = CPU(Uint16List(1024));
        AVRUSART(cpu, usart0Config, FREQ_16MHZ);
        cpu.writeData(UCSR0B, TXCIE | TXEN);
        cpu.writeData(UDR0, 0x61);
        cpu.data[SREG] = 0x80; // SREG: I-------
        cpu.cycles = 1000000;
        cpu.tick();
        expect(cpu.pc, equals(PC_INT_TXC));
        expect(cpu.cycles, equals(1000000 + 2));
        expect(cpu.data[UCSR0A] & TXC, equals(0));
      });

      test(
          'should not trigger data TX Complete interrupt if UDR was not written to',
          () {
        final cpu = CPU(Uint16List(1024));
        AVRUSART(cpu, usart0Config, FREQ_16MHZ);
        cpu.writeData(UCSR0B, TXCIE | TXEN);
        cpu.data[SREG] = 0x80; // SREG: I-------
        cpu.tick();
        expect(cpu.pc, equals(0));
        expect(cpu.cycles, equals(0));
      });

      test('should not trigger any interrupt if interrupts are disabled', () {
        final cpu = CPU(Uint16List(1024));
        AVRUSART(cpu, usart0Config, FREQ_16MHZ);
        cpu.writeData(UCSR0B, UDRIE | TXEN);
        cpu.writeData(UDR0, 0x61);
        cpu.data[SREG] = 0; // SREG: 0 (disable interrupts)
        cpu.cycles = 1000000;
        cpu.tick();
        expect(cpu.pc, equals(0));
        expect(cpu.cycles, equals(1000000));
        expect(cpu.data[UCSR0A], equals(TXC | UDRE));
      });
    });

    group('onLineTransmit', () {
      test(
          'should call onLineTransmit with the current line buffer after every newline',
          () {
        final cpu = CPU(Uint16List(1024));
        final usart = AVRUSART(cpu, usart0Config, FREQ_16MHZ);
        String? transmittedLine;
        usart.onLineTransmit = (value) {
          transmittedLine = value;
        };
        cpu.writeData(UCSR0B, TXEN);
        cpu.writeData(UDR0, 0x48); // 'H'
        cpu.writeData(UDR0, 0x65); // 'e'
        cpu.writeData(UDR0, 0x6c); // 'l'
        cpu.writeData(UDR0, 0x6c); // 'l'
        cpu.writeData(UDR0, 0x6f); // 'o'
        cpu.writeData(UDR0, 0xa); // '\n'
        expect(transmittedLine, equals('Hello'));
      });

      test('should not call onLineTransmit if no newline was received', () {
        final cpu = CPU(Uint16List(1024));
        final usart = AVRUSART(cpu, usart0Config, FREQ_16MHZ);
        String? transmittedLine;
        usart.onLineTransmit = (value) {
          transmittedLine = value;
        };
        cpu.writeData(UCSR0B, TXEN);
        cpu.writeData(UDR0, 0x48); // 'H'
        cpu.writeData(UDR0, 0x69); // 'i'
        expect(transmittedLine, isNull);
      });

      test('should clear the line buffer after each call to onLineTransmit',
          () {
        final cpu = CPU(Uint16List(1024));
        final usart = AVRUSART(cpu, usart0Config, FREQ_16MHZ);
        String? transmittedLine;
        usart.onLineTransmit = (value) {
          transmittedLine = value;
        };
        cpu.writeData(UCSR0B, TXEN);
        cpu.writeData(UDR0, 0x48); // 'H'
        cpu.writeData(UDR0, 0x69); // 'i'
        cpu.writeData(UDR0, 0xa); // '\n'
        cpu.writeData(UDR0, 0x74); // 't'
        cpu.writeData(UDR0, 0x68); // 'h'
        cpu.writeData(UDR0, 0x65); // 'e'
        cpu.writeData(UDR0, 0x72); // 'r'
        cpu.writeData(UDR0, 0x65); // 'e'
        cpu.writeData(UDR0, 0xa); // '\n'
        expect(transmittedLine, equals('there'));
      });
    });

    group('writeByte', () {
      test('should return false if called when RX is busy', () {
        final cpu = CPU(Uint16List(1024));
        final usart = AVRUSART(cpu, usart0Config, FREQ_16MHZ);
        cpu.writeData(UCSR0B, RXEN);
        cpu.writeData(UBRR0L, 103); // baud: 9600
        expect(usart.writeByte(10), isTrue);
        expect(usart.writeByte(10), isFalse);
        cpu.tick();
        expect(usart.writeByte(10), isFalse);
      });
    });

    group('Integration tests', () {
      test('should set the TXC bit after ~1.04mS when baud rate set to 9600',
          () {
        final cpu = CPU(Uint16List(1024));
        AVRUSART(cpu, usart0Config, FREQ_16MHZ);
        cpu.writeData(UCSR0B, TXEN);
        cpu.writeData(UBRR0L, 103); // baud: 9600
        cpu.writeData(UDR0, 0x48); // 'H'
        cpu.cycles += 16000; // 1ms
        cpu.tick();
        expect(cpu.data[UCSR0A] & TXC, equals(0));
        cpu.cycles += 800; // 0.05ms
        cpu.tick();
        expect(cpu.data[UCSR0A] & TXC, equals(TXC));
      });

      test(
          'should be ready to receive the next byte after ~1.04ms when baudrate set to 9600',
          () {
        final cpu = CPU(Uint16List(1024));
        final usart = AVRUSART(cpu, usart0Config, FREQ_16MHZ);
        int callCount = 0;
        usart.onRxComplete = () {
          callCount++;
        };
        cpu.writeData(UCSR0B, RXEN);
        cpu.writeData(UBRR0L, 103); // baud: 9600
        expect(usart.writeByte(0x42), isTrue);
        cpu.cycles += 16000; // 1ms
        cpu.tick();
        expect(cpu.data[UCSR0A] & RXC, equals(0)); // byte not received yet
        expect(usart.rxBusy, isTrue);
        expect(callCount, equals(0));
        cpu.cycles += 800; // 0.05ms
        cpu.tick();
        expect(cpu.data[UCSR0A] & RXC, equals(RXC));
        expect(usart.rxBusy, isFalse);
        expect(callCount, equals(1));
        expect(cpu.readData(UDR0), equals(0x42));
        expect(cpu.readData(UDR0), equals(0));
      });
    });
  });
}

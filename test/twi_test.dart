import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:avr8_dart/src/cpu/cpu.dart';
import 'package:avr8_dart/src/peripherals/twi.dart';

const FREQ_16MHZ = 16000000;

// CPU registers
const SREG = 95;

// TWI Registers
const TWBR = 0xb8;
const TWSR = 0xb9;
const TWDR = 0xbb;
const TWCR = 0xbc;

// Register bit names
const TWIE = 1;
const TWEN = 4;
const TWSTO = 0x10;
const TWSTA = 0x20;
const TWINT = 0x80;

class MockTWIEventHandler implements TWIEventHandler {
  final AVRTWI twi;
  
  MockTWIEventHandler(this.twi);

  int startCallCount = 0;
  bool? startRepeated;
  int stopCallCount = 0;
  int connectToSlaveCallCount = 0;
  int? connectToSlaveAddr;
  bool? connectToSlaveWrite;

  @override
  void start(bool repeated) {
    startCallCount++;
    startRepeated = repeated;
    twi.completeStart();
  }

  @override
  void stop() {
    stopCallCount++;
    twi.completeStop();
  }

  @override
  void connectToSlave(int addr, bool write) {
    connectToSlaveCallCount++;
    connectToSlaveAddr = addr;
    connectToSlaveWrite = write;
    twi.completeConnect(false);
  }

  @override
  void writeByte(int value) {
    twi.completeWrite(false);
  }

  @override
  void readByte(bool ack) {
    twi.completeRead(0xff);
  }
}

void main() {
  group('TWI', () {
    test('should correctly calculate the sclFrequency from TWBR', () {
      final cpu = CPU(Uint16List(1024));
      final twi = AVRTWI(cpu, twiConfig, FREQ_16MHZ);
      cpu.writeData(TWBR, 0x48);
      cpu.writeData(TWSR, 0); // prescaler: 1
      expect(twi.sclFrequency, equals(100000));
    });

    test('should take the prescaler into consideration when calculating sclFrequency', () {
      final cpu = CPU(Uint16List(1024));
      final twi = AVRTWI(cpu, twiConfig, FREQ_16MHZ);
      cpu.writeData(TWBR, 0x03);
      cpu.writeData(TWSR, 0x01); // prescaler: 4
      expect(twi.sclFrequency, equals(400000));
    });

    test('should trigger data an interrupt if TWINT is set', () {
      final cpu = CPU(Uint16List(1024));
      final twi = AVRTWI(cpu, twiConfig, FREQ_16MHZ);
      cpu.writeData(TWCR, TWIE);
      cpu.data[SREG] = 0x80; // SREG: I-------
      twi.completeStart(); // This will set the TWINT flag
      cpu.tick();
      expect(cpu.pc, equals(0x30)); // 2-wire Serial Interface Vector
      expect(cpu.cycles, equals(2));
      expect(cpu.data[TWCR] & TWINT, equals(0));
    });

    group('Master mode', () {
      test('should call the startEvent handler when TWSTA bit is written 1', () {
        final cpu = CPU(Uint16List(1024));
        final twi = AVRTWI(cpu, twiConfig, FREQ_16MHZ);
        final mockHandler = MockTWIEventHandler(twi);
        twi.eventHandler = mockHandler;
        
        cpu.writeData(TWCR, TWINT | TWSTA | TWEN);
        cpu.cycles++;
        cpu.tick();
        
        expect(mockHandler.startCallCount, equals(1));
        expect(mockHandler.startRepeated, isFalse);
      });

      test('should connect successfully in case of repeated start (issue #91)', () {
        final cpu = CPU(Uint16List(1024));
        final twi = AVRTWI(cpu, twiConfig, FREQ_16MHZ);
        final mockHandler = MockTWIEventHandler(twi);
        twi.eventHandler = mockHandler;

        // Start condition
        cpu.writeData(TWCR, TWINT | TWSTA | TWEN);
        cpu.cycles++;
        cpu.tick();

        // Repeated start
        mockHandler.startCallCount = 0;
        cpu.writeData(TWCR, TWINT | TWSTA | TWEN);
        cpu.cycles++;
        cpu.tick();
        expect(mockHandler.startCallCount, equals(1));
        expect(mockHandler.startRepeated, isTrue);

        // Now try to connect...
        cpu.writeData(TWDR, 0x80); // Address 0x40, write mode
        cpu.writeData(TWCR, TWINT | TWEN);
        cpu.cycles++;
        cpu.tick();
        expect(mockHandler.connectToSlaveCallCount, equals(1));
        expect(mockHandler.connectToSlaveAddr, equals(0x40));
        expect(mockHandler.connectToSlaveWrite, isTrue);
      });
    });
  });
}

import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:avr8_dart/src/cpu/cpu.dart';
import 'package:avr8_dart/src/peripherals/twi.dart';
import 'test_utils.dart';

const R16 = 16;
const R17 = 17;
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
const TWEA = 0x40;
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

    test(
        'should take the prescaler into consideration when calculating sclFrequency',
        () {
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
      test('should call the startEvent handler when TWSTA bit is written 1',
          () {
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

      test('should transmit a byte to a slave', () {
        final asm = asmProgram('''
          ; register addresses
          _REPLACE TWSR, $TWSR
          _REPLACE TWDR, $TWDR
          _REPLACE TWCR, $TWCR
          
          ; TWCR bits
          _REPLACE TWEN, $TWEN
          _REPLACE TWSTO, $TWSTO
          _REPLACE TWSTA, $TWSTA
          _REPLACE TWINT, $TWINT

          ; TWSR states
          _REPLACE START, 0x8         ; TWI start
          _REPLACE MT_SLA_ACK, 0x18   ; Slave Adresss ACK has been received
          _REPLACE MT_DATA_ACK, 0x28  ; Data has been transmitted and ACK has been received

          ; Send start condition
          ldi r16, TWEN
          sbr r16, TWSTA
          sbr r16, TWINT
          sts TWCR, r16

          ; Wait for TWINT Flag set. This indicates that the START condition has been transmitted
          call wait_for_twint
          
          ; Check value of TWI Status Register. Mask prescaler bits. If status different from START go to ERROR
          lds r16, TWSR
          andi r16, 0xf8
          cpi r16, START
          brne error

          ; Load SLA_W into TWDR Register. Clear TWINT bit in TWCR to start transmission of address
          ; 0x44 = Address 0x22, write mode (R/W bit clear)
          _REPLACE SLA_W, 0x44
          ldi r16, SLA_W
          sts TWDR, r16
          ldi r16, TWINT
          sbr r16, TWEN
          sts TWCR, r16

          ; Wait for TWINT Flag set. This indicates that the SLA+W has been transmitted, and ACK/NACK has been received.
          call wait_for_twint

          ; Check value of TWI Status Register. Mask prescaler bits. If status different from MT_SLA_ACK go to ERROR
          lds r16, TWSR
          andi r16, 0xf8
          cpi r16, MT_SLA_ACK
          brne error

          ; Load DATA into TWDR Register. Clear TWINT bit in TWCR to start transmission of data
          _REPLACE DATA, 0x55
          ldi r16, DATA
          sts TWDR, r16
          ldi r16, TWINT
          sbr r16, TWEN
          sts TWCR, r16

          ; Wait for TWINT Flag set. This indicates that the DATA has been transmitted, and ACK/NACK has been received
          call wait_for_twint

          ; Check value of TWI Status Register. Mask prescaler bits. If status different from MT_DATA_ACK go to ERROR
          lds r16, TWSR
          andi r16, 0xf8
          cpi r16, MT_DATA_ACK
          brne error

          ; Transmit STOP condition
          ldi r16, TWINT
          sbr r16, TWEN
          sbr r16, TWSTO
          sts TWCR, r16

          ; Wait for TWINT Flag set. This indicates that the STOP condition has been sent
          call wait_for_twint

          ; Check value of TWI Status Register. The masked value should be 0xf8 once done
          lds r16, TWSR
          andi r16, 0xf8
          cpi r16, 0xf8
          brne error

          ; Indicate success by loading 0x42 into r17
          ldi r17, 0x42

          loop:
          jmp loop

          ; Busy-waits for the TWINT flag to be set
          wait_for_twint:
          lds r16, TWCR
          andi r16, TWINT
          breq wait_for_twint
          ret

          ; In case of an error, toggle a breakpoint
          error:
          break
        ''');
        final cpu = CPU(asm.program);
        final twi = AVRTWI(cpu, twiConfig, FREQ_16MHZ);
        final runner = TestProgramRunner(cpu, (cpu) {});

        bool startCalled = false;
        bool stopCalled = false;
        bool connectCalled = false;
        int? connectedAddr;
        bool? connectedWrite;
        bool writeCalled = false;
        int? writtenByte;

        twi.eventHandler = _IntegrationEventHandler(
          onStart: (repeated) {
            startCalled = true;
            expect(repeated, isFalse);
          },
          onStop: () {
            stopCalled = true;
          },
          onConnect: (addr, write) {
            connectCalled = true;
            connectedAddr = addr;
            connectedWrite = write;
          },
          onWrite: (value) {
            writeCalled = true;
            writtenByte = value;
          },
          onRead: (ack) {},
        );

        // Step 1: wait for start condition
        runner.runInstructions(4);
        expect(startCalled, isTrue);

        runner.runInstructions(16);
        twi.completeStart();

        // Step 2: wait for slave connect in write mode
        runner.runInstructions(16);
        expect(connectCalled, isTrue);
        expect(connectedAddr, equals(0x22));
        expect(connectedWrite, isTrue);

        runner.runInstructions(16);
        twi.completeConnect(true);

        // Step 3: wait for first data byte
        runner.runInstructions(16);
        expect(writeCalled, isTrue);
        expect(writtenByte, equals(0x55));

        runner.runInstructions(16);
        twi.completeWrite(true);

        // Step 4: wait for stop condition
        runner.runInstructions(16);
        expect(stopCalled, isTrue);

        runner.runInstructions(16);
        twi.completeStop();

        // Step 5: wait for the assembly code to indicate success by settings r17 to 0x42
        runner.runInstructions(16);
        expect(cpu.data[R17], equals(0x42));
      });

      test('should successfully receive a byte from a slave', () {
        final asm = asmProgram('''
          ; register addresses
          _REPLACE TWSR, $TWSR
          _REPLACE TWDR, $TWDR
          _REPLACE TWCR, $TWCR
          
          ; TWCR bits
          _REPLACE TWEN, $TWEN
          _REPLACE TWSTO, $TWSTO
          _REPLACE TWSTA, $TWSTA
          _REPLACE TWEA, $TWEA
          _REPLACE TWINT, $TWINT

          ; TWSR states
          _REPLACE START, 0x8         ; TWI start
          _REPLACE MT_SLAR_ACK, 0x40  ; Slave Adresss ACK has been received
          _REPLACE MT_DATA_RECV, 0x50 ; Data has been received
          _REPLACE MT_DATA_RECV_NACK, 0x58 ; Data has been received, NACK has been returned

          ; Send start condition
          ldi r16, TWEN
          sbr r16, TWSTA
          sbr r16, TWINT
          sts TWCR, r16

          ; Wait for TWINT Flag set. This indicates that the START condition has been transmitted
          call wait_for_twint
          
          ; Check value of TWI Status Register. Mask prescaler bits. If status different from START go to ERROR
          lds r16, TWSR
          andi r16, 0xf8
          ldi r18, START
          cpse r16, r18
          jmp error   ; only jump if r16 != r18 (START)

          ; Load SLA_R into TWDR Register. Clear TWINT bit in TWCR to start transmission of address
          ; 0xa1 = Address 0x50, read mode (R/W bit set)
          _REPLACE SLA_R, 0xa1
          ldi r16, SLA_R
          sts TWDR, r16
          ldi r16, TWINT
          sbr r16, TWEN
          sts TWCR, r16

          ; Wait for TWINT Flag set. This indicates that the SLA+W has been transmitted, and ACK/NACK has been received.
          call wait_for_twint

          ; Check value of TWI Status Register. Mask prescaler bits. If status different from MT_SLA_ACK go to ERROR
          lds r16, TWSR
          andi r16, 0xf8
          cpi r16, MT_SLAR_ACK
          brne error

          ; Clear TWINT bit in TWCR to receive the next byte, set TWEA to send ACK
          ldi r16, TWINT
          sbr r16, TWEA
          sbr r16, TWEN
          sts TWCR, r16

          ; Wait for TWINT Flag set. This indicates that the DATA has been received, and ACK has been transmitted
          call wait_for_twint

          ; Check value of TWI Status Register. Mask prescaler bits. If status different from MT_DATA_RECV go to ERROR
          lds r16, TWSR
          andi r16, 0xf8
          cpi r16, MT_DATA_RECV
          brne error

          ; Validate that we recieved the desired data - first byte should be 0x66
          lds r16, TWDR
          cpi r16, 0x66
          brne error

          ; Clear TWINT bit in TWCR to receive the next byte, this time we don't ACK
          ldi r16, TWINT
          sbr r16, TWEN
          sts TWCR, r16

          ; Wait for TWINT Flag set. This indicates that the DATA has been received, and NACK has been transmitted
          call wait_for_twint

          ; Check value of TWI Status Register. Mask prescaler bits. If status different from MT_DATA_RECV_NACK go to ERROR
          lds r16, TWSR
          andi r16, 0xf8
          cpi r16, MT_DATA_RECV_NACK
          brne error

          ; Validate that we recieved the desired data - second byte should be 0x77
          lds r16, TWDR
          cpi r16, 0x77
          brne error

          ; Transmit STOP condition
          ldi r16, TWINT
          sbr r16, TWEN
          sbr r16, TWSTO
          sts TWCR, r16

          ; Wait for TWINT Flag set. This indicates that the STOP condition has been sent
          call wait_for_twint

          ; Check value of TWI Status Register. The masked value should be 0xf8 once done
          lds r16, TWSR
          andi r16, 0xf8
          cpi r16, 0xf8
          brne error

          ; Indicate success by loading 0x42 into r17
          ldi r17, 0x42

          loop:
          jmp loop

          ; Busy-waits for the TWINT flag to be set
          wait_for_twint:
          lds r16, TWCR
          andi r16, TWINT
          breq wait_for_twint
          ret

          ; In case of an error, toggle a breakpoint
          error:
          break
        ''');
        final cpu = CPU(asm.program);
        final twi = AVRTWI(cpu, twiConfig, FREQ_16MHZ);
        final runner = TestProgramRunner(cpu, (cpu) {});

        bool startCalled = false;
        bool stopCalled = false;
        bool connectCalled = false;
        int? connectedAddr;
        bool? connectedWrite;
        bool readCalled1 = false;
        bool? readAck1;
        bool readCalled2 = false;
        bool? readAck2;

        twi.eventHandler = _IntegrationEventHandler(
          onStart: (repeated) {
            startCalled = true;
            expect(repeated, isFalse);
          },
          onStop: () {
            stopCalled = true;
          },
          onConnect: (addr, write) {
            connectCalled = true;
            connectedAddr = addr;
            connectedWrite = write;
          },
          onWrite: (value) {},
          onRead: (ack) {
            if (!readCalled1) {
              readCalled1 = true;
              readAck1 = ack;
            } else {
              readCalled2 = true;
              readAck2 = ack;
            }
          },
        );

        // Step 1: wait for start condition
        runner.runInstructions(4);
        expect(startCalled, isTrue);

        runner.runInstructions(16);
        twi.completeStart();

        // Step 2: wait for slave connect in read mode
        runner.runInstructions(16);
        expect(connectCalled, isTrue);
        expect(connectedAddr, equals(0x50));
        expect(connectedWrite, isFalse);

        runner.runInstructions(16);
        twi.completeConnect(true);

        // Step 3: send the first byte to the master, expect ack
        runner.runInstructions(16);
        expect(readCalled1, isTrue);
        expect(readAck1, isTrue);

        runner.runInstructions(16);
        twi.completeRead(0x66);

        // Step 4: send the first byte to the master, expect nack
        runner.runInstructions(16);
        expect(readCalled2, isTrue);
        expect(readAck2, isFalse);

        runner.runInstructions(16);
        twi.completeRead(0x77);

        // Step 5: wait for stop condition
        runner.runInstructions(24);
        expect(stopCalled, isTrue);

        runner.runInstructions(16);
        twi.completeStop();

        // Step 6: wait for the assembly code to indicate success by settings r17 to 0x42
        runner.runInstructions(16);
        expect(cpu.data[R17], equals(0x42));
      });

      test('should connect successfully in case of repeated start (issue #91)',
          () {
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

class _IntegrationEventHandler implements TWIEventHandler {
  final void Function(bool repeated) onStart;
  final void Function() onStop;
  final void Function(int addr, bool write) onConnect;
  final void Function(int value) onWrite;
  final void Function(bool ack) onRead;

  _IntegrationEventHandler({
    required this.onStart,
    required this.onStop,
    required this.onConnect,
    required this.onWrite,
    required this.onRead,
  });

  @override
  void start(bool repeated) => onStart(repeated);

  @override
  void stop() => onStop();

  @override
  void connectToSlave(int addr, bool write) => onConnect(addr, write);

  @override
  void writeByte(int value) => onWrite(value);

  @override
  void readByte(bool ack) => onRead(ack);
}

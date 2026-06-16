import '../cpu/cpu.dart';

abstract class TWIEventHandler {
  void start(bool repeated);
  void stop();
  void connectToSlave(int addr, bool write);
  void writeByte(int value);
  void readByte(bool ack);
}

class TWIConfig {
  final int twiInterrupt;
  final int TWBR;
  final int TWCR;
  final int TWSR;
  final int TWDR;
  final int TWAR;
  final int TWAMR;

  const TWIConfig({
    required this.twiInterrupt,
    required this.TWBR,
    required this.TWCR,
    required this.TWSR,
    required this.TWDR,
    required this.TWAR,
    required this.TWAMR,
  });
}

// Register bits:
const TWCR_TWINT = 0x80; // TWI Interrupt Flag
const TWCR_TWEA = 0x40; // TWI Enable Acknowledge Bit
const TWCR_TWSTA = 0x20; // TWI START Condition Bit
const TWCR_TWSTO = 0x10; // TWI STOP Condition Bit
const TWCR_TWWC = 0x8; //TWI Write Collision Flag
const TWCR_TWEN = 0x4; //  TWI Enable Bit
const TWCR_TWIE = 0x1; // TWI Interrupt Enable
const TWSR_TWS_MASK = 0xf8; // TWI Status
const TWSR_TWPS1 = 0x2; // TWI Prescaler Bits
const TWSR_TWPS0 = 0x1; // TWI Prescaler Bits
const TWSR_TWPS_MASK = TWSR_TWPS1 | TWSR_TWPS0; // TWI Prescaler mask
const TWAR_TWA_MASK = 0xfe; //  TWI (Slave) Address Register
const TWAR_TWGCE = 0x1; // TWI General Call Recognition Enable Bit

const STATUS_BUS_ERROR = 0x0;
const STATUS_TWI_IDLE = 0xf8;
// Master states
const STATUS_START = 0x08;
const STATUS_REPEATED_START = 0x10;
const STATUS_SLAW_ACK = 0x18;
const STATUS_SLAW_NACK = 0x20;
const STATUS_DATA_SENT_ACK = 0x28;
const STATUS_DATA_SENT_NACK = 0x30;
const STATUS_DATA_LOST_ARBITRATION = 0x38;
const STATUS_SLAR_ACK = 0x40;
const STATUS_SLAR_NACK = 0x48;
const STATUS_DATA_RECEIVED_ACK = 0x50;
const STATUS_DATA_RECEIVED_NACK = 0x58;

const twiConfig = TWIConfig(
  twiInterrupt: 0x30,
  TWBR: 0xb8,
  TWSR: 0xb9,
  TWAR: 0xba,
  TWDR: 0xbb,
  TWCR: 0xbc,
  TWAMR: 0xbd,
);

class NoopTWIEventHandler implements TWIEventHandler {
  final AVRTWI twi;

  NoopTWIEventHandler(this.twi);

  @override
  void start(bool repeated) {
    twi.completeStart();
  }

  @override
  void stop() {
    twi.completeStop();
  }

  @override
  void connectToSlave(int addr, bool write) {
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

class AVRTWI {
  final CPU cpu;
  final TWIConfig config;
  final int freqHz;

  late TWIEventHandler eventHandler;
  bool busy = false;

  late final AVRInterruptConfig TWI;

  AVRTWI(this.cpu, this.config, this.freqHz) {
    eventHandler = NoopTWIEventHandler(this);

    TWI = AVRInterruptConfig(
      address: config.twiInterrupt,
      flagRegister: config.TWCR,
      flagMask: TWCR_TWINT,
      enableRegister: config.TWCR,
      enableMask: TWCR_TWIE,
    );

    updateStatus(STATUS_TWI_IDLE);

    cpu.writeHooks[config.TWCR] =
        (int value, int oldValue, int addr, int mask) {
      cpu.data[config.TWCR] = value;
      final clearInt = (value & TWCR_TWINT) != 0;
      cpu.clearInterruptByFlag(TWI, value);
      cpu.updateInterruptEnable(TWI, value);

      final currentStatus = status;
      if (clearInt && (value & TWCR_TWEN) != 0 && !busy) {
        final twdrValue = cpu.data[config.TWDR];
        cpu.addClockEvent(() {
          if ((value & TWCR_TWSTA) != 0) {
            busy = true;
            eventHandler.start(currentStatus != STATUS_TWI_IDLE);
          } else if ((value & TWCR_TWSTO) != 0) {
            busy = true;
            eventHandler.stop();
          } else if (currentStatus == STATUS_START ||
              currentStatus == STATUS_REPEATED_START) {
            busy = true;
            eventHandler.connectToSlave(twdrValue >> 1, (twdrValue & 0x1) == 0);
          } else if (currentStatus == STATUS_SLAW_ACK ||
              currentStatus == STATUS_DATA_SENT_ACK) {
            busy = true;
            eventHandler.writeByte(twdrValue);
          } else if (currentStatus == STATUS_SLAR_ACK ||
              currentStatus == STATUS_DATA_RECEIVED_ACK) {
            busy = true;
            final ack = (value & TWCR_TWEA) != 0;
            eventHandler.readByte(ack);
          }
        }, 0);
        return true;
      }
      return false; // Not handled or default memory logic
    };
  }

  int get prescaler {
    switch (cpu.data[config.TWSR] & TWSR_TWPS_MASK) {
      case 0:
        return 1;
      case 1:
        return 4;
      case 2:
        return 16;
      case 3:
        return 64;
    }
    throw Exception('Invalid prescaler value!');
  }

  double get sclFrequency {
    return freqHz / (16 + 2 * cpu.data[config.TWBR] * prescaler);
  }

  void completeStart() {
    busy = false;
    updateStatus(
        status == STATUS_TWI_IDLE ? STATUS_START : STATUS_REPEATED_START);
  }

  void completeStop() {
    busy = false;
    cpu.data[config.TWCR] &= ~TWCR_TWSTO;
    updateStatus(STATUS_TWI_IDLE);
  }

  void completeConnect(bool ack) {
    busy = false;
    if ((cpu.data[config.TWDR] & 0x1) != 0) {
      updateStatus(ack ? STATUS_SLAR_ACK : STATUS_SLAR_NACK);
    } else {
      updateStatus(ack ? STATUS_SLAW_ACK : STATUS_SLAW_NACK);
    }
  }

  void completeWrite(bool ack) {
    busy = false;
    updateStatus(ack ? STATUS_DATA_SENT_ACK : STATUS_DATA_SENT_NACK);
  }

  void completeRead(int value) {
    busy = false;
    final ack = (cpu.data[config.TWCR] & TWCR_TWEA) != 0;
    cpu.data[config.TWDR] = value;
    updateStatus(ack ? STATUS_DATA_RECEIVED_ACK : STATUS_DATA_RECEIVED_NACK);
  }

  int get status {
    return cpu.data[config.TWSR] & TWSR_TWS_MASK;
  }

  void updateStatus(int value) {
    cpu.data[config.TWSR] = (cpu.data[config.TWSR] & ~TWSR_TWS_MASK) | value;
    cpu.setInterruptFlag(TWI);
  }
}

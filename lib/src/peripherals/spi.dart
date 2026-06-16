import '../cpu/cpu.dart';

class SPIConfig {
  final int spiInterrupt;
  final int SPCR;
  final int SPSR;
  final int SPDR;

  const SPIConfig({
    required this.spiInterrupt,
    required this.SPCR,
    required this.SPSR,
    required this.SPDR,
  });
}

// Register bits:
const SPCR_SPIE = 0x80; // SPI Interrupt Enable
const SPCR_SPE = 0x40; // SPI Enable
const SPCR_DORD = 0x20; // Data Order
const SPCR_MSTR = 0x10; // Master/Slave Select
const SPCR_CPOL = 0x8; // Clock Polarity
const SPCR_CPHA = 0x4; // Clock Phase
const SPCR_SPR1 = 0x2; // SPI Clock Rate Select 1
const SPCR_SPR0 = 0x1; // SPI Clock Rate Select 0
const SPSR_SPR_MASK = SPCR_SPR1 | SPCR_SPR0;

const SPSR_SPIF = 0x80; // SPI Interrupt Flag
const SPSR_WCOL = 0x40; // Write COLlision Flag
const SPSR_SPI2X = 0x1; // Double SPI Speed Bit

const spiConfig = SPIConfig(
  spiInterrupt: 0x22,
  SPCR: 0x4c,
  SPSR: 0x4d,
  SPDR: 0x4e,
);

typedef SPITransferCallback = int Function(int value);
typedef SPIByteTransferCallback = void Function(int value);

const bitsPerByte = 8;

class AVRSPI {
  final CPU cpu;
  final SPIConfig config;
  final int freqHz;

  /// @deprecated Use onByte instead
  SPITransferCallback onTransfer = (int value) => 0;

  /// SPI byte transfer callback. Invoked whenever the user code starts an SPI transaction.
  /// You can override this with your own SPI handler logic.
  ///
  /// The callback receives a argument: the byte sent over the SPI MOSI line.
  /// It should call `completeTransfer()` within `transferCycles` CPU cycles.
  late SPIByteTransferCallback onByte;

  bool transmissionActive = false;

  late final AVRInterruptConfig SPI;

  AVRSPI(this.cpu, this.config, this.freqHz) {
    onByte = (int value) {
      final valueIn = onTransfer(value);
      cpu.addClockEvent(() => completeTransfer(valueIn), transferCycles);
    };

    SPI = AVRInterruptConfig(
      address: config.spiInterrupt,
      flagRegister: config.SPSR,
      flagMask: SPSR_SPIF,
      enableRegister: config.SPCR,
      enableMask: SPCR_SPIE,
    );

    cpu.writeHooks[config.SPDR] =
        (int value, int oldValue, int addr, int mask) {
      if ((cpu.data[config.SPCR] & SPCR_SPE) == 0) {
        // SPI not enabled, ignore write
        return false; // Not handled, or actually in TS it just returned undefined. In our cpu it returns true if handled. Let's return false to allow normal memory write.
      }

      // Write collision
      if (transmissionActive) {
        cpu.data[config.SPSR] |= SPSR_WCOL;
        return true;
      }

      // Clear write collision / interrupt flags
      cpu.data[config.SPSR] &= ~SPSR_WCOL;
      cpu.clearInterrupt(SPI);

      transmissionActive = true;
      onByte(value);
      return true;
    };

    cpu.writeHooks[config.SPCR] =
        (int value, int oldValue, int addr, int mask) {
      cpu.updateInterruptEnable(SPI, value);
      return false; // let normal memory update happen
    };

    cpu.writeHooks[config.SPSR] =
        (int value, int oldValue, int addr, int mask) {
      cpu.data[config.SPSR] = value;
      cpu.clearInterruptByFlag(SPI, value);
      return true;
    };
  }

  void reset() {
    transmissionActive = false;
  }

  /// Completes an SPI transaction. Call this method only from the `onByte` callback.
  ///
  /// @param receivedByte Byte read from the SPI MISO line.
  void completeTransfer(int receivedByte) {
    cpu.data[config.SPDR] = receivedByte;
    cpu.setInterruptFlag(SPI);
    transmissionActive = false;
  }

  bool get isMaster {
    return (cpu.data[config.SPCR] & SPCR_MSTR) != 0;
  }

  String get dataOrder {
    return (cpu.data[config.SPCR] & SPCR_DORD) != 0 ? 'lsbFirst' : 'msbFirst';
  }

  int get spiMode {
    final CPHA = cpu.data[config.SPCR] & SPCR_CPHA;
    final CPOL = cpu.data[config.SPCR] & SPCR_CPOL;
    return ((CPHA != 0 ? 2 : 0) | (CPOL != 0 ? 1 : 0));
  }

  /// The clock divider is only relevant for Master mode
  int get clockDivider {
    final base = (cpu.data[config.SPSR] & SPSR_SPI2X) != 0 ? 2 : 4;
    switch (cpu.data[config.SPCR] & SPSR_SPR_MASK) {
      case 0x00:
        return base;
      case 0x01:
        return base * 4;
      case 0x02:
        return base * 16;
      case 0x03:
        return base * 32;
    }
    throw Exception('Invalid divider value!');
  }

  /// Number of cycles to complete a single byte SPI transaction
  int get transferCycles {
    return clockDivider * bitsPerByte;
  }

  /// The SPI freqeuncy is only relevant to Master mode.
  /// In slave mode, the frequency can be as high as F(osc) / 4.
  double get spiFrequency {
    return freqHz / clockDivider;
  }
}

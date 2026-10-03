import '../cpu/cpu.dart';

class USARTConfig {
  final int rxCompleteInterrupt;
  final int dataRegisterEmptyInterrupt;
  final int txCompleteInterrupt;

  final int UCSRA;
  final int UCSRB;
  final int UCSRC;
  final int UBRRL;
  final int UBRRH;
  final int UDR;

  const USARTConfig({
    required this.rxCompleteInterrupt,
    required this.dataRegisterEmptyInterrupt,
    required this.txCompleteInterrupt,
    required this.UCSRA,
    required this.UCSRB,
    required this.UCSRC,
    required this.UBRRL,
    required this.UBRRH,
    required this.UDR,
  });
}

const usart0Config = USARTConfig(
  rxCompleteInterrupt: 0x24,
  dataRegisterEmptyInterrupt: 0x26,
  txCompleteInterrupt: 0x28,
  UCSRA: 0xc0,
  UCSRB: 0xc1,
  UCSRC: 0xc2,
  UBRRL: 0xc4,
  UBRRH: 0xc5,
  UDR: 0xc6,
);

typedef USARTTransmitCallback = void Function(int value);
typedef USARTLineTransmitCallback = void Function(String value);
typedef USARTConfigurationChangeCallback = void Function();

// Register bits:
const UCSRA_RXC = 0x80; // USART Receive Complete
const UCSRA_TXC = 0x40; // USART Transmit Complete
const UCSRA_UDRE = 0x20; // USART Data Register Empty
const UCSRA_FE = 0x10; // Frame Error
const UCSRA_DOR = 0x8; // Data OverRun
const UCSRA_UPE = 0x4; // USART Parity Error
const UCSRA_U2X = 0x2; // Double the USART Transmission Speed
const UCSRA_MPCM = 0x1; // Multi-processor Communication Mode
const UCSRA_CFG_MASK = UCSRA_U2X;
const UCSRB_RXCIE = 0x80; // RX Complete Interrupt Enable
const UCSRB_TXCIE = 0x40; // TX Complete Interrupt Enable
const UCSRB_UDRIE = 0x20; // USART Data Register Empty Interrupt Enable
const UCSRB_RXEN = 0x10; // Receiver Enable
const UCSRB_TXEN = 0x8; // Transmitter Enable
const UCSRB_UCSZ2 = 0x4; // Character Size 2
const UCSRB_RXB8 = 0x2; // Receive Data Bit 8
const UCSRB_TXB8 = 0x1; // Transmit Data Bit 8
const UCSRB_CFG_MASK = UCSRB_UCSZ2 | UCSRB_RXEN | UCSRB_TXEN;
const UCSRC_UMSEL1 = 0x80; // USART Mode Select 1
const UCSRC_UMSEL0 = 0x40; // USART Mode Select 0
const UCSRC_UPM1 = 0x20; // Parity Mode 1
const UCSRC_UPM0 = 0x10; // Parity Mode 0
const UCSRC_USBS = 0x8; // Stop Bit Select
const UCSRC_UCSZ1 = 0x4; // Character Size 1
const UCSRC_UCSZ0 = 0x2; // Character Size 0
const UCSRC_UCPOL = 0x1; // Clock Polarity

const rxMasks = {
  5: 0x1f,
  6: 0x3f,
  7: 0x7f,
  8: 0xff,
  9: 0xff,
};

class AVRUSART {
  final CPU cpu;
  final USARTConfig config;
  final int freqHz;

  USARTTransmitCallback? onByteTransmit;
  USARTLineTransmitCallback? onLineTransmit;
  void Function()? onRxComplete;
  USARTConfigurationChangeCallback? onConfigurationChange;

  bool rxBusyValue = false;
  int rxByte = 0;
  String lineBuffer = '';

  late final AVRInterruptConfig RXC;
  late final AVRInterruptConfig UDRE;
  late final AVRInterruptConfig TXC;

  AVRUSART(this.cpu, this.config, this.freqHz) {
    RXC = AVRInterruptConfig(
      address: config.rxCompleteInterrupt,
      flagRegister: config.UCSRA,
      flagMask: UCSRA_RXC,
      enableRegister: config.UCSRB,
      enableMask: UCSRB_RXCIE,
      constant: true,
    );
    UDRE = AVRInterruptConfig(
      address: config.dataRegisterEmptyInterrupt,
      flagRegister: config.UCSRA,
      flagMask: UCSRA_UDRE,
      enableRegister: config.UCSRB,
      enableMask: UCSRB_UDRIE,
    );
    TXC = AVRInterruptConfig(
      address: config.txCompleteInterrupt,
      flagRegister: config.UCSRA,
      flagMask: UCSRA_TXC,
      enableRegister: config.UCSRB,
      enableMask: UCSRB_TXCIE,
    );

    reset();

    cpu.writeHooks[config.UCSRA] =
        (int value, int oldValue, int addr, int mask) {
      cpu.data[config.UCSRA] = value & (UCSRA_MPCM | UCSRA_U2X);
      cpu.clearInterruptByFlag(TXC, value);
      if ((value & UCSRA_CFG_MASK) != (oldValue & UCSRA_CFG_MASK)) {
        onConfigurationChange?.call();
      }
      return true;
    };

    cpu.writeHooks[config.UCSRB] =
        (int value, int oldValue, int addr, int mask) {
      cpu.updateInterruptEnable(RXC, value);
      cpu.updateInterruptEnable(UDRE, value);
      cpu.updateInterruptEnable(TXC, value);
      if ((value & UCSRB_RXEN) != 0 && (oldValue & UCSRB_RXEN) != 0) {
        cpu.clearInterrupt(RXC);
      }
      if ((value & UCSRB_TXEN) != 0 && (oldValue & UCSRB_TXEN) == 0) {
        // Enabling the transmission - mark UDR as empty
        cpu.setInterruptFlag(UDRE);
      }
      cpu.data[config.UCSRB] = value;
      if ((value & UCSRB_CFG_MASK) != (oldValue & UCSRB_CFG_MASK)) {
        onConfigurationChange?.call();
      }
      return true;
    };

    cpu.writeHooks[config.UCSRC] =
        (int value, int oldValue, int addr, int mask) {
      cpu.data[config.UCSRC] = value;
      onConfigurationChange?.call();
      return true;
    };

    cpu.readHooks[config.UDR] = (int addr) {
      final mask = rxMasks[bitsPerChar] ?? 0xff;
      final result = rxByte & mask;
      rxByte = 0;
      cpu.clearInterrupt(RXC);
      return result;
    };

    cpu.writeHooks[config.UDR] = (int value, int oldValue, int addr, int mask) {
      if (onByteTransmit != null) {
        onByteTransmit!(value);
      }
      if (onLineTransmit != null) {
        final ch = String.fromCharCode(value);
        if (ch == '\n') {
          onLineTransmit!(lineBuffer);
          lineBuffer = '';
        } else {
          lineBuffer += ch;
        }
      }
      cpu.addClockEvent(() {
        cpu.setInterruptFlag(UDRE);
        cpu.setInterruptFlag(TXC);
      }, cyclesPerChar);
      cpu.clearInterrupt(TXC);
      cpu.clearInterrupt(UDRE);
      return false;
    };

    cpu.writeHooks[config.UBRRH] =
        (int value, int oldValue, int addr, int mask) {
      cpu.data[config.UBRRH] = value;
      onConfigurationChange?.call();
      return true;
    };

    cpu.writeHooks[config.UBRRL] =
        (int value, int oldValue, int addr, int mask) {
      cpu.data[config.UBRRL] = value;
      onConfigurationChange?.call();
      return true;
    };
  }

  void reset() {
    cpu.data[config.UCSRA] = UCSRA_UDRE;
    cpu.data[config.UCSRB] = 0;
    cpu.data[config.UCSRC] =
        UCSRC_UCSZ1 | UCSRC_UCSZ0; // default: 8 bits per byte
    rxBusyValue = false;
    rxByte = 0;
    lineBuffer = '';
  }

  bool get rxBusy => rxBusyValue;

  bool writeByte(int value, {bool immediate = false}) {
    if (rxBusyValue || !rxEnable) {
      return false;
    }
    if (immediate) {
      rxByte = value;
      cpu.setInterruptFlag(RXC);
      onRxComplete?.call();
      return true;
    } else {
      rxBusyValue = true;
      cpu.addClockEvent(() {
        rxBusyValue = false;
        writeByte(value, immediate: true);
      }, cyclesPerChar);
      return true;
    }
  }

  int get cyclesPerChar {
    final symbolsPerChar = 1 + bitsPerChar + stopBits + (parityEnabled ? 1 : 0);
    return (UBRR + 1) * multiplier * symbolsPerChar;
  }

  int get UBRR {
    return (cpu.data[config.UBRRH] << 8) | cpu.data[config.UBRRL];
  }

  int get multiplier {
    return (cpu.data[config.UCSRA] & UCSRA_U2X) != 0 ? 8 : 16;
  }

  bool get rxEnable {
    return (cpu.data[config.UCSRB] & UCSRB_RXEN) != 0;
  }

  bool get txEnable {
    return (cpu.data[config.UCSRB] & UCSRB_TXEN) != 0;
  }

  int get baudRate {
    return freqHz ~/ (multiplier * (1 + UBRR));
  }

  int get bitsPerChar {
    final ucsz = ((cpu.data[config.UCSRC] & (UCSRC_UCSZ1 | UCSRC_UCSZ0)) >> 1) |
        (cpu.data[config.UCSRB] & UCSRB_UCSZ2);
    switch (ucsz) {
      case 0:
        return 5;
      case 1:
        return 6;
      case 2:
        return 7;
      case 3:
        return 8;
      case 7:
        return 9;
      default: // 4..6 are reserved
        return 9;
    }
  }

  int get stopBits {
    return (cpu.data[config.UCSRC] & UCSRC_USBS) != 0 ? 2 : 1;
  }

  bool get parityEnabled {
    return (cpu.data[config.UCSRC] & UCSRC_UPM1) != 0;
  }

  bool get parityOdd {
    return (cpu.data[config.UCSRC] & UCSRC_UPM0) != 0;
  }
}

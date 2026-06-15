import '../cpu/cpu.dart';

class AVRExternalInterrupt {
  /// either EICRA or EICRB, depending on which register holds the ISCx0/ISCx1 bits for this interrupt
  final int EICR;
  final int EIMSK;
  final int EIFR;

  /// Offset of the ISCx0/ISCx1 bits in the EICRx register
  final int iscOffset;

  /// Bit index in the EIMSK / EIFR registers
  final int index; // 0..7

  /// Interrupt vector index
  final int interrupt;

  const AVRExternalInterrupt({
    required this.EICR,
    required this.EIMSK,
    required this.EIFR,
    required this.iscOffset,
    required this.index,
    required this.interrupt,
  });
}

class AVRPinChangeInterrupt {
  final int PCIE; // bit index in PCICR/PCIFR
  final int PCICR;
  final int PCIFR;
  final int PCMSK;
  final int pinChangeInterrupt;
  final int mask;
  final int offset;

  const AVRPinChangeInterrupt({
    required this.PCIE,
    required this.PCICR,
    required this.PCIFR,
    required this.PCMSK,
    required this.pinChangeInterrupt,
    required this.mask,
    required this.offset,
  });
}

class AVRPortConfig {
  // Register addresses
  final int PIN;
  final int DDR;
  final int PORT;

  // Interrupt settings
  final AVRPinChangeInterrupt? pinChange;
  final List<AVRExternalInterrupt?> externalInterrupts;

  const AVRPortConfig({
    required this.PIN,
    required this.DDR,
    required this.PORT,
    this.pinChange,
    required this.externalInterrupts,
  });
}

const INT0 = AVRExternalInterrupt(
  EICR: 0x69,
  EIMSK: 0x3d,
  EIFR: 0x3c,
  index: 0,
  iscOffset: 0,
  interrupt: 2,
);

const INT1 = AVRExternalInterrupt(
  EICR: 0x69,
  EIMSK: 0x3d,
  EIFR: 0x3c,
  index: 1,
  iscOffset: 2,
  interrupt: 4,
);

const PCINT0 = AVRPinChangeInterrupt(
  PCIE: 0,
  PCICR: 0x68,
  PCIFR: 0x3b,
  PCMSK: 0x6b,
  pinChangeInterrupt: 6,
  mask: 0xff,
  offset: 0,
);

const PCINT1 = AVRPinChangeInterrupt(
  PCIE: 1,
  PCICR: 0x68,
  PCIFR: 0x3b,
  PCMSK: 0x6c,
  pinChangeInterrupt: 8,
  mask: 0xff,
  offset: 0,
);

const PCINT2 = AVRPinChangeInterrupt(
  PCIE: 2,
  PCICR: 0x68,
  PCIFR: 0x3b,
  PCMSK: 0x6d,
  pinChangeInterrupt: 10,
  mask: 0xff,
  offset: 0,
);

typedef GPIOListener = void Function(int value, int oldValue);
typedef ExternalClockListener = void Function(bool pinValue);

const portAConfig = AVRPortConfig(
  PIN: 0x20,
  DDR: 0x21,
  PORT: 0x22,
  externalInterrupts: [],
);

const portBConfig = AVRPortConfig(
  PIN: 0x23,
  DDR: 0x24,
  PORT: 0x25,
  pinChange: PCINT0,
  externalInterrupts: [],
);

const portCConfig = AVRPortConfig(
  PIN: 0x26,
  DDR: 0x27,
  PORT: 0x28,
  pinChange: PCINT1,
  externalInterrupts: [],
);

const portDConfig = AVRPortConfig(
  PIN: 0x29,
  DDR: 0x2a,
  PORT: 0x2b,
  pinChange: PCINT2,
  externalInterrupts: [null, null, INT0, INT1],
);

const portEConfig = AVRPortConfig(
  PIN: 0x2c,
  DDR: 0x2d,
  PORT: 0x2e,
  externalInterrupts: [],
);

const portFConfig = AVRPortConfig(
  PIN: 0x2f,
  DDR: 0x30,
  PORT: 0x31,
  externalInterrupts: [],
);

const portGConfig = AVRPortConfig(
  PIN: 0x32,
  DDR: 0x33,
  PORT: 0x34,
  externalInterrupts: [],
);

const portHConfig = AVRPortConfig(
  PIN: 0x100,
  DDR: 0x101,
  PORT: 0x102,
  externalInterrupts: [],
);

const portJConfig = AVRPortConfig(
  PIN: 0x103,
  DDR: 0x104,
  PORT: 0x105,
  externalInterrupts: [],
);

const portKConfig = AVRPortConfig(
  PIN: 0x106,
  DDR: 0x107,
  PORT: 0x108,
  externalInterrupts: [],
);

const portLConfig = AVRPortConfig(
  PIN: 0x109,
  DDR: 0x10a,
  PORT: 0x10b,
  externalInterrupts: [],
);

enum PinState {
  Low,
  High,
  Input,
  InputPullUp,
}

/* This mechanism allows timers to override specific GPIO pins */
enum PinOverrideMode {
  None,
  Enable,
  Set,
  Clear,
  Toggle,
}

class InterruptMode {
  static const LowLevel = 0;
  static const Change = 1;
  static const FallingEdge = 2;
  static const RisingEdge = 3;
}

class AVRIOPort {
  final CPU cpu;
  final AVRPortConfig portConfig;

  final Map<int, ExternalClockListener?> externalClockListeners = {};
  late final List<AVRInterruptConfig?> externalInts;
  late final AVRInterruptConfig? PCINT;
  
  List<GPIOListener> listeners = [];
  int pinValue = 0;
  int overrideMask = 0xff;
  int overrideValue = 0;
  int lastValue = 0;
  int lastDdr = 0;
  int lastPin = 0;
  int openCollector = 0;

  AVRIOPort(this.cpu, this.portConfig) {
    cpu.gpioPorts.add(this);
    cpu.gpioByPort[portConfig.PORT] = this;

    cpu.writeHooks[portConfig.DDR] = (int value, int oldValue, int addr, int mask) {
      final portValue = cpu.data[portConfig.PORT];
      cpu.data[portConfig.DDR] = value;
      writeGpio(portValue, value);
      updatePinRegister(value);
      return true;
    };
    
    cpu.writeHooks[portConfig.PORT] = (int value, int oldValue, int addr, int mask) {
      final ddrMask = cpu.data[portConfig.DDR];
      cpu.data[portConfig.PORT] = value;
      writeGpio(value, ddrMask);
      updatePinRegister(ddrMask);
      return true;
    };
    
    cpu.writeHooks[portConfig.PIN] = (int value, int oldValue, int addr, int mask) {
      // Writing to 1 PIN toggles PORT bits
      final oldPortValue = cpu.data[portConfig.PORT];
      final ddrMask = cpu.data[portConfig.DDR];
      final portValue = oldPortValue ^ (value & mask);
      cpu.data[portConfig.PORT] = portValue;
      writeGpio(portValue, ddrMask);
      updatePinRegister(ddrMask);
      return true;
    };

    // External interrupts
    final externalInterrupts = portConfig.externalInterrupts;
    externalInts = externalInterrupts.map((externalConfig) =>
      externalConfig != null
        ? AVRInterruptConfig(
            address: externalConfig.interrupt,
            flagRegister: externalConfig.EIFR,
            flagMask: 1 << externalConfig.index,
            enableRegister: externalConfig.EIMSK,
            enableMask: 1 << externalConfig.index,
          )
        : null
    ).toList();
    
    final eicrSet = <int>{};
    for (final item in externalInterrupts) {
      if (item != null) eicrSet.add(item.EICR);
    }
    for (final EICRx in eicrSet) {
      attachInterruptHook(EICRx);
    }
    
    int EIMSK = 0;
    for (final item in externalInterrupts) {
      if (item != null) {
        EIMSK = item.EIMSK;
        break;
      }
    }
    attachInterruptHook(EIMSK, 'mask');
    
    int EIFR = 0;
    for (final item in externalInterrupts) {
      if (item != null) {
        EIFR = item.EIFR;
        break;
      }
    }
    attachInterruptHook(EIFR, 'flag');

    // Pin change interrupts
    final pinChange = portConfig.pinChange;
    PCINT = pinChange != null
      ? AVRInterruptConfig(
          address: pinChange.pinChangeInterrupt,
          flagRegister: pinChange.PCIFR,
          flagMask: 1 << pinChange.PCIE,
          enableRegister: pinChange.PCICR,
          enableMask: 1 << pinChange.PCIE,
        )
      : null;
      
    if (pinChange != null) {
      final PCIFR = pinChange.PCIFR;
      final PCMSK = pinChange.PCMSK;
      cpu.writeHooks[PCIFR] = (int value, int oldValue, int addr, int mask) {
        for (final gpio in cpu.gpioPorts) {
          final pcint = gpio.PCINT;
          if (pcint != null) {
            cpu.clearInterruptByFlag(pcint, value);
          }
        }
        return true;
      };
      cpu.writeHooks[PCMSK] = (int value, int oldValue, int addr, int mask) {
        cpu.data[PCMSK] = value;
        for (final gpio in cpu.gpioPorts) {
          final pcint = gpio.PCINT;
          if (pcint != null) {
            cpu.updateInterruptEnable(pcint, value);
          }
        }
        return true;
      };
    }
  }

  void addListener(GPIOListener listener) {
    listeners.add(listener);
  }

  void removeListener(GPIOListener listener) {
    listeners.remove(listener);
  }

  PinState pinState(int index) {
    final ddr = cpu.data[portConfig.DDR];
    final port = cpu.data[portConfig.PORT];
    final bitMask = 1 << index;
    final openState = (port & bitMask) != 0 ? PinState.InputPullUp : PinState.Input;
    final highValue = (openCollector & bitMask) != 0 ? openState : PinState.High;
    if ((ddr & bitMask) != 0) {
      return (lastValue & bitMask) != 0 ? highValue : PinState.Low;
    } else {
      return openState;
    }
  }

  void setPin(int index, bool value) {
    final bitMask = 1 << index;
    pinValue &= ~bitMask;
    if (value) {
      pinValue |= bitMask;
    }
    updatePinRegister(cpu.data[portConfig.DDR]);
  }

  void timerOverridePin(int pin, PinOverrideMode mode) {
    final pinMask = 1 << pin;
    if (mode == PinOverrideMode.None) {
      overrideMask |= pinMask;
      overrideValue &= ~pinMask;
    } else {
      overrideMask &= ~pinMask;
      switch (mode) {
        case PinOverrideMode.Enable:
          overrideValue &= ~pinMask;
          overrideValue |= cpu.data[portConfig.PORT] & pinMask;
          break;
        case PinOverrideMode.Set:
          overrideValue |= pinMask;
          break;
        case PinOverrideMode.Clear:
          overrideValue &= ~pinMask;
          break;
        case PinOverrideMode.Toggle:
          overrideValue ^= pinMask;
          break;
        default:
          break;
      }
    }
    final ddrMask = cpu.data[portConfig.DDR];
    writeGpio(cpu.data[portConfig.PORT], ddrMask);
    updatePinRegister(ddrMask);
  }

  void updatePinRegister(int ddr) {
    final newPin = (pinValue & ~ddr) | (lastValue & ddr);
    cpu.data[portConfig.PIN] = newPin;
    if (lastPin != newPin) {
      for (int index = 0; index < 8; index++) {
        if ((newPin & (1 << index)) != (lastPin & (1 << index))) {
          final value = (newPin & (1 << index)) != 0;
          toggleInterrupt(index, value);
          externalClockListeners[index]?.call(value);
        }
      }
      lastPin = newPin;
    }
  }

  void toggleInterrupt(int pin, bool risingEdge) {
    final externalInterrupts = portConfig.externalInterrupts;
    final pinChange = portConfig.pinChange;
    
    if (pin < externalInterrupts.length) {
      final externalConfig = externalInterrupts[pin];
      final external = pin < externalInts.length ? externalInts[pin] : null;
      if (external != null && externalConfig != null) {
        final EIMSK = externalConfig.EIMSK;
        final index = externalConfig.index;
        final EICR = externalConfig.EICR;
        final iscOffset = externalConfig.iscOffset;
        if ((cpu.data[EIMSK] & (1 << index)) != 0) {
          final configuration = (cpu.data[EICR] >> iscOffset) & 0x3;
          bool generateInterrupt = false;
          external.constant = false;
          switch (configuration) {
            case InterruptMode.LowLevel:
              generateInterrupt = !risingEdge;
              external.constant = true;
              break;
            case InterruptMode.Change:
              generateInterrupt = true;
              break;
            case InterruptMode.FallingEdge:
              generateInterrupt = !risingEdge;
              break;
            case InterruptMode.RisingEdge:
              generateInterrupt = risingEdge;
              break;
          }
          if (generateInterrupt) {
            cpu.setInterruptFlag(external);
          } else if (external.constant) {
            cpu.clearInterrupt(external, clearFlag: true);
          }
        }
      }
    }

    if (pinChange != null && PCINT != null && (pinChange.mask & (1 << pin)) != 0) {
      final PCMSK = pinChange.PCMSK;
      if ((cpu.data[PCMSK] & (1 << (pin + pinChange.offset))) != 0) {
        cpu.setInterruptFlag(PCINT!);
      }
    }
  }

  void attachInterruptHook(int register, [String registerType = 'other']) {
    if (register == 0) {
      return;
    }

    cpu.writeHooks[register] = (int value, int oldValue, int addr, int mask) {
      if (registerType != 'flag') {
        cpu.data[register] = value;
      }
      for (final gpio in cpu.gpioPorts) {
        for (final external in gpio.externalInts) {
          if (external != null && registerType == 'mask') {
            cpu.updateInterruptEnable(external, value);
          }
          if (external != null && !external.constant && registerType == 'flag') {
            cpu.clearInterruptByFlag(external, value);
          }
        }
        gpio.checkExternalInterrupts();
      }
      return true;
    };
  }

  void checkExternalInterrupts() {
    final externalInterrupts = portConfig.externalInterrupts;
    for (int pin = 0; pin < 8; pin++) {
      if (pin >= externalInterrupts.length) continue;
      final external = externalInterrupts[pin];
      if (external == null) {
        continue;
      }
      final pinValue = (lastPin & (1 << pin)) != 0;
      final EIFR = external.EIFR;
      final EIMSK = external.EIMSK;
      final index = external.index;
      final EICR = external.EICR;
      final iscOffset = external.iscOffset;
      final interrupt = external.interrupt;
      if ((cpu.data[EIMSK] & (1 << index)) == 0 || pinValue) {
        continue;
      }
      final configuration = (cpu.data[EICR] >> iscOffset) & 0x3;
      if (configuration == InterruptMode.LowLevel) {
        cpu.queueInterrupt(AVRInterruptConfig(
          address: interrupt,
          flagRegister: EIFR,
          flagMask: 1 << index,
          enableRegister: EIMSK,
          enableMask: 1 << index,
          constant: true,
        ));
      }
    }
  }

  void writeGpio(int value, int ddr) {
    final newValue = (((value & overrideMask) | overrideValue) & ddr) | (value & ~ddr);
    final prevValue = lastValue;
    if (newValue != prevValue || ddr != lastDdr) {
      lastValue = newValue;
      lastDdr = ddr;
      for (final listener in listeners) {
        listener(newValue, prevValue);
      }
    }
  }
}

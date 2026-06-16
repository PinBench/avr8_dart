import '../cpu/cpu.dart';
import 'gpio.dart';

class ATtinyTimer1Config {
  final int TCCR1;
  final int GTCCR;
  final int TCNT1;
  final int OCR1A;
  final int OCR1B;
  final int OCR1C;
  final int TIFR;
  final int TIMSK;

  final int ovfInterrupt;
  final int compAInterrupt;
  final int compBInterrupt;

  final int TOV1;
  final int OCF1A;
  final int OCF1B;

  final int TOIE1;
  final int OCIE1A;
  final int OCIE1B;

  final int compPortB;
  final int compPinA;
  final int compPinB;

  final Map<int, int> dividers;

  const ATtinyTimer1Config({
    required this.TCCR1,
    required this.GTCCR,
    required this.TCNT1,
    required this.OCR1A,
    required this.OCR1B,
    required this.OCR1C,
    required this.TIFR,
    required this.TIMSK,
    required this.ovfInterrupt,
    required this.compAInterrupt,
    required this.compBInterrupt,
    required this.TOV1,
    required this.OCF1A,
    required this.OCF1B,
    required this.TOIE1,
    required this.OCIE1A,
    required this.OCIE1B,
    required this.compPortB,
    required this.compPinA,
    required this.compPinB,
    required this.dividers,
  });
}

// TCCR1 bits
const CTC1 = 1 << 7;
const PWM1A = 1 << 6;
const CS_MASK = 0x0f;

// GTCCR bits
const PWM1B_BIT = 1 << 6;
const FOC1B = 1 << 3;
const FOC1A = 1 << 2;
const PSR1 = 1 << 1;

const attinyTimer1Config = ATtinyTimer1Config(
  TCCR1: 0x50,
  GTCCR: 0x4c,
  TCNT1: 0x4f,
  OCR1A: 0x4e,
  OCR1B: 0x4b,
  OCR1C: 0x4d,
  TIFR: 0x58,
  TIMSK: 0x59,
  ovfInterrupt: 0x04,
  compAInterrupt: 0x03,
  compBInterrupt: 0x09,
  TOV1: 1 << 2,
  OCF1A: 1 << 6,
  OCF1B: 1 << 5,
  TOIE1: 1 << 2,
  OCIE1A: 1 << 6,
  OCIE1B: 1 << 5,
  compPortB: 0x38,
  compPinA: 1, // PB1
  compPinB: 4, // PB4
  dividers: {
    0: 0,
    1: 1,
    2: 2,
    3: 4,
    4: 8,
    5: 16,
    6: 32,
    7: 64,
    8: 128,
    9: 256,
    10: 512,
    11: 1024,
    12: 2048,
    13: 4096,
    14: 8192,
    15: 16384,
  },
);

class ATtinyTimer1 {
  final CPU cpu;
  final ATtinyTimer1Config config;

  int lastCycle = 0;
  int tcnt = 0;
  int tcntNext = 0;
  bool tcntUpdated = false;
  int ocrA = 0;
  int ocrB = 0;
  int ocrC = 0;
  int divider = 0;
  bool updateDividerFlag = false;
  bool countingUp = true;

  late final AVRInterruptConfig OVF;
  late final AVRInterruptConfig OCFA;
  late final AVRInterruptConfig OCFB;

  ATtinyTimer1(this.cpu, this.config) {
    OVF = AVRInterruptConfig(
      address: config.ovfInterrupt,
      flagRegister: config.TIFR,
      flagMask: config.TOV1,
      enableRegister: config.TIMSK,
      enableMask: config.TOIE1,
    );

    OCFA = AVRInterruptConfig(
      address: config.compAInterrupt,
      flagRegister: config.TIFR,
      flagMask: config.OCF1A,
      enableRegister: config.TIMSK,
      enableMask: config.OCIE1A,
    );

    OCFB = AVRInterruptConfig(
      address: config.compBInterrupt,
      flagRegister: config.TIFR,
      flagMask: config.OCF1B,
      enableRegister: config.TIMSK,
      enableMask: config.OCIE1B,
    );

    cpu.readHooks[config.TCNT1] = (int addr) {
      count(reschedule: false);
      return cpu.data[config.TCNT1] = tcnt & 0xff;
    };

    cpu.writeHooks[config.TCNT1] =
        (int value, int oldValue, int addr, int mask) {
      tcntNext = value;
      countingUp = true;
      tcntUpdated = true;
      cpu.updateClockEvent(countEvent, 0);
      if (divider != 0) {
        timerUpdated(tcntNext, tcntNext);
      }
      return false;
    };

    cpu.writeHooks[config.OCR1A] =
        (int value, int oldValue, int addr, int mask) {
      ocrA = value;
      return false;
    };
    cpu.writeHooks[config.OCR1B] =
        (int value, int oldValue, int addr, int mask) {
      ocrB = value;
      return false;
    };
    cpu.writeHooks[config.OCR1C] =
        (int value, int oldValue, int addr, int mask) {
      ocrC = value;
      return false;
    };

    cpu.writeHooks[config.TCCR1] =
        (int value, int oldValue, int addr, int mask) {
      cpu.data[config.TCCR1] = value;
      updateDividerFlag = true;
      cpu.clearClockEvent(countEvent);
      cpu.addClockEvent(countEvent, 0);
      updateCompConfig();
      return true;
    };

    final prevGtccrHook = cpu.writeHooks[config.GTCCR];
    cpu.writeHooks[config.GTCCR] =
        (int value, int oldValue, int addr, int mask) {
      if ((value & FOC1A) != 0) {
        forceCompare('A');
      }
      if ((value & FOC1B) != 0) {
        forceCompare('B');
      }
      if ((value & PSR1) != 0) {
        lastCycle = cpu.cycles;
      }
      value &= ~(FOC1A | FOC1B | PSR1);

      if (prevGtccrHook != null) {
        prevGtccrHook(value, oldValue, addr, mask);
      } else {
        cpu.data[config.GTCCR] = value;
      }

      updateCompConfig();
      return true;
    };

    final prevTifrHook = cpu.writeHooks[config.TIFR];
    cpu.writeHooks[config.TIFR] =
        (int value, int oldValue, int addr, int mask) {
      if (prevTifrHook != null) {
        prevTifrHook(value, oldValue, addr, mask);
      } else {
        cpu.data[config.TIFR] = value;
      }
      cpu.clearInterruptByFlag(OVF, value);
      cpu.clearInterruptByFlag(OCFA, value);
      cpu.clearInterruptByFlag(OCFB, value);
      return true;
    };

    final prevTimskHook = cpu.writeHooks[config.TIMSK];
    cpu.writeHooks[config.TIMSK] =
        (int value, int oldValue, int addr, int mask) {
      if (prevTimskHook != null) {
        prevTimskHook(value, oldValue, addr, mask);
      } else {
        cpu.data[config.TIMSK] = value;
      }
      cpu.updateInterruptEnable(OVF, value);
      cpu.updateInterruptEnable(OCFA, value);
      cpu.updateInterruptEnable(OCFB, value);
      return true;
    };
  }

  int get tccr1 => cpu.data[config.TCCR1];
  int get gtccr => cpu.data[config.GTCCR];

  int get CS => tccr1 & CS_MASK;
  bool get ctcMode => (tccr1 & CTC1) != 0;
  bool get pwmA => (tccr1 & PWM1A) != 0;
  bool get pwmB => (gtccr & PWM1B_BIT) != 0;

  int get comA => (tccr1 >> 4) & 0x3;
  int get comB => (gtccr >> 4) & 0x3;

  int get TOP {
    if (ctcMode || pwmA || pwmB) {
      return ocrC;
    }
    return 0xff;
  }

  void countEvent() {
    count(reschedule: true);
  }

  void count({bool reschedule = true}) {
    final cycles = cpu.cycles;
    final delta = cycles - lastCycle;

    if (divider != 0 && delta >= divider) {
      final counterDelta = delta ~/ divider;
      lastCycle += counterDelta * divider;
      final val = tcnt;
      final top = TOP;
      final phasePwm = (pwmA || pwmB) && !ctcMode;

      final newVal = phasePwm
          ? phasePwmCount(val, counterDelta)
          : (val + counterDelta) % (top + 1);
      final overflow = val + counterDelta > top;

      if (!tcntUpdated) {
        tcnt = newVal;
        if (!phasePwm) {
          timerUpdated(newVal, val);
        }
      }

      if (!phasePwm && overflow) {
        cpu.setInterruptFlag(OVF);
      }
    }

    if (tcntUpdated) {
      tcnt = tcntNext;
      tcntUpdated = false;
    }

    if (updateDividerFlag) {
      final cs = CS;
      final newDivider = config.dividers[cs] ?? 0;
      lastCycle = newDivider != 0 ? cpu.cycles : 0;
      updateDividerFlag = false;
      divider = newDivider;
      if (newDivider != 0) {
        cpu.addClockEvent(countEvent, lastCycle + newDivider - cpu.cycles);
      }
      return;
    }

    if (reschedule && divider != 0) {
      cpu.addClockEvent(countEvent, lastCycle + divider - cpu.cycles);
    }
  }

  int phasePwmCount(int value, int delta) {
    final top = TOP;

    while (delta > 0) {
      if (countingUp) {
        value++;
        if (value >= top) {
          value = top;
          countingUp = false;
        }
      } else {
        value--;
        if (value <= 0) {
          value = 0;
          countingUp = true;
          cpu.setInterruptFlag(OVF);
        }
      }

      if (!tcntUpdated) {
        if (value == ocrA) {
          cpu.setInterruptFlag(OCFA);
          updateCompPinPwm('A');
        }
        if (value == ocrB) {
          cpu.setInterruptFlag(OCFB);
          updateCompPinPwm('B');
        }
      }
      delta--;
    }
    return value & 0xff;
  }

  void timerUpdated(int value, int prevValue) {
    final overflow = prevValue > value;
    if (((prevValue < ocrA || overflow) && value >= ocrA) ||
        (prevValue < ocrA && overflow)) {
      cpu.setInterruptFlag(OCFA);
      if (comA != 0 && !pwmA) {
        updateCompPinNonPwm('A');
      }
    }
    if (((prevValue < ocrB || overflow) && value >= ocrB) ||
        (prevValue < ocrB && overflow)) {
      cpu.setInterruptFlag(OCFB);
      if (comB != 0 && !pwmB) {
        updateCompPinNonPwm('B');
      }
    }
  }

  void forceCompare(String channel) {
    if (channel == 'A' && !pwmA && comA != 0) {
      updateCompPinNonPwm('A');
    } else if (channel == 'B' && !pwmB && comB != 0) {
      updateCompPinNonPwm('B');
    }
  }

  void updateCompPinNonPwm(String channel) {
    final com = channel == 'A' ? comA : comB;
    final pin = channel == 'A' ? config.compPinA : config.compPinB;
    PinOverrideMode mode;
    switch (com) {
      case 1:
        mode = PinOverrideMode.Toggle;
        break;
      case 2:
        mode = PinOverrideMode.Clear;
        break;
      case 3:
        mode = PinOverrideMode.Set;
        break;
      default:
        return;
    }
    cpu.gpioByPort[config.compPortB]?.timerOverridePin(pin, mode);
  }

  void updateCompPinPwm(String channel) {
    final com = channel == 'A' ? comA : comB;
    final pin = channel == 'A' ? config.compPinA : config.compPinB;
    final invertingMode = com == 3;
    final isSet = countingUp == invertingMode;
    PinOverrideMode mode;
    switch (com) {
      case 1:
        mode = PinOverrideMode.Toggle;
        break;
      case 2:
      case 3:
        mode = isSet ? PinOverrideMode.Set : PinOverrideMode.Clear;
        break;
      default:
        return;
    }
    cpu.gpioByPort[config.compPortB]?.timerOverridePin(pin, mode);
  }

  void updateCompConfig() {
    final port = cpu.gpioByPort[config.compPortB];
    if (port == null) return;
    port.timerOverridePin(
      config.compPinA,
      comA != 0 ? PinOverrideMode.Enable : PinOverrideMode.None,
    );
    port.timerOverridePin(
      config.compPinB,
      comB != 0 ? PinOverrideMode.Enable : PinOverrideMode.None,
    );
  }
}

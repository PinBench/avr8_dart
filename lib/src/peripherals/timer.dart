import '../cpu/cpu.dart';
import 'gpio.dart';

const timer01Dividers = {
  0: 0,
  1: 1,
  2: 8,
  3: 64,
  4: 256,
  5: 1024,
  6: 0, // External clock - see ExternalClockMode
  7: 0, // Ditto
};

class ExternalClockMode {
  static const int FallingEdge = 6;
  static const int RisingEdge = 7;
}

class AVRTimerConfig {
  final int bits;
  final Map<int, int> dividers;

  // Interrupt vectors
  final int captureInterrupt;
  final int compAInterrupt;
  final int compBInterrupt;
  final int compCInterrupt; // Optional, 0 = unused
  final int ovfInterrupt;

  // Register addresses
  final int TIFR;
  final int OCRA;
  final int OCRB;
  final int OCRC; // Optional, 0 = unused
  final int ICR;
  final int TCNT;
  final int TCCRA;
  final int TCCRB;
  final int TCCRC;
  final int TIMSK;

  // TIFR bits
  final int TOV;
  final int OCFA;
  final int OCFB;
  final int OCFC; // Optional, if compCInterrupt != 0

  // TIMSK bits
  final int TOIE;
  final int OCIEA;
  final int OCIEB;
  final int OCIEC; // Optional, if compCInterrupt != 0

  // Output compare pins
  final int compPortA;
  final int compPinA;
  final int compPortB;
  final int compPinB;
  final int compPortC; // Optional, 0 = unused
  final int compPinC;

  // External clock pin (optional, 0 = unused)
  final int externalClockPort;
  final int externalClockPin;

  const AVRTimerConfig({
    required this.bits,
    required this.dividers,
    required this.captureInterrupt,
    required this.compAInterrupt,
    required this.compBInterrupt,
    this.compCInterrupt = 0,
    required this.ovfInterrupt,
    required this.TIFR,
    required this.OCRA,
    required this.OCRB,
    this.OCRC = 0,
    required this.ICR,
    required this.TCNT,
    required this.TCCRA,
    required this.TCCRB,
    required this.TCCRC,
    required this.TIMSK,
    required this.TOV,
    required this.OCFA,
    required this.OCFB,
    this.OCFC = 0,
    required this.TOIE,
    required this.OCIEA,
    required this.OCIEB,
    this.OCIEC = 0,
    required this.compPortA,
    required this.compPinA,
    required this.compPortB,
    required this.compPinB,
    this.compPortC = 0,
    this.compPinC = 0,
    required this.externalClockPort,
    required this.externalClockPin,
  });
}

const defaultTimerBits = {
  // TIFR bits
  'TOV': 1,
  'OCFA': 2,
  'OCFB': 4,
  'OCFC': 0, // Unused

  // TIMSK bits
  'TOIE': 1,
  'OCIEA': 2,
  'OCIEB': 4,
  'OCIEC': 0, // Unused
};

const timer0Config = AVRTimerConfig(
  bits: 8,
  captureInterrupt: 0,
  compAInterrupt: 0x1c,
  compBInterrupt: 0x1e,
  compCInterrupt: 0,
  ovfInterrupt: 0x20,
  TIFR: 0x35,
  OCRA: 0x47,
  OCRB: 0x48,
  OCRC: 0,
  ICR: 0,
  TCNT: 0x46,
  TCCRA: 0x44,
  TCCRB: 0x45,
  TCCRC: 0,
  TIMSK: 0x6e,
  dividers: timer01Dividers,
  compPortA: 0x2b,
  compPinA: 6,
  compPortB: 0x2b,
  compPinB: 5,
  compPortC: 0,
  compPinC: 0,
  externalClockPort: 0x2b,
  externalClockPin: 4,
  TOV: 1,
  OCFA: 2,
  OCFB: 4,
  OCFC: 0,
  TOIE: 1,
  OCIEA: 2,
  OCIEB: 4,
  OCIEC: 0,
);

const timer1Config = AVRTimerConfig(
  bits: 16,
  captureInterrupt: 0x14,
  compAInterrupt: 0x16,
  compBInterrupt: 0x18,
  compCInterrupt: 0,
  ovfInterrupt: 0x1a,
  TIFR: 0x36,
  OCRA: 0x88,
  OCRB: 0x8a,
  OCRC: 0,
  ICR: 0x86,
  TCNT: 0x84,
  TCCRA: 0x80,
  TCCRB: 0x81,
  TCCRC: 0x82,
  TIMSK: 0x6f,
  dividers: timer01Dividers,
  compPortA: 0x25,
  compPinA: 1,
  compPortB: 0x25,
  compPinB: 2,
  compPortC: 0,
  compPinC: 0,
  externalClockPort: 0x2b,
  externalClockPin: 5,
  TOV: 1,
  OCFA: 2,
  OCFB: 4,
  OCFC: 0,
  TOIE: 1,
  OCIEA: 2,
  OCIEB: 4,
  OCIEC: 0,
);

const timer2Config = AVRTimerConfig(
  bits: 8,
  captureInterrupt: 0,
  compAInterrupt: 0x0e,
  compBInterrupt: 0x10,
  compCInterrupt: 0,
  ovfInterrupt: 0x12,
  TIFR: 0x37,
  OCRA: 0xb3,
  OCRB: 0xb4,
  OCRC: 0,
  ICR: 0,
  TCNT: 0xb2,
  TCCRA: 0xb0,
  TCCRB: 0xb1,
  TCCRC: 0,
  TIMSK: 0x70,
  dividers: {
    0: 0,
    1: 1,
    2: 8,
    3: 32,
    4: 64,
    5: 128,
    6: 256,
    7: 1024,
  },
  compPortA: 0x25,
  compPinA: 3,
  compPortB: 0x2b,
  compPinB: 3,
  compPortC: 0,
  compPinC: 0,
  externalClockPort: 0,
  externalClockPin: 0,
  TOV: 1,
  OCFA: 2,
  OCFB: 4,
  OCFC: 0,
  TOIE: 1,
  OCIEA: 2,
  OCIEB: 4,
  OCIEC: 0,
);

class TimerMode {
  static const Normal = 0;
  static const PWMPhaseCorrect = 1;
  static const CTC = 2;
  static const FastPWM = 3;
  static const PWMPhaseFrequencyCorrect = 4;
  static const Reserved = 5;
}

class TOVUpdateMode {
  static const Max = 0;
  static const Top = 1;
  static const Bottom = 2;
}

class OCRUpdateMode {
  static const Immediate = 0;
  static const Top = 1;
  static const Bottom = 2;
}

const TopOCRA = -1;
const TopICR = -2;

class WGMConfig {
  final int timerMode;
  final int topValue;
  final int ocrUpdateMode;
  final int tovUpdateMode;
  final int flags;

  const WGMConfig(this.timerMode, this.topValue, this.ocrUpdateMode,
      this.tovUpdateMode, this.flags);
}

const OCToggle = 1;

const Normal = TimerMode.Normal;
const PWMPhaseCorrect = TimerMode.PWMPhaseCorrect;
const CTC = TimerMode.CTC;
const FastPWM = TimerMode.FastPWM;
const Reserved = TimerMode.Reserved;
const PWMPhaseFrequencyCorrect = TimerMode.PWMPhaseFrequencyCorrect;

const wgmModes8Bit = [
  WGMConfig(Normal, 0xff, OCRUpdateMode.Immediate, TOVUpdateMode.Max, 0),
  WGMConfig(PWMPhaseCorrect, 0xff, OCRUpdateMode.Top, TOVUpdateMode.Bottom, 0),
  WGMConfig(CTC, TopOCRA, OCRUpdateMode.Immediate, TOVUpdateMode.Max, 0),
  WGMConfig(FastPWM, 0xff, OCRUpdateMode.Bottom, TOVUpdateMode.Max, 0),
  WGMConfig(Reserved, 0xff, OCRUpdateMode.Immediate, TOVUpdateMode.Max, 0),
  WGMConfig(PWMPhaseCorrect, TopOCRA, OCRUpdateMode.Top, TOVUpdateMode.Bottom,
      OCToggle),
  WGMConfig(Reserved, 0xff, OCRUpdateMode.Immediate, TOVUpdateMode.Max, 0),
  WGMConfig(
      FastPWM, TopOCRA, OCRUpdateMode.Bottom, TOVUpdateMode.Top, OCToggle),
];

const wgmModes16Bit = [
  WGMConfig(Normal, 0xffff, OCRUpdateMode.Immediate, TOVUpdateMode.Max, 0),
  WGMConfig(
      PWMPhaseCorrect, 0x00ff, OCRUpdateMode.Top, TOVUpdateMode.Bottom, 0),
  WGMConfig(
      PWMPhaseCorrect, 0x01ff, OCRUpdateMode.Top, TOVUpdateMode.Bottom, 0),
  WGMConfig(
      PWMPhaseCorrect, 0x03ff, OCRUpdateMode.Top, TOVUpdateMode.Bottom, 0),
  WGMConfig(CTC, TopOCRA, OCRUpdateMode.Immediate, TOVUpdateMode.Max, 0),
  WGMConfig(FastPWM, 0x00ff, OCRUpdateMode.Bottom, TOVUpdateMode.Top, 0),
  WGMConfig(FastPWM, 0x01ff, OCRUpdateMode.Bottom, TOVUpdateMode.Top, 0),
  WGMConfig(FastPWM, 0x03ff, OCRUpdateMode.Bottom, TOVUpdateMode.Top, 0),
  WGMConfig(PWMPhaseFrequencyCorrect, TopICR, OCRUpdateMode.Bottom,
      TOVUpdateMode.Bottom, 0),
  WGMConfig(PWMPhaseFrequencyCorrect, TopOCRA, OCRUpdateMode.Bottom,
      TOVUpdateMode.Bottom, OCToggle),
  WGMConfig(
      PWMPhaseCorrect, TopICR, OCRUpdateMode.Top, TOVUpdateMode.Bottom, 0),
  WGMConfig(PWMPhaseCorrect, TopOCRA, OCRUpdateMode.Top, TOVUpdateMode.Bottom,
      OCToggle),
  WGMConfig(CTC, TopICR, OCRUpdateMode.Immediate, TOVUpdateMode.Max, 0),
  WGMConfig(Reserved, 0xffff, OCRUpdateMode.Immediate, TOVUpdateMode.Max, 0),
  WGMConfig(FastPWM, TopICR, OCRUpdateMode.Bottom, TOVUpdateMode.Top, OCToggle),
  WGMConfig(
      FastPWM, TopOCRA, OCRUpdateMode.Bottom, TOVUpdateMode.Top, OCToggle),
];

PinOverrideMode compToOverride(int comp) {
  switch (comp) {
    case 1:
      return PinOverrideMode.Toggle;
    case 2:
      return PinOverrideMode.Clear;
    case 3:
      return PinOverrideMode.Set;
    default:
      return PinOverrideMode.Enable;
  }
}

const FOCA = 1 << 7;
const FOCB = 1 << 6;
const FOCC = 1 << 5;

class AVRTimer {
  final CPU cpu;
  final AVRTimerConfig config;

  late final int MAX;
  int lastCycle = 0;
  int ocrA = 0;
  int nextOcrA = 0;
  int ocrB = 0;
  int nextOcrB = 0;
  late final bool hasOCRC;
  int ocrC = 0;
  int nextOcrC = 0;
  int ocrUpdateMode = OCRUpdateMode.Immediate;
  int tovUpdateMode = TOVUpdateMode.Max;
  int icr = 0;
  int timerMode = TimerMode.Normal;
  int topValue = 0xff;
  int tcnt = 0;
  int tcntNext = 0;
  int compA = 0;
  int compB = 0;
  int compC = 0;
  bool tcntUpdated = false;
  bool updateDividerFlag = false;
  bool countingUp = true;
  int divider = 0;
  AVRIOPort? externalClockPort;
  bool externalClockRisingEdge = false;

  int highByteTemp = 0;

  late final AVRInterruptConfig OVF;
  late final AVRInterruptConfig OCFA;
  late final AVRInterruptConfig OCFB;
  late final AVRInterruptConfig OCFC;

  AVRTimer(this.cpu, this.config) {
    MAX = config.bits == 16 ? 0xffff : 0xff;
    hasOCRC = config.OCRC > 0;

    OVF = AVRInterruptConfig(
      address: config.ovfInterrupt,
      flagRegister: config.TIFR,
      flagMask: config.TOV,
      enableRegister: config.TIMSK,
      enableMask: config.TOIE,
    );
    OCFA = AVRInterruptConfig(
      address: config.compAInterrupt,
      flagRegister: config.TIFR,
      flagMask: config.OCFA,
      enableRegister: config.TIMSK,
      enableMask: config.OCIEA,
    );
    OCFB = AVRInterruptConfig(
      address: config.compBInterrupt,
      flagRegister: config.TIFR,
      flagMask: config.OCFB,
      enableRegister: config.TIMSK,
      enableMask: config.OCIEB,
    );
    OCFC = AVRInterruptConfig(
      address: config.compCInterrupt,
      flagRegister: config.TIFR,
      flagMask: config.OCFC,
      enableRegister: config.TIMSK,
      enableMask: config.OCIEC,
    );

    updateWGMConfig();

    cpu.readHooks[config.TCNT] = (int addr) {
      count(reschedule: false);
      if (config.bits == 16) {
        cpu.data[addr + 1] = tcnt >> 8;
      }
      return cpu.data[addr] = tcnt & 0xff;
    };

    cpu.writeHooks[config.TCNT] =
        (int value, int oldValue, int addr, int mask) {
      tcntNext = (highByteTemp << 8) | value;
      countingUp = true;
      tcntUpdated = true;
      cpu.updateClockEvent(countEvent, 0);
      if (divider != 0) {
        timerUpdated(tcntNext, tcntNext);
      }
      return false; // Actually let's return true? wait... TCNT writes update registers. We should not return true unless we fully handle it? In TS `this.cpu.data[config.TCNT] = ...` was not intercepted except to update Next. The TS version returns undefined (falsy) for TCNT writeHook. So return false.
    };

    cpu.writeHooks[config.OCRA] =
        (int value, int oldValue, int addr, int mask) {
      nextOcrA = (highByteTemp << 8) | value;
      if (ocrUpdateMode == OCRUpdateMode.Immediate) {
        ocrA = nextOcrA;
      }
      return false;
    };

    cpu.writeHooks[config.OCRB] =
        (int value, int oldValue, int addr, int mask) {
      nextOcrB = (highByteTemp << 8) | value;
      if (ocrUpdateMode == OCRUpdateMode.Immediate) {
        ocrB = nextOcrB;
      }
      return false;
    };

    if (hasOCRC) {
      cpu.writeHooks[config.OCRC] =
          (int value, int oldValue, int addr, int mask) {
        nextOcrC = (highByteTemp << 8) | value;
        if (ocrUpdateMode == OCRUpdateMode.Immediate) {
          ocrC = nextOcrC;
        }
        return false;
      };
    }

    if (config.bits == 16) {
      cpu.writeHooks[config.ICR] =
          (int value, int oldValue, int addr, int mask) {
        icr = (highByteTemp << 8) | value;
        return false;
      };

      bool updateTempRegister(int value, int oldValue, int addr, int mask) {
        highByteTemp = value;
        return false;
      }

      bool updateOCRHighRegister(int value, int oldValue, int addr, int mask) {
        highByteTemp = value & (ocrMask >> 8);
        cpu.data[addr] = highByteTemp;
        return true;
      }

      cpu.writeHooks[config.TCNT + 1] = updateTempRegister;
      cpu.writeHooks[config.OCRA + 1] = updateOCRHighRegister;
      cpu.writeHooks[config.OCRB + 1] = updateOCRHighRegister;
      if (hasOCRC) {
        cpu.writeHooks[config.OCRC + 1] = updateOCRHighRegister;
      }
      cpu.writeHooks[config.ICR + 1] = updateTempRegister;
    }

    cpu.writeHooks[config.TCCRA] =
        (int value, int oldValue, int addr, int mask) {
      cpu.data[config.TCCRA] = value;
      updateWGMConfig();
      return true;
    };

    cpu.writeHooks[config.TCCRB] =
        (int value, int oldValue, int addr, int mask) {
      if (config.TCCRC == 0) {
        checkForceCompare(value);
        value &= ~(FOCA | FOCB);
      }
      cpu.data[config.TCCRB] = value;
      updateDividerFlag = true;
      cpu.clearClockEvent(countEvent);
      cpu.addClockEvent(countEvent, 0);
      updateWGMConfig();
      return true;
    };

    if (config.TCCRC != 0) {
      cpu.writeHooks[config.TCCRC] =
          (int value, int oldValue, int addr, int mask) {
        checkForceCompare(value);
        return false;
      };
    }

    cpu.writeHooks[config.TIFR] =
        (int value, int oldValue, int addr, int mask) {
      cpu.data[config.TIFR] = value;
      cpu.clearInterruptByFlag(OVF, value);
      cpu.clearInterruptByFlag(OCFA, value);
      cpu.clearInterruptByFlag(OCFB, value);
      return true;
    };

    cpu.writeHooks[config.TIMSK] =
        (int value, int oldValue, int addr, int mask) {
      cpu.updateInterruptEnable(OVF, value);
      cpu.updateInterruptEnable(OCFA, value);
      cpu.updateInterruptEnable(OCFB, value);
      return false;
    };
  }

  void reset() {
    divider = 0;
    lastCycle = 0;
    ocrA = 0;
    nextOcrA = 0;
    ocrB = 0;
    nextOcrB = 0;
    ocrC = 0;
    nextOcrC = 0;
    icr = 0;
    tcnt = 0;
    tcntNext = 0;
    tcntUpdated = false;
    countingUp = false;
    updateDividerFlag = true;
  }

  int get TCCRA => cpu.data[config.TCCRA];
  int get TCCRB => cpu.data[config.TCCRB];
  int get TIMSK => cpu.data[config.TIMSK];

  int get CS => TCCRB & 0x7;

  int get WGM {
    final mask = config.bits == 16 ? 0x18 : 0x8;
    return ((TCCRB & mask) >> 1) | (TCCRA & 0x3);
  }

  int get TOP {
    switch (topValue) {
      case TopOCRA:
        return ocrA;
      case TopICR:
        return icr;
      default:
        return topValue;
    }
  }

  int get ocrMask {
    switch (topValue) {
      case TopOCRA:
      case TopICR:
        return 0xffff;
      default:
        return topValue;
    }
  }

  int get debugTCNT => tcnt;

  void updateWGMConfig() {
    final wgmModes = config.bits == 16 ? wgmModes16Bit : wgmModes8Bit;
    final tccraVal = cpu.data[config.TCCRA];
    final wgmConfig = wgmModes[WGM];

    timerMode = wgmConfig.timerMode;
    topValue = wgmConfig.topValue;
    ocrUpdateMode = wgmConfig.ocrUpdateMode;
    tovUpdateMode = wgmConfig.tovUpdateMode;
    final flags = wgmConfig.flags;

    final pwmMode = timerMode == FastPWM ||
        timerMode == PWMPhaseCorrect ||
        timerMode == PWMPhaseFrequencyCorrect;

    final prevCompA = compA;
    compA = (tccraVal >> 6) & 0x3;
    if (compA == 1 && pwmMode && (flags & OCToggle) == 0) {
      compA = 0;
    }
    if ((prevCompA != 0) != (compA != 0)) {
      updateCompA(compA != 0 ? PinOverrideMode.Enable : PinOverrideMode.None);
    }

    final prevCompB = compB;
    compB = (tccraVal >> 4) & 0x3;
    if (compB == 1 && pwmMode) {
      compB = 0; // Reserved
    }
    if ((prevCompB != 0) != (compB != 0)) {
      updateCompB(compB != 0 ? PinOverrideMode.Enable : PinOverrideMode.None);
    }

    if (hasOCRC) {
      final prevCompC = compC;
      compC = (tccraVal >> 2) & 0x3;
      if (compC == 1 && pwmMode) {
        compC = 0; // Reserved
      }
      if ((prevCompC != 0) != (compC != 0)) {
        updateCompC(compC != 0 ? PinOverrideMode.Enable : PinOverrideMode.None);
      }
    }
  }

  void countEvent() {
    count(reschedule: true);
  }

  void count({bool reschedule = true, bool external = false}) {
    final cycles = cpu.cycles;
    final delta = cycles - lastCycle;
    if ((divider != 0 && delta >= divider) || external) {
      final counterDelta = external ? 1 : (delta ~/ divider);
      lastCycle += counterDelta * divider;
      final val = tcnt;

      final phasePwm =
          timerMode == PWMPhaseCorrect || timerMode == PWMPhaseFrequencyCorrect;
      final newVal = phasePwm
          ? phasePwmCount(val, counterDelta)
          : (val + counterDelta) % (TOP + 1);
      final overflow = val + counterDelta > TOP;

      if (!tcntUpdated) {
        tcnt = newVal;
        if (!phasePwm) {
          timerUpdated(newVal, val);
        }
      }

      if (!phasePwm) {
        if (timerMode == FastPWM && overflow) {
          if (compA != 0) updateCompPin(compA, 'A', true);
          if (compB != 0) updateCompPin(compB, 'B', true);
        }

        if (ocrUpdateMode == OCRUpdateMode.Bottom && overflow) {
          ocrA = nextOcrA;
          ocrB = nextOcrB;
          ocrC = nextOcrC;
        }

        if (overflow && (tovUpdateMode == TOVUpdateMode.Top || TOP == MAX)) {
          cpu.setInterruptFlag(OVF);
        }
      }
    }

    if (tcntUpdated) {
      tcnt = tcntNext;
      tcntUpdated = false;
      if ((tcnt == 0 && ocrUpdateMode == OCRUpdateMode.Bottom) ||
          (tcnt == TOP && ocrUpdateMode == OCRUpdateMode.Top)) {
        ocrA = nextOcrA;
        ocrB = nextOcrB;
        ocrC = nextOcrC;
      }
    }

    if (updateDividerFlag) {
      final currentCS = CS;
      final externalClockPin = config.externalClockPin;
      final newDivider = config.dividers[currentCS] ?? 0;
      lastCycle = newDivider != 0 ? cpu.cycles : 0;
      updateDividerFlag = false;
      divider = newDivider;

      if (config.externalClockPort != 0 && externalClockPort == null) {
        externalClockPort = cpu.gpioByPort[config.externalClockPort];
      }
      if (externalClockPort != null) {
        externalClockPort!.externalClockListeners[externalClockPin] = null;
      }
      if (newDivider != 0) {
        cpu.addClockEvent(countEvent, lastCycle + newDivider - cpu.cycles);
      } else if (externalClockPort != null &&
          (currentCS == ExternalClockMode.FallingEdge ||
              currentCS == ExternalClockMode.RisingEdge)) {
        externalClockPort!.externalClockListeners[externalClockPin] =
            externalClockCallback;
        externalClockRisingEdge = currentCS == ExternalClockMode.RisingEdge;
      }
      return;
    }

    if (reschedule && divider != 0) {
      cpu.addClockEvent(countEvent, lastCycle + divider - cpu.cycles);
    }
  }

  void externalClockCallback(bool value) {
    if (value == externalClockRisingEdge) {
      count(reschedule: false, external: true);
    }
  }

  int phasePwmCount(int value, int delta) {
    if (value == 0 && TOP == 0) {
      delta = 0;
      if (ocrUpdateMode == OCRUpdateMode.Top) {
        ocrA = nextOcrA;
        ocrB = nextOcrB;
        ocrC = nextOcrC;
      }
    }
    while (delta > 0) {
      if (countingUp) {
        value++;
        if (value == TOP && !tcntUpdated) {
          countingUp = false;
          if (ocrUpdateMode == OCRUpdateMode.Top) {
            ocrA = nextOcrA;
            ocrB = nextOcrB;
            ocrC = nextOcrC;
          }
        }
      } else {
        value--;
        if (value == 0 && !tcntUpdated) {
          countingUp = true;
          cpu.setInterruptFlag(OVF);
          if (ocrUpdateMode == OCRUpdateMode.Bottom) {
            ocrA = nextOcrA;
            ocrB = nextOcrB;
            ocrC = nextOcrC;
          }
        }
      }
      if (!tcntUpdated) {
        if (value == ocrA) {
          cpu.setInterruptFlag(OCFA);
          if (compA != 0) updateCompPin(compA, 'A');
        }
        if (value == ocrB) {
          cpu.setInterruptFlag(OCFB);
          if (compB != 0) updateCompPin(compB, 'B');
        }
        if (hasOCRC && value == ocrC) {
          cpu.setInterruptFlag(OCFC);
          if (compC != 0) updateCompPin(compC, 'C');
        }
      }
      delta--;
    }
    return value & MAX;
  }

  void timerUpdated(int value, int prevValue) {
    final overflow = prevValue > value;
    if (((prevValue < ocrA || overflow) && value >= ocrA) ||
        (prevValue < ocrA && overflow)) {
      cpu.setInterruptFlag(OCFA);
      if (compA != 0) updateCompPin(compA, 'A');
    }
    if (((prevValue < ocrB || overflow) && value >= ocrB) ||
        (prevValue < ocrB && overflow)) {
      cpu.setInterruptFlag(OCFB);
      if (compB != 0) updateCompPin(compB, 'B');
    }
    if (hasOCRC &&
        (((prevValue < ocrC || overflow) && value >= ocrC) ||
            (prevValue < ocrC && overflow))) {
      cpu.setInterruptFlag(OCFC);
      if (compC != 0) updateCompPin(compC, 'C');
    }
  }

  void checkForceCompare(int value) {
    if (timerMode == TimerMode.FastPWM ||
        timerMode == TimerMode.PWMPhaseCorrect ||
        timerMode == TimerMode.PWMPhaseFrequencyCorrect) {
      return;
    }
    if ((value & FOCA) != 0) updateCompPin(compA, 'A');
    if ((value & FOCB) != 0) updateCompPin(compB, 'B');
    if (config.compPortC != 0 && (value & FOCC) != 0) updateCompPin(compC, 'C');
  }

  void updateCompPin(int compValue, String pinName, [bool bottom = false]) {
    var newValue = PinOverrideMode.None;
    final invertingMode = compValue == 3;
    final isSet = countingUp == invertingMode;
    switch (timerMode) {
      case Normal:
      case CTC:
        newValue = compToOverride(compValue);
        break;
      case FastPWM:
        if (compValue == 1) {
          newValue = bottom ? PinOverrideMode.None : PinOverrideMode.Toggle;
        } else {
          newValue = invertingMode != bottom
              ? PinOverrideMode.Set
              : PinOverrideMode.Clear;
        }
        break;
      case PWMPhaseCorrect:
      case PWMPhaseFrequencyCorrect:
        if (compValue == 1) {
          newValue = PinOverrideMode.Toggle;
        } else {
          newValue = isSet ? PinOverrideMode.Set : PinOverrideMode.Clear;
        }
        break;
    }

    if (newValue != PinOverrideMode.None) {
      if (pinName == 'A') {
        updateCompA(newValue);
      } else if (pinName == 'B') {
        updateCompB(newValue);
      } else {
        updateCompC(newValue);
      }
    }
  }

  void updateCompA(PinOverrideMode value) {
    final port = cpu.gpioByPort[config.compPortA];
    port?.timerOverridePin(config.compPinA, value);
  }

  void updateCompB(PinOverrideMode value) {
    final port = cpu.gpioByPort[config.compPortB];
    port?.timerOverridePin(config.compPinB, value);
  }

  void updateCompC(PinOverrideMode value) {
    final port = cpu.gpioByPort[config.compPortC];
    port?.timerOverridePin(config.compPinC, value);
  }
}

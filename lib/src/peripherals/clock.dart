import '../cpu/cpu.dart';

const CLKPCE = 128;

class AVRClockConfig {
  final int CLKPR;

  const AVRClockConfig({required this.CLKPR});
}

const clockConfig = AVRClockConfig(
  CLKPR: 0x61,
);

const prescalers = [
  1, 2, 4, 8, 16, 32, 64, 128, 256,

  // The following values are "reserved" according to the datasheet, so we measured
  // with a scope to figure them out (on ATmega328p)
  2, 4, 8, 16, 32, 64, 128,
];

class AVRClock {
  final CPU cpu;
  final int baseFreqHz;
  final AVRClockConfig config;

  int clockEnabledCycles = 0;
  int prescalerValue = 1;
  double cyclesDelta = 0;

  AVRClock(this.cpu, this.baseFreqHz, [this.config = clockConfig]) {
    cpu.writeHooks[config.CLKPR] = (int clkpr, int oldValue, int addr, int mask) {
      if ((clockEnabledCycles == 0 || clockEnabledCycles < cpu.cycles) && clkpr == CLKPCE) {
        clockEnabledCycles = cpu.cycles + 4;
      } else if (clockEnabledCycles != 0 && clockEnabledCycles >= cpu.cycles) {
        clockEnabledCycles = 0;
        final index = clkpr & 0xf;
        final oldPrescaler = prescalerValue;
        prescalerValue = prescalers[index];
        cpu.data[config.CLKPR] = index;
        if (oldPrescaler != prescalerValue) {
          cyclesDelta =
              (cpu.cycles + cyclesDelta) * (oldPrescaler / prescalerValue) - cpu.cycles;
        }
      }
      return true;
    };
  }

  double get frequency {
    return baseFreqHz / prescalerValue;
  }

  int get prescaler {
    return prescalerValue;
  }

  double get timeNanos {
    return ((cpu.cycles + cyclesDelta) / frequency) * 1e9;
  }

  double get timeMicros {
    return ((cpu.cycles + cyclesDelta) / frequency) * 1e6;
  }

  double get timeMillis {
    return ((cpu.cycles + cyclesDelta) / frequency) * 1e3;
  }
}

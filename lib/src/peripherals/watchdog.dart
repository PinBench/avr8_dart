import '../cpu/cpu.dart';
import 'clock.dart';

class WatchdogConfig {
  final int watchdogInterrupt;
  final int MCUSR;
  final int WDTCSR;

  const WatchdogConfig({
    required this.watchdogInterrupt,
    required this.MCUSR,
    required this.WDTCSR,
  });
}

// Register bits:
const MCUSR_WDRF = 0x8; //  Watchdog System Reset Flag

const WDTCSR_WDIF = 0x80;
const WDTCSR_WDIE = 0x40;
const WDTCSR_WDP3 = 0x20;
const WDTCSR_WDCE = 0x10; // Watchdog Change Enable
const WDTCSR_WDE = 0x8;
const WDTCSR_WDP2 = 0x4;
const WDTCSR_WDP1 = 0x2;
const WDTCSR_WDP0 = 0x1;
const WDTCSR_WDP210 = WDTCSR_WDP2 | WDTCSR_WDP1 | WDTCSR_WDP0;

const WDTCSR_PROTECT_MASK = WDTCSR_WDE | WDTCSR_WDP3 | WDTCSR_WDP210;

const watchdogConfig = WatchdogConfig(
  watchdogInterrupt: 0x0c,
  MCUSR: 0x54,
  WDTCSR: 0x60,
);

class AVRWatchdog {
  final CPU cpu;
  final WatchdogConfig config;
  final AVRClock clock;

  final int clockFrequency = 128000;

  /// Used to keep track on the last write to WDCE. Once written, the WDE/WDP* bits can be changed.
  int changeEnabledCycles = 0;
  int watchdogTimeout = 0;
  bool enabledValue = false;
  bool scheduled = false;

  late final AVRInterruptConfig Watchdog;

  AVRWatchdog(this.cpu, this.config, this.clock) {
    Watchdog = AVRInterruptConfig(
      address: config.watchdogInterrupt,
      flagRegister: config.WDTCSR,
      flagMask: WDTCSR_WDIF,
      enableRegister: config.WDTCSR,
      enableMask: WDTCSR_WDIE,
    );

    cpu.onWatchdogReset = () {
      resetWatchdog();
    };

    cpu.writeHooks[config.WDTCSR] =
        (int value, int oldValue, int addr, int mask) {
      if ((value & WDTCSR_WDCE) != 0 && (value & WDTCSR_WDE) != 0) {
        changeEnabledCycles = cpu.cycles + 4;
        value = value & ~WDTCSR_PROTECT_MASK;
      } else {
        if (cpu.cycles >= changeEnabledCycles) {
          value =
              (value & ~WDTCSR_PROTECT_MASK) | (oldValue & WDTCSR_PROTECT_MASK);
        }
        enabledValue = (value & WDTCSR_WDE) != 0 || (value & WDTCSR_WDIE) != 0;
        cpu.data[config.WDTCSR] = value;
      }

      if (enabled) {
        resetWatchdog();
      }

      if (enabled && !scheduled) {
        cpu.addClockEvent(checkWatchdog, watchdogTimeout - cpu.cycles);
      }

      cpu.clearInterruptByFlag(Watchdog, value);
      return true;
    };
  }

  void resetWatchdog() {
    final cycles = ((clock.frequency / clockFrequency) * prescaler).floor();
    watchdogTimeout = cpu.cycles + cycles;
  }

  void checkWatchdog() {
    if (enabled && cpu.cycles >= watchdogTimeout) {
      // Watchdog timed out!
      final wdtcsr = cpu.data[config.WDTCSR];
      if ((wdtcsr & WDTCSR_WDIE) != 0) {
        cpu.setInterruptFlag(Watchdog);
      }
      if ((wdtcsr & WDTCSR_WDE) != 0) {
        if ((wdtcsr & WDTCSR_WDIE) != 0) {
          cpu.data[config.WDTCSR] &= ~WDTCSR_WDIE;
        } else {
          cpu.reset();
          scheduled = false;
          cpu.data[config.MCUSR] |= MCUSR_WDRF;
          return;
        }
      }
      resetWatchdog();
    }
    if (enabled) {
      scheduled = true;
      cpu.addClockEvent(checkWatchdog, watchdogTimeout - cpu.cycles);
    } else {
      scheduled = false;
    }
  }

  bool get enabled {
    return enabledValue;
  }

  /// The base clock frequency is 128KHz. Thus, a prescaler of 2048 gives 16ms timeout.
  int get prescaler {
    final wdtcsr = cpu.data[config.WDTCSR];
    final value = ((wdtcsr & WDTCSR_WDP3) >> 2) | (wdtcsr & WDTCSR_WDP210);
    return 2048 << value;
  }
}

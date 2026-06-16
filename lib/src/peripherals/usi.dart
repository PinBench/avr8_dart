import '../cpu/cpu.dart';
import 'gpio.dart';

const USICR = 0x2d;
const USISR = 0x2e;
const USIDR = 0x2f;
const USIBR = 0x30;

// USISR bits
const USICNT_MASK = 0xf;
const USIDC = 1 << 4;
const USIPF = 1 << 5;
const USIOIF = 1 << 6;
const USISIF = 1 << 7;

// USICR bits
const USITC = 1 << 0;
const USICLK = 1 << 1;
const USICS0 = 1 << 2;
const USICS1 = 1 << 3;
const USIWM0 = 1 << 4;
const USIWM1 = 1 << 5;
const USIOIE = 1 << 6;
const USISIE = 1 << 7;

class AVRUSI {
  late final AVRInterruptConfig START;
  late final AVRInterruptConfig OVF;

  AVRUSI(CPU cpu, AVRIOPort port, int portPin, int dataPin, int clockPin) {
    START = AVRInterruptConfig(
      address: 0xd,
      flagRegister: USISR,
      flagMask: USISIF,
      enableRegister: USICR,
      enableMask: USISIE,
    );

    OVF = AVRInterruptConfig(
      address: 0xe,
      flagRegister: USISR,
      flagMask: USIOIF,
      enableRegister: USICR,
      enableMask: USIOIE,
    );

    final PIN = portPin;
    final PORT = PIN + 2;

    port.addListener((int value, int oldValue) {
      final twoWire = (cpu.data[USICR] & USIWM1) == USIWM1;
      if (twoWire) {
        if ((value & (1 << clockPin)) != 0 && (value & (1 << dataPin)) == 0) {
          // Start condition detected
          cpu.setInterruptFlag(START);
        }
        if ((value & (1 << clockPin)) != 0 && (value & (1 << dataPin)) != 0) {
          // Stop condition detected
          cpu.data[USISR] |= USIPF;
        }
      }
    });

    void updateOutput() {
      final oldValue = cpu.data[PORT];
      final newValue = (cpu.data[USIDR] & 0x80) != 0
          ? oldValue | (1 << dataPin)
          : oldValue & ~(1 << dataPin);
      cpu.writeHooks[PORT]!(newValue, oldValue, PORT, 0xff);
      if ((newValue & 0x80) != 0 && (cpu.data[PIN] & 0x80) == 0) {
        cpu.data[USISR] |=
            USIDC; // Shout output HIGH (pulled-up), but input is LOW
      } else {
        cpu.data[USISR] &= ~USIDC;
      }
    }

    void count() {
      final counter = (cpu.data[USISR] + 1) & USICNT_MASK;
      cpu.data[USISR] = (cpu.data[USISR] & ~USICNT_MASK) | counter;
      if (counter == 0) {
        cpu.data[USIBR] = cpu.data[USIDR];
        cpu.setInterruptFlag(OVF);
      }
    }

    void shift(int inputValue) {
      cpu.data[USIDR] = (cpu.data[USIDR] << 1) | inputValue;
      updateOutput();
    }

    cpu.writeHooks[USIDR] = (int value, int oldValue, int addr, int mask) {
      cpu.data[USIDR] = value;
      updateOutput();
      return true;
    };

    cpu.writeHooks[USISR] = (int value, int oldValue, int addr, int mask) {
      const writeClearMask = USISIF | USIOIF | USIPF;
      cpu.data[USISR] =
          (cpu.data[USISR] & writeClearMask & ~value) | (value & 0xf);
      cpu.clearInterruptByFlag(START, value);
      cpu.clearInterruptByFlag(OVF, value);
      return true;
    };

    cpu.writeHooks[USICR] = (int value, int oldValue, int addr, int mask) {
      cpu.data[USICR] = value & ~(USICLK | USITC);
      cpu.updateInterruptEnable(START, value);
      cpu.updateInterruptEnable(OVF, value);

      final clockSrc = (value & (USICS1 | USICS0)) >> 2;
      final mode = (value & (USIWM1 | USIWM0)) >> 4;
      final usiClk = (value & USICLK) != 0;

      port.openCollector = mode >= 2 ? 1 << dataPin : 0;
      final inputValue = (cpu.data[PIN] & (1 << dataPin)) != 0 ? 1 : 0;

      if (usiClk && clockSrc == 0) {
        shift(inputValue);
        count();
      }

      if ((value & USITC) != 0) {
        cpu.writeHooks[PIN]!(1 << clockPin, cpu.data[PIN], PIN, 0xff);
        final newValue = (cpu.data[PIN] & (1 << clockPin)) != 0;
        if (usiClk && (clockSrc == 2 || clockSrc == 3)) {
          if (clockSrc == 2 && newValue) {
            shift(inputValue);
          }
          if (clockSrc == 3 && !newValue) {
            shift(inputValue);
          }
          count();
        }
        return true;
      }
      return false; // update logic handle USICR itself
    };
  }
}

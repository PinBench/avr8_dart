import 'dart:typed_data';
import '../cpu/cpu.dart';

abstract class EEPROMBackend {
  int readMemory(int addr);
  void writeMemory(int addr, int value);
  void eraseMemory(int addr);
}

class EEPROMMemoryBackend implements EEPROMBackend {
  final Uint8List memory;

  EEPROMMemoryBackend(int size) : memory = Uint8List(size) {
    memory.fillRange(0, size, 0xff);
  }

  @override
  int readMemory(int addr) {
    return memory[addr];
  }

  @override
  void writeMemory(int addr, int value) {
    memory[addr] &= value;
  }

  @override
  void eraseMemory(int addr) {
    memory[addr] = 0xff;
  }
}

class AVREEPROMConfig {
  final int eepromReadyInterrupt;
  final int EECR;
  final int EEDR;
  final int EEARL;
  final int EEARH;

  /// The amount of clock cycles erase takes
  final int eraseCycles;

  /// The amount of clock cycles a write takes
  final int writeCycles;

  const AVREEPROMConfig({
    required this.eepromReadyInterrupt,
    required this.EECR,
    required this.EEDR,
    required this.EEARL,
    required this.EEARH,
    required this.eraseCycles,
    required this.writeCycles,
  });
}

const eepromConfig = AVREEPROMConfig(
  eepromReadyInterrupt: 0x2c,
  EECR: 0x3f,
  EEDR: 0x40,
  EEARL: 0x41,
  EEARH: 0x42,
  eraseCycles: 28800, // 1.8ms at 16MHz
  writeCycles: 28800, // 1.8ms at 16MHz
);

const EERE = 1 << 0;
const EEPE = 1 << 1;
const EEMPE = 1 << 2;
const EERIE = 1 << 3;
const EEPM0 = 1 << 4;
const EEPM1 = 1 << 5;
const EECR_WRITE_MASK = EEPE | EEMPE | EERIE | EEPM0 | EEPM1;

class AVREEPROM {
  final CPU cpu;
  final EEPROMBackend backend;
  final AVREEPROMConfig config;

  /// Used to keep track on the last write to EEMPE. From the datasheet:
  /// The EEMPE bit determines whether setting EEPE to one causes the EEPROM to be written.
  /// When EEMPE is set, setting EEPE within four clock cycles will write data to the EEPROM
  /// at the selected address If EEMPE is zero, setting EEPE will have no effect.
  int writeEnabledCycles = 0;

  int writeCompleteCycles = 0;

  late final AVRInterruptConfig EER;

  AVREEPROM(this.cpu, this.backend, [this.config = eepromConfig]) {
    EER = AVRInterruptConfig(
      address: config.eepromReadyInterrupt,
      flagRegister: config.EECR,
      flagMask: EEPE,
      enableRegister: config.EECR,
      enableMask: EERIE,
      constant: true,
      inverseFlag: true,
    );

    cpu.writeHooks[config.EECR] = (int value, int oldValue, int addr, int mask) {
      final eecr = value;
      final memoryAddr = (cpu.data[config.EEARH] << 8) | cpu.data[config.EEARL];

      cpu.data[config.EECR] = (cpu.data[config.EECR] & ~EECR_WRITE_MASK) | (eecr & EECR_WRITE_MASK);
      cpu.updateInterruptEnable(EER, eecr);

      if ((eecr & EERE) != 0) {
        cpu.clearInterrupt(EER);
      }

      if ((eecr & EEMPE) != 0) {
        const eempeCycles = 4;
        writeEnabledCycles = cpu.cycles + eempeCycles;
        cpu.addClockEvent(() {
          cpu.data[config.EECR] &= ~EEMPE;
        }, eempeCycles);
      }

      // Read
      if ((eecr & EERE) != 0) {
        cpu.data[config.EEDR] = backend.readMemory(memoryAddr);
        // When the EEPROM is read, the CPU is halted for four cycles before the
        // next instruction is executed.
        cpu.cycles += 4;
        return true;
      }

      // Write
      if ((eecr & EEPE) != 0) {
        //  If EEMPE is zero, setting EEPE will have no effect.
        if (cpu.cycles >= writeEnabledCycles) {
          cpu.data[config.EECR] &= ~EEPE;
          return true;
        }
        // Check for write-in-progress
        if (cpu.cycles < writeCompleteCycles) {
          return true;
        }

        final eedr = cpu.data[config.EEDR];

        writeCompleteCycles = cpu.cycles;

        // Erase
        if ((eecr & EEPM1) == 0) {
          backend.eraseMemory(memoryAddr);
          writeCompleteCycles += config.eraseCycles;
        }
        // Write
        if ((eecr & EEPM0) == 0) {
          backend.writeMemory(memoryAddr, eedr);
          writeCompleteCycles += config.writeCycles;
        }

        cpu.data[config.EECR] |= EEPE;

        cpu.addClockEvent(() {
          cpu.setInterruptFlag(EER);
        }, writeCompleteCycles - cpu.cycles);

        // When EEPE has been set, the CPU is halted for two cycles before the
        // next instruction is executed.
        cpu.cycles += 2;
      }

      return true;
    };
  }
}

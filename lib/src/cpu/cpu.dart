// SPDX-License-Identifier: MIT
// Copyright (c) Uri Shaked and contributors

import 'dart:typed_data';
import '../types.dart';
import '../peripherals/gpio.dart';
import 'instruction.dart' show avrDecodeTable;
import 'interrupt.dart';

const int registerSpace = 0x100;
const int MAX_INTERRUPTS = 128; // Enough for ATMega2560

typedef CPUMemoryHook = bool Function(u8 value, u8 oldValue, u16 addr, u8 mask);

typedef CPUMemoryReadHook = u8 Function(u16 addr);

class AVRInterruptConfig {
  final u8 address;
  final u16 enableRegister;
  final u8 enableMask;
  final u16 flagRegister;
  final u8 flagMask;
  bool constant;
  final bool inverseFlag;

  AVRInterruptConfig({
    required this.address,
    required this.enableRegister,
    required this.enableMask,
    required this.flagRegister,
    required this.flagMask,
    this.constant = false,
    this.inverseFlag = false,
  });
}

typedef AVRClockEventCallback = void Function();

class AVRClockEventEntry {
  int cycles;
  AVRClockEventCallback callback;
  AVRClockEventEntry? next;

  AVRClockEventEntry({
    required this.cycles,
    required this.callback,
    this.next,
  });
}

/// The CPU's memory hooks, one slot per data-space address.
///
/// Indexed like the `Map<int, hook>` it replaced, but backed by a list: every
/// load and store the CPU executes looks up its address here, and a list
/// index is far cheaper than a hash lookup.
class CPUHookTable<T extends Function> {
  CPUHookTable(int size) : _hooks = List<T?>.filled(size, null);

  final List<T?> _hooks;

  /// The hook for [addr], or null if there is none.
  T? operator [](int addr) =>
      addr >= 0 && addr < _hooks.length ? _hooks[addr] : null;

  /// Sets the hook for [addr], which must be inside the data space.
  void operator []=(int addr, T hook) => _hooks[addr] = hook;

  bool containsKey(int addr) => this[addr] != null;

  /// Removes and returns the hook for [addr], if any.
  T? remove(int addr) {
    final hook = this[addr];
    if (hook != null) {
      _hooks[addr] = null;
    }
    return hook;
  }
}

class CPU {
  // Plain `final`, not `late final`: these are read by nearly every
  // instruction, and a `late` field pays an initialisation check per read.
  final Uint8List data;
  final Uint16List data16;
  final ByteData dataView;
  final Uint8List progBytes;

  /// [avrDecodeTable], held per CPU: a top-level `final` is initialised
  /// lazily, so reading it pays an initialisation check, where reading an
  /// instance field does not. `avrInstruction` reads it on every instruction.
  final Uint8List decodeTable = avrDecodeTable;

  final CPUHookTable<CPUMemoryReadHook> readHooks;
  final CPUHookTable<CPUMemoryHook> writeHooks;

  final List<AVRInterruptConfig?> pendingInterrupts =
      List.filled(MAX_INTERRUPTS, null);
  AVRClockEventEntry? nextClockEvent;
  final List<AVRClockEventEntry> clockEventPool = [];

  final bool pc22Bits;
  final Set<AVRIOPort> gpioPorts = {};
  final List<AVRIOPort?> gpioByPort =
      List.filled(registerSpace, null, growable: true);

  void Function() onWatchdogReset = () {};

  u32 pc = 0;
  int cycles = 0;
  i16 nextInterrupt = -1;
  i16 maxInterrupt = 0;

  final Uint16List progMem;
  final int sramBytes;

  CPU(Uint16List progMem, {int sramBytes = 8192})
      : this._(progMem, sramBytes, Uint8List(sramBytes + registerSpace));

  CPU._(this.progMem, this.sramBytes, this.data)
      : data16 = Uint16List.view(data.buffer),
        dataView = ByteData.view(data.buffer),
        progBytes = Uint8List.view(progMem.buffer),
        pc22Bits = Uint8List.view(progMem.buffer).length > 0x20000,
        readHooks = CPUHookTable(data.length),
        writeHooks = CPUHookTable(data.length) {
    reset();
  }

  void reset() {
    SP = data.length - 1;
    pc = 0;
    pendingInterrupts.fillRange(0, MAX_INTERRUPTS, null);
    nextInterrupt = -1;
    nextClockEvent = null;
  }

  int readData(int addr) {
    if (addr >= 32) {
      final hook = readHooks[addr];
      if (hook != null) {
        return hook(addr);
      }
    }
    return data[addr];
  }

  void writeData(int addr, int value, [int mask = 0xff]) {
    final hook = writeHooks[addr];
    if (hook != null) {
      if (hook(value, data[addr], addr, mask)) {
        return;
      }
    }
    data[addr] = value;
  }

  int get SP => dataView.getUint16(93, Endian.little);
  set SP(int value) => dataView.setUint16(93, value, Endian.little);

  int get SREG => data[95];

  bool get interruptsEnabled => (SREG & 0x80) != 0;

  void setInterruptFlag(AVRInterruptConfig interrupt) {
    if (interrupt.inverseFlag) {
      data[interrupt.flagRegister] &= ~interrupt.flagMask;
    } else {
      data[interrupt.flagRegister] |= interrupt.flagMask;
    }
    if ((data[interrupt.enableRegister] & interrupt.enableMask) != 0) {
      queueInterrupt(interrupt);
    }
  }

  void updateInterruptEnable(AVRInterruptConfig interrupt, int registerValue) {
    if ((registerValue & interrupt.enableMask) != 0) {
      final bitSet = (data[interrupt.flagRegister] & interrupt.flagMask) != 0;
      if (interrupt.inverseFlag ? !bitSet : bitSet) {
        queueInterrupt(interrupt);
      }
    } else {
      clearInterrupt(interrupt, clearFlag: false);
    }
  }

  void queueInterrupt(AVRInterruptConfig interrupt) {
    final address = interrupt.address;
    pendingInterrupts[address] = interrupt;
    if (nextInterrupt == -1 || nextInterrupt > address) {
      nextInterrupt = address;
    }
    if (address > maxInterrupt) {
      maxInterrupt = address;
    }
  }

  void clearInterrupt(AVRInterruptConfig interrupt, {bool clearFlag = true}) {
    if (clearFlag) {
      data[interrupt.flagRegister] &= ~interrupt.flagMask;
    }
    final address = interrupt.address;
    if (pendingInterrupts[address] == null) {
      return;
    }
    pendingInterrupts[address] = null;
    if (nextInterrupt == address) {
      nextInterrupt = -1;
      for (int i = address + 1; i <= maxInterrupt; i++) {
        if (pendingInterrupts[i] != null) {
          nextInterrupt = i;
          break;
        }
      }
    }
  }

  void clearInterruptByFlag(AVRInterruptConfig interrupt, int registerValue) {
    if ((registerValue & interrupt.flagMask) != 0) {
      data[interrupt.flagRegister] &= ~interrupt.flagMask;
      clearInterrupt(interrupt);
    }
  }

  AVRClockEventCallback addClockEvent(
      AVRClockEventCallback callback, int cyclesArg) {
    int actualCycles = cycles + (cyclesArg > 1 ? cyclesArg : 1);
    AVRClockEventEntry entry;
    if (clockEventPool.isNotEmpty) {
      entry = clockEventPool.removeLast();
      entry.cycles = actualCycles;
      entry.callback = callback;
      entry.next = null;
    } else {
      entry = AVRClockEventEntry(cycles: actualCycles, callback: callback);
    }

    AVRClockEventEntry? clockEvent = nextClockEvent;
    AVRClockEventEntry? lastItem;

    while (clockEvent != null && clockEvent.cycles < actualCycles) {
      lastItem = clockEvent;
      clockEvent = clockEvent.next;
    }

    if (lastItem != null) {
      lastItem.next = entry;
      entry.next = clockEvent;
    } else {
      nextClockEvent = entry;
      entry.next = clockEvent;
    }
    return callback;
  }

  bool updateClockEvent(AVRClockEventCallback callback, int cycles) {
    if (clearClockEvent(callback)) {
      addClockEvent(callback, cycles);
      return true;
    }
    return false;
  }

  bool clearClockEvent(AVRClockEventCallback callback) {
    AVRClockEventEntry? clockEvent = nextClockEvent;
    if (clockEvent == null) {
      return false;
    }

    AVRClockEventEntry? lastItem;
    while (clockEvent != null) {
      if (clockEvent.callback == callback) {
        if (lastItem != null) {
          lastItem.next = clockEvent.next;
        } else {
          nextClockEvent = clockEvent.next;
        }
        if (clockEventPool.length < 10) {
          clockEventPool.add(clockEvent);
        }
        return true;
      }
      lastItem = clockEvent;
      clockEvent = clockEvent.next;
    }
    return false;
  }

  void tick() {
    if (nextClockEvent != null && nextClockEvent!.cycles <= cycles) {
      final event = nextClockEvent!;
      event.callback();
      nextClockEvent = event.next;
      if (clockEventPool.length < 10) {
        clockEventPool.add(event);
      }
    }

    if (interruptsEnabled && nextInterrupt >= 0) {
      final interrupt = pendingInterrupts[nextInterrupt]!;
      avrInterrupt(this, interrupt.address);
      if (!interrupt.constant) {
        clearInterrupt(interrupt);
      }
    }
  }
}

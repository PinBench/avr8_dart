import 'dart:typed_data';
import 'package:avr8_dart/src/cpu/cpu.dart';
import 'package:avr8_dart/src/cpu/instruction.dart';
import 'package:avr8_dart/src/utils/assembler.dart';

const BREAK_OPCODE = 0x9598;

class AsmProgramResult {
  final Uint16List program;
  final List<LineTable> lines;
  final int instructionCount;
  final Map<String, int> labels;

  AsmProgramResult({
    required this.program,
    required this.lines,
    required this.instructionCount,
    required this.labels,
  });
}

AsmProgramResult asmProgram(String source) {
  final res = assemble(source);
  if (res.errors.isNotEmpty) {
    throw Exception('Assembly failed: ${res.errors}');
  }
  return AsmProgramResult(
    program: Uint16List.view(res.bytes.buffer),
    lines: res.lines,
    instructionCount: res.lines.length,
    labels: res.labels,
  );
}

void defaultOnBreak(CPU cpu) {
  throw Exception('BREAK instruction encountered');
}

class TestProgramRunner {
  final CPU cpu;
  final void Function(CPU) onBreak;

  TestProgramRunner(this.cpu, [this.onBreak = defaultOnBreak]);

  void runInstructions(int count) {
    for (int i = 0; i < count; i++) {
      if (cpu.progMem[cpu.pc] == BREAK_OPCODE) {
        onBreak(cpu);
      }
      avrInstruction(cpu);
      cpu.tick();
    }
  }

  void runUntil(bool Function(CPU) predicate, [int maxIterations = 5000]) {
    for (int i = 0; i < maxIterations; i++) {
      if (cpu.progMem[cpu.pc] == BREAK_OPCODE) {
        onBreak(cpu);
      }
      if (predicate(cpu)) {
        return;
      }
      avrInstruction(cpu);
      cpu.tick();
    }
    throw Exception('Test program ran for too long, check your predicate');
  }

  void runToBreak() {
    runUntil((cpu) => cpu.progMem[cpu.pc] == BREAK_OPCODE);
  }

  void runToAddress(int byteAddr) {
    runUntil((cpu) => cpu.pc * 2 == byteAddr);
  }
}

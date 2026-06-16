import 'package:avr8_dart/src/cpu/cpu.dart';
import 'package:avr8_dart/src/cpu/instruction.dart';
import 'package:avr8_dart/src/peripherals/spi.dart';
import 'test_utils.dart';
import 'dart:typed_data';

const SPCR = 0x4c;
const SPSR = 0x4d;
const SPDR = 0x4e;

void main() {
      final asm = asmProgram('''
      _REPLACE SPCR, \${SPCR - 0x20}
      _REPLACE SPDR, \${SPDR - 0x20}
      _REPLACE SPSR, \${SPSR - 0x20}
      _REPLACE DDR_SPI, 0x4 ; PORTB

      SPI_MasterInit:
        LDI r17, 0x28
        OUT DDR_SPI, r17
        LDI r17, 0x51
        OUT SPCR, r17

      SPI_MasterTransmit:
        LDI r16, 0xb8
        OUT SPDR, r16

      Wait_Transmit:
        IN r16, SPSR
        SBRS r16, 7
        RJMP Wait_Transmit
      
        IN r17, SPDR
        BREAK
    ''');

      final cpu = CPU(asm.program);
      final spi = AVRSPI(cpu, spiConfig, 16000000);

      spi.onByte = (value) {
        cpu.addClockEvent(() => spi.completeTransfer(0x5b), spi.transferCycles);
      };

      for(int i = 0; i < 20; i++) {
        print("PC: \${cpu.pc}, r16: \${cpu.data[16].toRadixString(16)}, SPSR: \${cpu.data[SPSR].toRadixString(16)}");
        avrInstruction(cpu);
        cpu.tick();
        if (cpu.progMem[cpu.pc] == 0x9598) break;
      }
      print("Cycles: \${cpu.cycles}");
}

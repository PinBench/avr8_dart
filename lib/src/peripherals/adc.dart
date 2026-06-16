import 'dart:math';
import '../cpu/cpu.dart';

enum ADCReference {
  AVCC,
  AREF,
  Internal1V1,
  Internal2V56,
  Reserved,
}

enum ADCMuxInputType {
  SingleEnded,
  Differential,
  Constant,
  Temperature,
}

abstract class ADCMuxInput {
  final ADCMuxInputType type;
  const ADCMuxInput(this.type);
}

class ADCMuxInputTemperature extends ADCMuxInput {
  const ADCMuxInputTemperature() : super(ADCMuxInputType.Temperature);
}

class ADCMuxInputConstant extends ADCMuxInput {
  final double voltage;
  const ADCMuxInputConstant(this.voltage) : super(ADCMuxInputType.Constant);
}

class ADCMuxInputSingleEnded extends ADCMuxInput {
  final int channel;
  const ADCMuxInputSingleEnded(this.channel)
      : super(ADCMuxInputType.SingleEnded);
}

class ADCMuxInputDifferential extends ADCMuxInput {
  final int positiveChannel;
  final int negativeChannel;
  final double gain;
  const ADCMuxInputDifferential(
      this.positiveChannel, this.negativeChannel, this.gain)
      : super(ADCMuxInputType.Differential);
}

typedef ADCMuxConfiguration = Map<int, ADCMuxInput>;

class ADCConfig {
  final int ADMUX;
  final int ADCSRA;
  final int ADCSRB;
  final int ADCL;
  final int ADCH;
  final int DIDR0;
  final int adcInterrupt;
  final int numChannels;
  final int muxInputMask;
  final ADCMuxConfiguration muxChannels;
  final List<ADCReference> adcReferences;

  const ADCConfig({
    required this.ADMUX,
    required this.ADCSRA,
    required this.ADCSRB,
    required this.ADCL,
    required this.ADCH,
    required this.DIDR0,
    required this.adcInterrupt,
    required this.numChannels,
    required this.muxInputMask,
    required this.muxChannels,
    required this.adcReferences,
  });
}

const atmega328Channels = <int, ADCMuxInput>{
  0: ADCMuxInputSingleEnded(0),
  1: ADCMuxInputSingleEnded(1),
  2: ADCMuxInputSingleEnded(2),
  3: ADCMuxInputSingleEnded(3),
  4: ADCMuxInputSingleEnded(4),
  5: ADCMuxInputSingleEnded(5),
  6: ADCMuxInputSingleEnded(6),
  7: ADCMuxInputSingleEnded(7),
  8: ADCMuxInputTemperature(),
  14: ADCMuxInputConstant(1.1),
  15: ADCMuxInputConstant(0),
};

const fallbackMuxInput = ADCMuxInputConstant(0);

const adcConfig = ADCConfig(
  ADMUX: 0x7c,
  ADCSRA: 0x7a,
  ADCSRB: 0x7b,
  ADCL: 0x78,
  ADCH: 0x79,
  DIDR0: 0x7e,
  adcInterrupt: 0x2a,
  numChannels: 8,
  muxInputMask: 0xf,
  muxChannels: atmega328Channels,
  adcReferences: [
    ADCReference.AREF,
    ADCReference.AVCC,
    ADCReference.Reserved,
    ADCReference.Internal1V1,
  ],
);

// Register bits:
const ADPS_MASK = 0x7;
const ADIE = 0x8;
const ADIF = 0x10;
const ADSC = 0x40;
const ADEN = 0x80;

const MUX_MASK = 0x1f;
const ADLAR = 0x20;
const MUX5 = 0x8;
const REFS2 = 0x8;
const REFS_MASK = 0x3;
const REFS_SHIFT = 6;

class AVRADC {
  final CPU cpu;
  final ADCConfig config;

  /// ADC Channel values, in voltage (0..5). The number of channels depends on the chip.
  ///
  /// Changing the values here will change the ADC reading, unless you override onADCRead() with a custom implementation.
  late final List<double> channelValues;

  /// AVCC Reference voltage
  double avcc = 5.0;

  /// AREF Reference voltage
  double aref = 5.0;

  late void Function(ADCMuxInput) onADCRead;

  bool converting = false;
  int conversionCycles = 25;

  late final AVRInterruptConfig ADC;

  AVRADC(this.cpu, this.config) {
    channelValues = List.filled(config.numChannels, 0.0);

    onADCRead = (ADCMuxInput input) {
      double voltage = 0.0;
      if (input is ADCMuxInputConstant) {
        voltage = input.voltage;
      } else if (input is ADCMuxInputSingleEnded) {
        voltage = channelValues[input.channel];
      } else if (input is ADCMuxInputDifferential) {
        voltage = input.gain *
            (channelValues[input.positiveChannel] -
                channelValues[input.negativeChannel]);
      } else if (input is ADCMuxInputTemperature) {
        voltage = 0.378125; // 25 celcius
      }

      final rawValue = (voltage / referenceVoltage) * 1024;
      final result = min(max(rawValue.floor(), 0), 1023);
      cpu.addClockEvent(() => completeADCRead(result), sampleCycles);
    };

    ADC = AVRInterruptConfig(
      address: config.adcInterrupt,
      flagRegister: config.ADCSRA,
      flagMask: ADIF,
      enableRegister: config.ADCSRA,
      enableMask: ADIE,
    );

    cpu.writeHooks[config.ADCSRA] =
        (int value, int oldValue, int addr, int mask) {
      if ((value & ADEN) != 0 && (oldValue & ADEN) == 0) {
        conversionCycles = 25;
      }
      cpu.data[config.ADCSRA] = value;
      cpu.updateInterruptEnable(ADC, value);
      if (!converting && (value & ADSC) != 0) {
        if ((value & ADEN) == 0) {
          // Special case: reading while the ADC is not enabled should return 0
          cpu.addClockEvent(() => completeADCRead(0), sampleCycles);
          return true;
        }
        int channel = cpu.data[config.ADMUX] & MUX_MASK;
        if ((cpu.data[config.ADCSRB] & MUX5) != 0) {
          channel |= 0x20;
        }
        channel &= config.muxInputMask;
        final muxInput = config.muxChannels[channel] ?? fallbackMuxInput;
        converting = true;
        onADCRead(muxInput);
        return true; // don't update
      }
      return false; // update normal logic
    };
  }

  void completeADCRead(int value) {
    converting = false;
    conversionCycles = 13;
    if ((cpu.data[config.ADMUX] & ADLAR) != 0) {
      cpu.data[config.ADCL] = (value << 6) & 0xff;
      cpu.data[config.ADCH] = value >> 2;
    } else {
      cpu.data[config.ADCL] = value & 0xff;
      cpu.data[config.ADCH] = (value >> 8) & 0x3;
    }
    cpu.data[config.ADCSRA] &= ~ADSC;
    cpu.setInterruptFlag(ADC);
  }

  int get prescaler {
    final adcsra = cpu.data[config.ADCSRA];
    final adps = adcsra & ADPS_MASK;
    switch (adps) {
      case 0:
      case 1:
        return 2;
      case 2:
        return 4;
      case 3:
        return 8;
      case 4:
        return 16;
      case 5:
        return 32;
      case 6:
        return 64;
      case 7:
      default:
        return 128;
    }
  }

  ADCReference get referenceVoltageType {
    int refs = (cpu.data[config.ADMUX] >> REFS_SHIFT) & REFS_MASK;
    if (config.adcReferences.length > 4 &&
        (cpu.data[config.ADMUX] & REFS2) != 0) {
      refs |= 0x4;
    }
    if (refs < config.adcReferences.length) {
      return config.adcReferences[refs];
    }
    return ADCReference.Reserved;
  }

  double get referenceVoltage {
    switch (referenceVoltageType) {
      case ADCReference.AVCC:
        return avcc;
      case ADCReference.AREF:
        return aref;
      case ADCReference.Internal1V1:
        return 1.1;
      case ADCReference.Internal2V56:
        return 2.56;
      default:
        return avcc;
    }
  }

  int get sampleCycles {
    return conversionCycles * prescaler;
  }
}

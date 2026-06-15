import 'dart:math';
import 'dart:typed_data';

typedef LabelTable = Map<String, int>;

abstract class Pass1Bytes {}

class Pass1BytesString extends Pass1Bytes {
  final String value;
  Pass1BytesString(this.value);
}

class Pass1BytesFunction extends Pass1Bytes {
  final String Function(LabelTable) func;
  Pass1BytesFunction(this.func);
}

class Pass1BytesList extends Pass1Bytes {
  final List<String> list;
  Pass1BytesList(this.list);
}

class Pass1BytesTuple extends Pass1Bytes {
  final List<String> Function(LabelTable) func;
  final String placeholder;
  Pass1BytesTuple(this.func, this.placeholder);
}

class LineTablePass1 {
  final int line;
  Pass1Bytes bytes;
  final String text;
  int byteOffset;

  LineTablePass1({
    required this.line,
    required this.bytes,
    required this.text,
    required this.byteOffset,
  });
}

class LineTable {
  final int line;
  final dynamic bytes;
  final String text;
  final int byteOffset;

  LineTable({
    required this.line,
    required this.bytes,
    required this.text,
    required this.byteOffset,
  });
}

int destRindex(String r, [int min = 0, int max = 31]) {
  final match = RegExp(r'[Rr](\d{1,2})').firstMatch(r);
  if (match == null) {
    throw 'Not a register: $r';
  }
  final d = int.parse(match.group(1)!);
  if (d < min || d > max) {
    throw 'Rd out of range: $min<>$max';
  }
  return (d & 0x1f) << 4;
}

int srcRindex(String r, [int min = 0, int max = 31]) {
  final match = RegExp(r'[Rr](\d{1,2})').firstMatch(r);
  if (match == null) {
    throw 'Not a register: $r';
  }
  final d = int.parse(match.group(1)!);
  if (d < min || d > max) {
    throw 'Rd out of range: $min<>$max';
  }
  int s = d & 0xf;
  s |= ((d >> 4) & 1) << 9;
  return s;
}

int constValue(dynamic r, [int min = 0, int max = 255]) {
  final int d;
  if (r is String) {
    d = int.tryParse(r) ?? (throw 'constant is not a number.');
  } else {
    d = r as int;
  }
  if (d < min || d > max) {
    throw '[Ks] out of range: $min<>$max';
  }
  return d;
}

int fitTwoC(int r, int bits) {
  if (bits < 2) throw 'Need at least 2 bits to be signed.';
  if (bits > 16) throw 'fitTwoC only works on 16bit numbers for now.';
  if (r.abs() > pow(2, bits - 1)) throw 'Not enough bits for number. ($r, $bits)';
  if (r < 0) {
    r = 0xffff + r + 1;
  }
  final mask = 0xffff >> (16 - bits);
  return r & mask;
}

num constOrLabel(dynamic c, LabelTable labels, [int offset = 0]) {
  if (c is String) {
    final d = int.tryParse(c);
    if (d == null) {
      if (labels.containsKey(c)) {
        return labels[c]! - offset;
      } else {
        return double.nan;
      }
    }
    return d;
  }
  return c as num;
}

String zeroPad(dynamic r, [int len = 4]) {
  final int val;
  if (r is String) {
    val = int.parse(r);
  } else {
    val = r as int;
  }
  final hex = val.toRadixString(16);
  return hex.padLeft(len, '0');
}

int stldXYZ(String xyz) {
  switch (xyz) {
    case 'X':
      return 0x900c;
    case 'X+':
      return 0x900d;
    case '-X':
      return 0x900e;
    case 'Y':
      return 0x8008;
    case 'Y+':
      return 0x9009;
    case '-Y':
      return 0x900a;
    case 'Z':
      return 0x8000;
    case 'Z+':
      return 0x9001;
    case '-Z':
      return 0x9002;
    default:
      throw 'Not -?[XYZ]\\+?';
  }
}

int stldYZq(String yzq) {
  final d = RegExp(r'([YZ])\+(\d+)').firstMatch(yzq);
  int r = 0x8000;
  if (d == null) {
    throw 'Invalid arguments';
  }
  switch (d.group(1)) {
    case 'Y':
      r |= 0x8;
      break;
    case 'Z':
      break;
    default:
      throw 'Not Y or Z with q';
  }
  final q = int.parse(d.group(2)!);
  if (q < 0 || q > 64) {
    throw 'q is out of range';
  }
  r |= ((q & 0x20) << 8) | ((q & 0x18) << 7) | (q & 0x7);
  return r;
}

typedef OpcodeHandler = Pass1Bytes Function(String? a, String? b, int byteLoc, LabelTable labels);

Pass1BytesString SEflag(int a) {
  return Pass1BytesString(zeroPad(0x9408 | (constValue(a, 0, 7) << 4)));
}

final Map<String, OpcodeHandler> OPTABLE = <String, OpcodeHandler>{
  'ADD': (a, b, byteLoc, labels) {
    final r = 0x0c00 | destRindex(a!) | srcRindex(b!);
    return Pass1BytesString(zeroPad(r));
  },
  'ADC': (a, b, byteLoc, labels) {
    final r = 0x1c00 | destRindex(a!) | srcRindex(b!);
    return Pass1BytesString(zeroPad(r));
  },
  'ADIW': (a, b, byteLoc, labels) {
    int r = 0x9600;
    final dm = RegExp(r'[Rr](24|26|28|30)').firstMatch(a!);
    if (dm == null) throw 'Rd must be 24, 26, 28, or 30';
    int d = int.parse(dm.group(1)!);
    d = (d - 24) ~/ 2;
    r |= (d & 0x3) << 4;
    final k = constValue(b!, 0, 63);
    r |= ((k & 0x30) << 2) | (k & 0x0f);
    return Pass1BytesString(zeroPad(r));
  },
  'AND': (a, b, byteLoc, labels) {
    final r = 0x2000 | destRindex(a!) | srcRindex(b!);
    return Pass1BytesString(zeroPad(r));
  },
  'ANDI': (a, b, byteLoc, labels) {
    int r = 0x7000 | (destRindex(a!, 16, 31) & 0xf0);
    final k = constValue(b!);
    r |= ((k & 0xf0) << 4) | (k & 0xf);
    return Pass1BytesString(zeroPad(r));
  },
  'ASR': (a, b, byteLoc, labels) {
    final r = 0x9405 | destRindex(a!);
    return Pass1BytesString(zeroPad(r));
  },
  'BCLR': (a, b, byteLoc, labels) {
    int r = 0x9488;
    final s = constValue(a!, 0, 7);
    r |= (s & 0x7) << 4;
    return Pass1BytesString(zeroPad(r));
  },
  'BLD': (a, b, byteLoc, labels) {
    final r = 0xf800 | destRindex(a!) | (constValue(b!, 0, 7) & 0x7);
    return Pass1BytesString(zeroPad(r));
  },
  'BRBC': (a, b, byteLoc, labels) {
    final k = constOrLabel(b!, labels, byteLoc + 2);
    if (k.isNaN) {
      return Pass1BytesFunction((l) {
        return (OPTABLE['BRBC']!(a, b, byteLoc, l) as Pass1BytesString).value;
      });
    }
    int r = 0xf400 | constValue(a!, 0, 7);
    r |= fitTwoC(constValue(k.toInt() >> 1, -64, 63), 7) << 3;
    return Pass1BytesString(zeroPad(r));
  },
  'BRBS': (a, b, byteLoc, labels) {
    final k = constOrLabel(b!, labels, byteLoc + 2);
    if (k.isNaN) {
      return Pass1BytesFunction((l) {
        return (OPTABLE['BRBS']!(a, b, byteLoc, l) as Pass1BytesString).value;
      });
    }
    int r = 0xf000 | constValue(a!, 0, 7);
    r |= fitTwoC(constValue(k.toInt() >> 1, -64, 63), 7) << 3;
    return Pass1BytesString(zeroPad(r));
  },
  'BRCC': (a, b, byteLoc, labels) => OPTABLE['BRBC']!('0', a, byteLoc, labels),
  'BRCS': (a, b, byteLoc, labels) => OPTABLE['BRBS']!('0', a, byteLoc, labels),
  'BREAK': (a, b, byteLoc, labels) => Pass1BytesString('9598'),
  'BREQ': (a, b, byteLoc, labels) => OPTABLE['BRBS']!('1', a, byteLoc, labels),
  'BRGE': (a, b, byteLoc, labels) => OPTABLE['BRBC']!('4', a, byteLoc, labels),
  'BRHC': (a, b, byteLoc, labels) => OPTABLE['BRBC']!('5', a, byteLoc, labels),
  'BRHS': (a, b, byteLoc, labels) => OPTABLE['BRBS']!('5', a, byteLoc, labels),
  'BRID': (a, b, byteLoc, labels) => OPTABLE['BRBC']!('7', a, byteLoc, labels),
  'BRIE': (a, b, byteLoc, labels) => OPTABLE['BRBS']!('7', a, byteLoc, labels),
  'BRLO': (a, b, byteLoc, labels) => OPTABLE['BRBS']!('0', a, byteLoc, labels),
  'BRLT': (a, b, byteLoc, labels) => OPTABLE['BRBS']!('4', a, byteLoc, labels),
  'BRMI': (a, b, byteLoc, labels) => OPTABLE['BRBS']!('2', a, byteLoc, labels),
  'BRNE': (a, b, byteLoc, labels) => OPTABLE['BRBC']!('1', a, byteLoc, labels),
  'BRPL': (a, b, byteLoc, labels) => OPTABLE['BRBC']!('2', a, byteLoc, labels),
  'BRSH': (a, b, byteLoc, labels) => OPTABLE['BRBC']!('0', a, byteLoc, labels),
  'BRTC': (a, b, byteLoc, labels) => OPTABLE['BRBC']!('6', a, byteLoc, labels),
  'BRTS': (a, b, byteLoc, labels) => OPTABLE['BRBS']!('6', a, byteLoc, labels),
  'BRVC': (a, b, byteLoc, labels) => OPTABLE['BRBC']!('3', a, byteLoc, labels),
  'BRVS': (a, b, byteLoc, labels) => OPTABLE['BRBS']!('3', a, byteLoc, labels),
  'BSET': (a, b, byteLoc, labels) {
    int r = 0x9408;
    final s = constValue(a!, 0, 7);
    r |= (s & 0x7) << 4;
    return Pass1BytesString(zeroPad(r));
  },
  'BST': (a, b, byteLoc, labels) {
    final r = 0xfa00 | destRindex(a!) | constValue(b!, 0, 7);
    return Pass1BytesString(zeroPad(r));
  },
  'CALL': (a, b, byteLoc, labels) {
    num k = constOrLabel(a!, labels);
    if (k.isNaN) {
      return Pass1BytesTuple((l) {
        final res = OPTABLE['CALL']!(a, b, byteLoc, l) as Pass1BytesList;
        return res.list;
      }, 'xxxx');
    }
    int r = 0x940e;
    k = constValue(k, 0, 0x400000) >> 1;
    final lk = k.toInt() & 0xffff;
    final hk = (k.toInt() >> 16) & 0x3f;
    r |= ((hk & 0x3e) << 3) | (hk & 1);
    return Pass1BytesList([zeroPad(r), zeroPad(lk)]);
  },
  'CBI': (a, b, byteLoc, labels) {
    final r = 0x9800 | (constValue(a!, 0, 31) << 3) | constValue(b!, 0, 7);
    return Pass1BytesString(zeroPad(r));
  },
  'CRB': (a, b, byteLoc, labels) {
    final k = constValue(b!);
    return OPTABLE['ANDI']!(a, (~k & 0xff).toString(), byteLoc, labels);
  },
  'CLC': (a, b, byteLoc, labels) => Pass1BytesString('9488'),
  'CLH': (a, b, byteLoc, labels) => Pass1BytesString('94d8'),
  'CLI': (a, b, byteLoc, labels) => Pass1BytesString('94f8'),
  'CLN': (a, b, byteLoc, labels) => Pass1BytesString('94a8'),
  'CLR': (a, b, byteLoc, labels) => OPTABLE['EOR']!(a, a, byteLoc, labels),
  'CLS': (a, b, byteLoc, labels) => Pass1BytesString('94c8'),
  'CLT': (a, b, byteLoc, labels) => Pass1BytesString('94e8'),
  'CLV': (a, b, byteLoc, labels) => Pass1BytesString('94b8'),
  'CLZ': (a, b, byteLoc, labels) => Pass1BytesString('9498'),
  'COM': (a, b, byteLoc, labels) {
    final r = 0x9400 | destRindex(a!);
    return Pass1BytesString(zeroPad(r));
  },
  'CP': (a, b, byteLoc, labels) {
    final r = 0x1400 | destRindex(a!) | srcRindex(b!);
    return Pass1BytesString(zeroPad(r));
  },
  'CPC': (a, b, byteLoc, labels) {
    final r = 0x0400 | destRindex(a!) | srcRindex(b!);
    return Pass1BytesString(zeroPad(r));
  },
  'CPI': (a, b, byteLoc, labels) {
    int r = 0x3000 | (destRindex(a!, 16, 31) & 0xf0);
    final k = constValue(b!);
    r |= ((k & 0xf0) << 4) | (k & 0xf);
    return Pass1BytesString(zeroPad(r));
  },
  'CPSE': (a, b, byteLoc, labels) {
    final r = 0x1000 | destRindex(a!) | srcRindex(b!);
    return Pass1BytesString(zeroPad(r));
  },
  'DEC': (a, b, byteLoc, labels) {
    final r = 0x940a | destRindex(a!);
    return Pass1BytesString(zeroPad(r));
  },
  'DES': (a, b, byteLoc, labels) {
    final r = 0x940b | (constValue(a!, 0, 15) << 4);
    return Pass1BytesString(zeroPad(r));
  },
  'EICALL': (a, b, byteLoc, labels) => Pass1BytesString('9519'),
  'EIJMP': (a, b, byteLoc, labels) => Pass1BytesString('9419'),
  'ELPM': (a, b, byteLoc, labels) {
    if (a == null || a.isEmpty) return Pass1BytesString('95d8');
    int r = 0x9000 | destRindex(a);
    switch (b) {
      case 'Z':
        r |= 6;
        break;
      case 'Z+':
        r |= 7;
        break;
      default:
        throw 'Bad operand';
    }
    return Pass1BytesString(zeroPad(r));
  },
  'EOR': (a, b, byteLoc, labels) {
    final r = 0x2400 | destRindex(a!) | srcRindex(b!);
    return Pass1BytesString(zeroPad(r));
  },
  'FMUL': (a, b, byteLoc, labels) {
    final r = 0x0308 | (destRindex(a!, 16, 23) & 0x70) | (srcRindex(b!, 16, 23) & 0x7);
    return Pass1BytesString(zeroPad(r));
  },
  'FMULS': (a, b, byteLoc, labels) {
    final r = 0x0380 | (destRindex(a!, 16, 23) & 0x70) | (srcRindex(b!, 16, 23) & 0x7);
    return Pass1BytesString(zeroPad(r));
  },
  'FMULSU': (a, b, byteLoc, labels) {
    final r = 0x0388 | (destRindex(a!, 16, 23) & 0x70) | (srcRindex(b!, 16, 23) & 0x7);
    return Pass1BytesString(zeroPad(r));
  },
  'ICALL': (a, b, byteLoc, labels) => Pass1BytesString('9509'),
  'IJMP': (a, b, byteLoc, labels) => Pass1BytesString('9409'),
  'IN': (a, b, byteLoc, labels) {
    int r = 0xb000 | destRindex(a!);
    final A = constValue(b!, 0, 63);
    r |= ((A & 0x30) << 5) | (A & 0x0f);
    return Pass1BytesString(zeroPad(r));
  },
  'INC': (a, b, byteLoc, labels) {
    final r = 0x9403 | destRindex(a!);
    return Pass1BytesString(zeroPad(r));
  },
  'JMP': (a, b, byteLoc, labels) {
    num k = constOrLabel(a!, labels);
    if (k.isNaN) {
      return Pass1BytesTuple((l) {
        final res = OPTABLE['JMP']!(a, b, byteLoc, l) as Pass1BytesList;
        return res.list;
      }, 'xxxx');
    }
    int r = 0x940c;
    k = constValue(k, 0, 0x400000) >> 1;
    final lk = k.toInt() & 0xffff;
    final hk = (k.toInt() >> 16) & 0x3f;
    r |= ((hk & 0x3e) << 3) | (hk & 1);
    return Pass1BytesList([zeroPad(r), zeroPad(lk)]);
  },
  'LAC': (a, b, byteLoc, labels) {
    if (a != 'Z') throw 'First Operand is not Z';
    final r = 0x9206 | destRindex(b!);
    return Pass1BytesString(zeroPad(r));
  },
  'LAS': (a, b, byteLoc, labels) {
    if (a != 'Z') throw 'First Operand is not Z';
    final r = 0x9205 | destRindex(b!);
    return Pass1BytesString(zeroPad(r));
  },
  'LAT': (a, b, byteLoc, labels) {
    if (a != 'Z') throw 'First Operand is not Z';
    final r = 0x9207 | destRindex(b!);
    return Pass1BytesString(zeroPad(r));
  },
  'LD': (a, b, byteLoc, labels) {
    final r = 0x0000 | destRindex(a!) | stldXYZ(b!);
    return Pass1BytesString(zeroPad(r));
  },
  'LDD': (a, b, byteLoc, labels) {
    final r = 0x0000 | destRindex(a!) | stldYZq(b!);
    return Pass1BytesString(zeroPad(r));
  },
  'LDI': (a, b, byteLoc, labels) {
    int r = 0xe000 | (destRindex(a!, 16, 31) & 0xf0);
    final k = constValue(b!);
    r |= ((k & 0xf0) << 4) | (k & 0xf);
    return Pass1BytesString(zeroPad(r));
  },
  'LDS': (a, b, byteLoc, labels) {
    final k = constValue(b!, 0, 65535);
    final r = 0x9000 | destRindex(a!);
    return Pass1BytesList([zeroPad(r), zeroPad(k)]);
  },
  'LPM': (a, b, byteLoc, labels) {
    if (a == null || a.isEmpty) return Pass1BytesString('95c8');
    int r = 0x9000 | destRindex(a);
    switch (b) {
      case 'Z':
        r |= 4;
        break;
      case 'Z+':
        r |= 5;
        break;
      default:
        throw 'Bad operand';
    }
    return Pass1BytesString(zeroPad(r));
  },
  'LSL': (a, b, byteLoc, labels) => OPTABLE['ADD']!(a, a, byteLoc, labels),
  'LSR': (a, b, byteLoc, labels) {
    final r = 0x9406 | destRindex(a!);
    return Pass1BytesString(zeroPad(r));
  },
  'MOV': (a, b, byteLoc, labels) {
    final r = 0x2c00 | destRindex(a!) | srcRindex(b!);
    return Pass1BytesString(zeroPad(r));
  },
  'MOVW': (a, b, byteLoc, labels) {
    final r = 0x0100 | ((destRindex(a!) >> 1) & 0xf0) | ((destRindex(b!) >> 5) & 0xf);
    return Pass1BytesString(zeroPad(r));
  },
  'MUL': (a, b, byteLoc, labels) {
    final r = 0x9c00 | destRindex(a!) | srcRindex(b!);
    return Pass1BytesString(zeroPad(r));
  },
  'MULS': (a, b, byteLoc, labels) {
    final r = 0x0200 | (destRindex(a!, 16, 31) & 0xf0) | (srcRindex(b!, 16, 31) & 0xf);
    return Pass1BytesString(zeroPad(r));
  },
  'MULSU': (a, b, byteLoc, labels) {
    final r = 0x0300 | (destRindex(a!, 16, 23) & 0x70) | (srcRindex(b!, 16, 23) & 0x7);
    return Pass1BytesString(zeroPad(r));
  },
  'NEG': (a, b, byteLoc, labels) {
    final r = 0x9401 | destRindex(a!);
    return Pass1BytesString(zeroPad(r));
  },
  'NOP': (a, b, byteLoc, labels) => Pass1BytesString('0000'),
  'OR': (a, b, byteLoc, labels) {
    final r = 0x2800 | destRindex(a!) | srcRindex(b!);
    return Pass1BytesString(zeroPad(r));
  },
  'ORI': (a, b, byteLoc, labels) {
    int r = 0x6000 | (destRindex(a!, 16, 31) & 0xf0);
    final k = constValue(b!);
    r |= ((k & 0xf0) << 4) | (k & 0xf);
    return Pass1BytesString(zeroPad(r));
  },
  'OUT': (a, b, byteLoc, labels) {
    int r = 0xb800 | destRindex(b!);
    final A = constValue(a!, 0, 63);
    r |= ((A & 0x30) << 5) | (A & 0x0f);
    return Pass1BytesString(zeroPad(r));
  },
  'POP': (a, b, byteLoc, labels) {
    final r = 0x900f | destRindex(a!);
    return Pass1BytesString(zeroPad(r));
  },
  'PUSH': (a, b, byteLoc, labels) {
    final r = 0x920f | destRindex(a!);
    return Pass1BytesString(zeroPad(r));
  },
  'RCALL': (a, b, byteLoc, labels) {
    final k = constOrLabel(a!, labels, byteLoc + 2);
    if (k.isNaN) {
      return Pass1BytesFunction((l) {
        return (OPTABLE['RCALL']!(a, b, byteLoc, l) as Pass1BytesString).value;
      });
    }
    final r = 0xd000 | fitTwoC(constValue(k.toInt() >> 1, -2048, 2047), 12);
    return Pass1BytesString(zeroPad(r));
  },
  'RET': (a, b, byteLoc, labels) => Pass1BytesString('9508'),
  'RETI': (a, b, byteLoc, labels) => Pass1BytesString('9518'),
  'RJMP': (a, b, byteLoc, labels) {
    final k = constOrLabel(a!, labels, byteLoc + 2);
    if (k.isNaN) {
      return Pass1BytesFunction((l) {
        return (OPTABLE['RJMP']!(a, b, byteLoc, l) as Pass1BytesString).value;
      });
    }
    final r = 0xc000 | fitTwoC(constValue(k.toInt() >> 1, -2048, 2047), 12);
    return Pass1BytesString(zeroPad(r));
  },
  'ROL': (a, b, byteLoc, labels) => OPTABLE['ADC']!(a, a, byteLoc, labels),
  'ROR': (a, b, byteLoc, labels) {
    final r = 0x9407 | destRindex(a!);
    return Pass1BytesString(zeroPad(r));
  },
  'SBC': (a, b, byteLoc, labels) {
    final r = 0x0800 | destRindex(a!) | srcRindex(b!);
    return Pass1BytesString(zeroPad(r));
  },
  'SBCI': (a, b, byteLoc, labels) {
    int r = 0x4000 | (destRindex(a!, 16, 31) & 0xf0);
    final k = constValue(b!);
    r |= ((k & 0xf0) << 4) | (k & 0x0f);
    return Pass1BytesString(zeroPad(r));
  },
  'SBI': (a, b, byteLoc, labels) {
    final r = 0x9a00 | (constValue(a!, 0, 31) << 3) | constValue(b!, 0, 7);
    return Pass1BytesString(zeroPad(r));
  },
  'SBIC': (a, b, byteLoc, labels) {
    final r = 0x9900 | (constValue(a!, 0, 31) << 3) | constValue(b!, 0, 7);
    return Pass1BytesString(zeroPad(r));
  },
  'SBIS': (a, b, byteLoc, labels) {
    final r = 0x9b00 | (constValue(a!, 0, 31) << 3) | constValue(b!, 0, 7);
    return Pass1BytesString(zeroPad(r));
  },
  'SBIW': (a, b, byteLoc, labels) {
    int r = 0x9700;
    final dm = RegExp(r'[Rr](24|26|28|30)').firstMatch(a!);
    if (dm == null) throw 'Rd must be 24, 26, 28, or 30';
    int d = int.parse(dm.group(1)!);
    d = (d - 24) ~/ 2;
    r |= (d & 0x3) << 4;
    final k = constValue(b!, 0, 63);
    r |= ((k & 0x30) << 2) | (k & 0x0f);
    return Pass1BytesString(zeroPad(r));
  },
  'SBR': (a, b, byteLoc, labels) {
    int r = 0x6000 | (destRindex(a!, 16, 31) & 0xf0);
    final k = constValue(b!);
    r |= ((k & 0xf0) << 4) | (k & 0x0f);
    return Pass1BytesString(zeroPad(r));
  },
  'SBRC': (a, b, byteLoc, labels) {
    final r = 0xfc00 | destRindex(a!) | constValue(b!, 0, 7);
    return Pass1BytesString(zeroPad(r));
  },
  'SBRS': (a, b, byteLoc, labels) {
    final r = 0xfe00 | destRindex(a!) | constValue(b!, 0, 7);
    return Pass1BytesString(zeroPad(r));
  },
  'SEC': (a, b, byteLoc, labels) => SEflag(0),
  'SEH': (a, b, byteLoc, labels) => SEflag(5),
  'SEI': (a, b, byteLoc, labels) => SEflag(7),
  'SEN': (a, b, byteLoc, labels) => SEflag(2),
  'SER': (a, b, byteLoc, labels) {
    final r = 0xef0f | (destRindex(a!, 16, 31) & 0xf0);
    return Pass1BytesString(zeroPad(r));
  },
  'SES': (a, b, byteLoc, labels) => SEflag(4),
  'SET': (a, b, byteLoc, labels) => SEflag(6),
  'SEV': (a, b, byteLoc, labels) => SEflag(3),
  'SEZ': (a, b, byteLoc, labels) => SEflag(1),
  'SLEEP': (a, b, byteLoc, labels) => Pass1BytesString('9588'),
  'SPM': (a, b, byteLoc, labels) {
    if (a == null || a.isEmpty) return Pass1BytesString('95e8');
    if (a != 'Z+') throw 'Bad param to SPM';
    return Pass1BytesString('95f8');
  },
  'ST': (a, b, byteLoc, labels) {
    final r = 0x0200 | destRindex(b!) | stldXYZ(a!);
    return Pass1BytesString(zeroPad(r));
  },
  'STD': (a, b, byteLoc, labels) {
    final r = 0x0200 | destRindex(b!) | stldYZq(a!);
    return Pass1BytesString(zeroPad(r));
  },
  'STS': (a, b, byteLoc, labels) {
    final k = constValue(a!, 0, 65535);
    final r = 0x9200 | destRindex(b!);
    return Pass1BytesList([zeroPad(r), zeroPad(k)]);
  },
  'SUB': (a, b, byteLoc, labels) {
    final r = 0x1800 | destRindex(a!) | srcRindex(b!);
    return Pass1BytesString(zeroPad(r));
  },
  'SUBI': (a, b, byteLoc, labels) {
    int r = 0x5000 | (destRindex(a!, 16, 31) & 0xf0);
    final k = constValue(b!);
    r |= ((k & 0xf0) << 4) | (k & 0xf);
    return Pass1BytesString(zeroPad(r));
  },
  'SWAP': (a, b, byteLoc, labels) {
    final r = 0x9402 | destRindex(a!);
    return Pass1BytesString(zeroPad(r));
  },
  'TST': (a, b, byteLoc, labels) => OPTABLE['AND']!(a, a, byteLoc, labels),
  'WDR': (a, b, byteLoc, labels) => Pass1BytesString('95a8'),
  'XCH': (a, b, byteLoc, labels) {
    final r = 0x9204 | destRindex(b!);
    if (a != 'Z') throw 'Bad param, not Z';
    return Pass1BytesString(zeroPad(r));
  },
};

class AssembleResult {
  final Map<String, int> labels;
  final List<String> errors;
  final List<LineTable> lines;
  final Uint8List? bytes;
  
  AssembleResult({required this.labels, required this.errors, required this.lines, this.bytes});
}

class PassOneResult {
  final Map<String, int> labels;
  final List<String> errors;
  final List<LineTablePass1> lines;

  PassOneResult({required this.labels, required this.errors, required this.lines});
}

PassOneResult passOne(String inputdata) {
  final lines = inputdata.split('\n');
  final commentReg = RegExp(r'[#;].*$');
  final labelReg = RegExp(r'^(\w+):');
  final codeReg = RegExp(r'^\s*(\w+)(?:\s+([^,]+)(?:,\s*(\S+))?)?\s*$');

  int byteOffset = 0;
  final labelTable = <String, int>{};
  final replacements = <String, String>{};
  final errorTable = <String>[];
  final lineTable = <LineTablePass1>[];

  for (int idx = 0; idx < lines.length; idx++) {
    String res = lines[idx].trim();
    if (res.isEmpty) continue;

    final lt = LineTablePass1(line: idx + 1, text: res, bytes: Pass1BytesList([]), byteOffset: 0);
    res = res.replaceAll(commentReg, '').trim();
    if (res.isEmpty) continue;

    final labelMatch = labelReg.firstMatch(res);
    if (labelMatch != null) {
      labelTable[labelMatch.group(1)!] = byteOffset;
      res = res.replaceFirst(labelReg, '').trim();
    }
    if (res.isEmpty) continue;

    final resMatch = codeReg.firstMatch(res);
    try {
      if (resMatch == null) {
        throw "doesn't match as code!";
      }

      final instructionStr = resMatch.group(1);
      if (instructionStr == null || instructionStr.isEmpty) {
        throw 'Empty mnemonic field!';
      }

      final instruction = instructionStr.toUpperCase().trim();
      
      String? arg1 = resMatch.group(2);
      String? arg2 = resMatch.group(3);

      switch (instruction) {
        case '_REPLACE':
          if (arg1 != null && arg2 != null) {
             replacements[arg1] = arg2;
          }
          continue;
        case '_LOC':
          final num = int.tryParse(arg1 ?? '');
          if (num == null) throw 'Location is not a number.';
          if ((num & 0x1) != 0) throw 'Location is odd';
          byteOffset = num;
          continue;
        case '_IW':
          final num = int.tryParse(arg1 ?? '');
          if (num == null) throw 'Immeadiate Word is not a number.';
          lt.bytes = Pass1BytesString(zeroPad(num));
          lt.byteOffset = byteOffset;
          byteOffset += 2;
          lineTable.add(lt);
          continue;
      }

      if (!OPTABLE.containsKey(instruction)) {
        throw 'No such instruction: $instruction';
      }

      if (arg1 != null && replacements.containsKey(arg1)) arg1 = replacements[arg1];
      if (arg2 != null && replacements.containsKey(arg2)) arg2 = replacements[arg2];

      final bytes = OPTABLE[instruction]!(arg1, arg2, byteOffset, labelTable);
      lt.byteOffset = byteOffset;

      if (bytes is Pass1BytesString || bytes is Pass1BytesFunction) {
        byteOffset += 2;
      } else if (bytes is Pass1BytesList) {
        byteOffset += bytes.list.length * 2;
      } else if (bytes is Pass1BytesTuple) {
        byteOffset += 4; // since tuple has 2 strings
      } else {
        throw 'unknown return type from optable.';
      }
      
      lt.bytes = bytes;
      lineTable.add(lt);
    } catch (err) {
      errorTable.add('Line $idx: $err');
    }
  }

  return PassOneResult(labels: labelTable, errors: errorTable, lines: lineTable);
}

int elementSize(LineTablePass1 lt) {
  final b = lt.bytes;
  if (b is Pass1BytesString) {
    return b.value.length ~/ 2;
  } else if (b is Pass1BytesList) {
    return b.list.length * 2;
  } else if (b is Pass1BytesFunction) {
    return 2;
  } else if (b is Pass1BytesTuple) {
    return 4;
  }
  return 0;
}

class PassTwoResult {
  final List<String> errors;
  final Uint8List bytes;
  final List<LineTable> lines;
  final Map<String, int> labels;

  PassTwoResult({required this.errors, required this.bytes, required this.lines, required this.labels});
}

PassTwoResult passTwo(List<LineTablePass1> lineTable, Map<String, int> labels) {
  final errorTable = <String>[];
  final lastElement = lineTable.isNotEmpty ? lineTable.last : null;
  final byteSize = lastElement != null ? lastElement.byteOffset + elementSize(lastElement) : 0;
  final resultTable = Uint8List(byteSize);
  final finalLines = <LineTable>[];

  for (final ltEntry in lineTable) {
    try {
      dynamic resolvedBytes;
      if (ltEntry.bytes is Pass1BytesFunction) {
        resolvedBytes = (ltEntry.bytes as Pass1BytesFunction).func(labels);
      } else if (ltEntry.bytes is Pass1BytesTuple) {
        resolvedBytes = (ltEntry.bytes as Pass1BytesTuple).func(labels);
      } else if (ltEntry.bytes is Pass1BytesList) {
        resolvedBytes = (ltEntry.bytes as Pass1BytesList).list;
      } else if (ltEntry.bytes is Pass1BytesString) {
        resolvedBytes = (ltEntry.bytes as Pass1BytesString).value;
      }

      if (resolvedBytes is String) {
        resultTable[ltEntry.byteOffset + 1] = int.parse(resolvedBytes.substring(0, 2), radix: 16);
        resultTable[ltEntry.byteOffset] = int.parse(resolvedBytes.substring(2, 4), radix: 16);
      } else if (resolvedBytes is List<String>) {
        if (resolvedBytes.isEmpty) throw 'Empty array in lineTable.';
        int bi = ltEntry.byteOffset;
        for (int j = 0; j < resolvedBytes.length; j++, bi += 2) {
          final value = resolvedBytes[j];
          resultTable[bi + 1] = int.parse(value.substring(0, 2), radix: 16);
          resultTable[bi] = int.parse(value.substring(2, 4), radix: 16);
        }
      } else {
        throw 'unknown return type from optable.';
      }

      finalLines.add(LineTable(
        line: ltEntry.line,
        bytes: resolvedBytes,
        text: ltEntry.text,
        byteOffset: ltEntry.byteOffset,
      ));
    } catch (err) {
      errorTable.add('Line: ${ltEntry.line}: $err');
    }
  }

  return PassTwoResult(errors: errorTable, bytes: resultTable, lines: finalLines, labels: labels);
}

class AssembleOutput {
  final Uint8List bytes;
  final List<String> errors;
  final List<LineTable> lines;
  final Map<String, int> labels;

  AssembleOutput({required this.bytes, required this.errors, required this.lines, required this.labels});
}

AssembleOutput assemble(String input) {
  final mid = passOne(input);
  if (mid.errors.isNotEmpty) {
    return AssembleOutput(
      bytes: Uint8List(0),
      errors: mid.errors,
      lines: [],
      labels: {},
    );
  }
  final res = passTwo(mid.lines, mid.labels);
  return AssembleOutput(
    bytes: res.bytes,
    errors: res.errors,
    lines: res.lines,
    labels: res.labels,
  );
}

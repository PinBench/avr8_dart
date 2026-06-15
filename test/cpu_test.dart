import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:avr8_dart/src/cpu/cpu.dart';

void main() {
  group('cpu', () {
    test('should set initial value of SP to the last byte of internal SRAM', () {
      final cpu = CPU(Uint16List(1024), sramBytes: 0x1000);
      expect(cpu.SP, equals(0x10ff));
    });

    group('events', () {
      test('should execute queued events after the given number of cycles has passed', () {
        final cpu = CPU(Uint16List(1024), sramBytes: 0x1000);
        final events = <List<int>>[];
        for (final i in [1, 4, 10]) {
          cpu.addClockEvent(() => events.add([i, cpu.cycles]), i);
        }
        for (var i = 0; i < 10; i++) {
          cpu.cycles++;
          cpu.tick();
        }
        expect(events, equals([
          [1, 1],
          [4, 4],
          [10, 10],
        ]));
      });

      test('should correctly sort the events when added in reverse order', () {
        final cpu = CPU(Uint16List(1024), sramBytes: 0x1000);
        final events = <List<int>>[];
        for (final i in [10, 4, 1]) {
          cpu.addClockEvent(() => events.add([i, cpu.cycles]), i);
        }
        for (var i = 0; i < 10; i++) {
          cpu.cycles++;
          cpu.tick();
        }
        expect(events, equals([
          [1, 1],
          [4, 4],
          [10, 10],
        ]));
      });

      group('updateClockEvent', () {
        test('should update the number of cycles for the given clock event', () {
          final cpu = CPU(Uint16List(1024), sramBytes: 0x1000);
          final events = <List<int>>[];
          final callbacks = <int, AVRClockEventCallback>{};
          for (final i in [1, 4, 10]) {
            AVRClockEventCallback cb = () => events.add([i, cpu.cycles]);
            cpu.addClockEvent(cb, i);
            callbacks[i] = cb;
          }
          cpu.updateClockEvent(callbacks[4]!, 2);
          cpu.updateClockEvent(callbacks[1]!, 12);
          for (var i = 0; i < 14; i++) {
            cpu.cycles++;
            cpu.tick();
          }
          expect(events, equals([
            [4, 2],
            [10, 10],
            [1, 12],
          ]));
        });

        group('clearClockEvent', () {
          test('should remove the given clock event', () {
            final cpu = CPU(Uint16List(1024), sramBytes: 0x1000);
            final events = <List<int>>[];
            final callbacks = <int, AVRClockEventCallback>{};
            for (final i in [1, 4, 10]) {
              AVRClockEventCallback cb = () => events.add([i, cpu.cycles]);
              cpu.addClockEvent(cb, i);
              callbacks[i] = cb;
            }
            cpu.clearClockEvent(callbacks[4]!);
            for (var i = 0; i < 10; i++) {
              cpu.cycles++;
              cpu.tick();
            }
            expect(events, equals([
              [1, 1],
              [10, 10],
            ]));
          });

          test('should return false if the provided clock event is not scheduled', () {
            final cpu = CPU(Uint16List(1024), sramBytes: 0x1000);
            AVRClockEventCallback event4 = () {};
            cpu.addClockEvent(event4, 4);
            AVRClockEventCallback event10 = () {};
            cpu.addClockEvent(event10, 10);
            cpu.addClockEvent(() {}, 1);

            // Both events should be successfully removed
            expect(cpu.clearClockEvent(event4), isTrue);
            expect(cpu.clearClockEvent(event10), isTrue);
            // And now we should get false, as these events have already been removed
            expect(cpu.clearClockEvent(event4), isFalse);
            expect(cpu.clearClockEvent(event10), isFalse);
          });
        });
      });
    });
  });
}

// The Windows calls behind serial ports; elsewhere these are skipped.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tildeck/ssh/serial.dart';
import 'package:tildeck/ssh/ssh_connector.dart';

void main() {
  final skip = Platform.isWindows ? null : 'Windows only';

  test('the ports are listed by name, in number order', () {
    final ports = serialPortNames();
    for (final p in ports) {
      expect(p, matches(RegExp(r'^COM\d+$')));
    }
    final numbers = [for (final p in ports) int.parse(p.substring(3))];
    expect(numbers, [...numbers]..sort());
  }, skip: skip);

  test('a port that does not exist will not open', () {
    expect(
      () => openSerialPort('COM250', 115200),
      throwsA(isA<ConnectException>().having((e) => e.problem, 'problem', ConnectProblem.serialFailed)),
    );
  }, skip: skip);
}

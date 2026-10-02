import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_libserialport/flutter_libserialport.dart';

import 'ssh_connector.dart';

/// An open serial line: what a serial terminal reads and writes.
class SerialLine {
  const SerialLine({required this.output, required this.write, required this.done, required this.close});

  final Stream<Uint8List> output;
  final void Function(Uint8List data) write;

  /// Completes when the line ends: closed, or the device went away.
  final Future<void> done;
  final void Function() close;
}

/// Opens a serial port by name at a baud rate.
typedef SerialOpener = SerialLine Function(String port, int baudRate);

/// The serial ports on this computer, by name; none where they cannot be
/// listed.
List<String> serialPortNames() {
  try {
    return SerialPort.availablePorts;
  } catch (_) {
    return const [];
  }
}

/// Opens [name] at [baudRate] with 8 data bits, no parity, one stop bit and
/// no flow control, the settings nearly every console uses.
SerialLine openSerialPort(String name, int baudRate) {
  final SerialPort port;
  try {
    port = SerialPort(name);
  } catch (_) {
    throw const ConnectException(ConnectProblem.serialFailed);
  }
  try {
    if (!port.openReadWrite()) throw const ConnectException(ConnectProblem.serialFailed);
    final config = SerialPortConfig()
      ..baudRate = baudRate
      ..bits = 8
      ..parity = SerialPortParity.none
      ..stopBits = 1
      ..setFlowControl(SerialPortFlowControl.none);
    port.config = config;
    config.dispose();
  } catch (_) {
    port.close();
    port.dispose();
    throw const ConnectException(ConnectProblem.serialFailed);
  }

  final reader = SerialPortReader(port);
  final done = Completer<void>();
  void close() {
    if (done.isCompleted) return;
    done.complete();
    reader.close();
    port.close();
    // The reader's isolate may still be waiting on the port: free it after.
    Timer(const Duration(seconds: 2), port.dispose);
  }

  return SerialLine(
    // A read error means the device is gone.
    output: reader.stream.handleError((Object _) => close()),
    write: (data) {
      if (done.isCompleted) return;
      try {
        port.write(data, timeout: 2000);
      } catch (_) {
        close();
      }
    },
    done: done.future,
    close: close,
  );
}

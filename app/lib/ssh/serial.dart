import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';

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

/// Serial ports open on Windows, the desktop Tildeck ships on; tests turn
/// the choice on elsewhere.
bool serialSupported = !kIsWeb && Platform.isWindows;

/// The serial ports on this computer (COM1, COM3), in order; none where they
/// cannot be listed.
List<String> serialPortNames() {
  if (!Platform.isWindows) return const [];
  try {
    return _Kernel32().comPorts();
  } catch (_) {
    return const [];
  }
}

/// Opens [name] at [baudRate] with 8 data bits, no parity, one stop bit and
/// no flow control, the settings nearly every console uses.
SerialLine openSerialPort(String name, int baudRate) {
  if (!Platform.isWindows) throw const ConnectException(ConnectProblem.serialFailed);
  final kernel = _Kernel32();
  final handle = kernel.open(name, baudRate);
  if (handle == null) throw const ConnectException(ConnectProblem.serialFailed);

  final output = StreamController<Uint8List>();
  final done = Completer<void>();
  final fromWorker = ReceivePort();
  final exited = ReceivePort();
  // What is sent before the worker is ready waits for it.
  SendPort? worker;
  final pending = <Object>[];
  void send(Object message) => worker == null ? pending.add(message) : worker!.send(message);
  var closing = false;

  fromWorker.listen((message) {
    switch (message) {
      case SendPort port:
        worker = port;
        pending.forEach(port.send);
        pending.clear();
      case Uint8List data:
        output.add(data);
    }
  });
  // The handle is closed only once the worker, its only user, has ended.
  exited.listen((_) {
    fromWorker.close();
    exited.close();
    kernel.close(handle);
    output.close();
    if (!done.isCompleted) done.complete();
  });
  Isolate.spawn(
    _serialWorker,
    (handle, fromWorker.sendPort),
    onExit: exited.sendPort,
    debugName: 'serial $name',
  ).then<void>((_) {}, onError: (Object _) => exited.sendPort.send(null));

  return SerialLine(
    output: output.stream,
    write: (data) {
      if (!closing) send(data);
    },
    done: done.future,
    close: () {
      if (closing) return;
      closing = true;
      send(false);
    },
  );
}

/// Owns the open port: writes what it is sent and reads what arrives, in
/// turn, until told to stop (false) or the device goes away.
Future<void> _serialWorker((int, SendPort) args) async {
  final (handle, out) = args;
  final kernel = _Kernel32();
  final inbox = ReceivePort();
  out.send(inbox.sendPort);
  final writes = <Uint8List>[];
  var stop = false;
  inbox.listen((message) {
    if (message is Uint8List) {
      writes.add(message);
    } else {
      stop = true;
    }
  });
  final buffer = calloc<Uint8>(4096);
  final count = calloc<Uint32>();
  try {
    while (!stop) {
      while (writes.isNotEmpty && !stop) {
        if (!kernel.writeAll(handle, writes.removeAt(0))) stop = true;
      }
      if (stop) break;
      // Returns after at most the read timeout, with or without data.
      if (!kernel.read(handle, buffer, 4096, count)) break;
      if (count.value > 0) out.send(Uint8List.fromList(buffer.asTypedList(count.value)));
      // Let the inbox take what was typed meanwhile.
      await Future<void>.delayed(Duration.zero);
    }
  } finally {
    calloc
      ..free(buffer)
      ..free(count);
    inbox.close();
  }
}

/// The few Windows calls a serial port needs.
class _Kernel32 {
  _Kernel32() : _lib = DynamicLibrary.open('kernel32.dll');

  final DynamicLibrary _lib;

  late final _createFile = _lib
      .lookupFunction<
        IntPtr Function(Pointer<Utf16>, Uint32, Uint32, Pointer<Void>, Uint32, Uint32, IntPtr),
        int Function(Pointer<Utf16>, int, int, Pointer<Void>, int, int, int)
      >('CreateFileW');
  late final _closeHandle = _lib.lookupFunction<Int32 Function(IntPtr), int Function(int)>('CloseHandle');
  late final _getCommState = _lib
      .lookupFunction<Int32 Function(IntPtr, Pointer<Uint8>), int Function(int, Pointer<Uint8>)>('GetCommState');
  late final _setCommState = _lib
      .lookupFunction<Int32 Function(IntPtr, Pointer<Uint8>), int Function(int, Pointer<Uint8>)>('SetCommState');
  late final _setCommTimeouts = _lib
      .lookupFunction<Int32 Function(IntPtr, Pointer<Uint32>), int Function(int, Pointer<Uint32>)>('SetCommTimeouts');
  late final _readFile = _lib
      .lookupFunction<
        Int32 Function(IntPtr, Pointer<Uint8>, Uint32, Pointer<Uint32>, Pointer<Void>),
        int Function(int, Pointer<Uint8>, int, Pointer<Uint32>, Pointer<Void>)
      >('ReadFile');
  late final _writeFile = _lib
      .lookupFunction<
        Int32 Function(IntPtr, Pointer<Uint8>, Uint32, Pointer<Uint32>, Pointer<Void>),
        int Function(int, Pointer<Uint8>, int, Pointer<Uint32>, Pointer<Void>)
      >('WriteFile');
  late final _queryDosDevice = _lib
      .lookupFunction<
        Uint32 Function(Pointer<Utf16>, Pointer<Uint16>, Uint32),
        int Function(Pointer<Utf16>, Pointer<Uint16>, int)
      >('QueryDosDeviceW');

  static const _genericReadWrite = 0xC0000000;
  static const _openExisting = 3;
  static const _invalidHandle = -1;
  static const _maxDword = 0xFFFFFFFF;

  /// Opens and sets up the port, or null when it cannot be.
  int? open(String name, int baudRate) {
    // The device path works for COM10 and above too.
    final path = (r'\\.\' + name).toNativeUtf16();
    final handle = _createFile(path, _genericReadWrite, 0, nullptr, _openExisting, 0, 0);
    calloc.free(path);
    if (handle == _invalidHandle || handle == 0) return null;
    final dcb = calloc<Uint8>(28);
    final timeouts = calloc<Uint32>(5);
    try {
      final bytes = ByteData.sublistView(dcb.asTypedList(28));
      bytes.setUint32(0, 28, Endian.little); // DCBlength
      if (_getCommState(handle, dcb) == 0) throw StateError('GetCommState');
      bytes.setUint32(4, baudRate, Endian.little);
      // fBinary, DTR and RTS on, no flow control, parity, or error handling.
      bytes.setUint32(8, 0x1 | (1 << 4) | (1 << 12), Endian.little);
      bytes.setUint8(18, 8); // ByteSize
      bytes.setUint8(19, 0); // NOPARITY
      bytes.setUint8(20, 0); // ONESTOPBIT
      if (_setCommState(handle, dcb) == 0) throw StateError('SetCommState');
      // A read returns as soon as bytes arrive, or after 50 ms without; a
      // write gives up after two seconds.
      timeouts[0] = _maxDword;
      timeouts[1] = _maxDword;
      timeouts[2] = 50;
      timeouts[3] = 0;
      timeouts[4] = 2000;
      if (_setCommTimeouts(handle, timeouts) == 0) throw StateError('SetCommTimeouts');
      return handle;
    } catch (_) {
      _closeHandle(handle);
      return null;
    } finally {
      calloc
        ..free(dcb)
        ..free(timeouts);
    }
  }

  void close(int handle) => _closeHandle(handle);

  bool read(int handle, Pointer<Uint8> buffer, int size, Pointer<Uint32> count) =>
      _readFile(handle, buffer, size, count, nullptr) != 0;

  bool writeAll(int handle, Uint8List data) {
    final buffer = calloc<Uint8>(data.length);
    final written = calloc<Uint32>();
    try {
      buffer.asTypedList(data.length).setAll(0, data);
      var offset = 0;
      while (offset < data.length) {
        if (_writeFile(handle, buffer + offset, data.length - offset, written, nullptr) == 0) return false;
        if (written.value == 0) return false;
        offset += written.value;
      }
      return true;
    } finally {
      calloc
        ..free(buffer)
        ..free(written);
    }
  }

  /// The COM devices Windows knows, by number.
  List<String> comPorts() {
    for (var size = 1 << 16; size <= 1 << 22; size <<= 2) {
      final buffer = calloc<Uint16>(size);
      try {
        final length = _queryDosDevice(nullptr, buffer, size);
        if (length == 0) continue; // Too small: try a larger one.
        final names = String.fromCharCodes(buffer.asTypedList(length)).split('\u0000');
        final ports = [
          for (final n in names)
            if (RegExp(r'^COM\d+$').hasMatch(n)) n,
        ]..sort((a, b) => int.parse(a.substring(3)).compareTo(int.parse(b.substring(3))));
        return ports;
      } finally {
        calloc.free(buffer);
      }
    }
    return const [];
  }
}

// The terminal's keyboard connection must name the view it belongs to.
// Flutter's Windows embedder (3.44 and later) rejects TextInput.setClient
// without a viewId ("Could not set client, view ID is null"), and the
// terminal then drops every typed character: the test binding accepts the
// call either way, so the configuration itself is checked here.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xterm/xterm.dart';

void main() {
  testWidgets('the terminal attaches its keyboard input with the view id', (tester) async {
    int? sentViewId;
    var setClientCalled = false;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.textInput, (call) async {
      if (call.method == 'TextInput.setClient') {
        setClientCalled = true;
        sentViewId = ((call.arguments as List).last as Map)['viewId'] as int?;
      }
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.textInput, null));

    await tester.pumpWidget(MaterialApp(home: TerminalView(Terminal(), autofocus: true)));
    await tester.tap(find.byType(TerminalView));
    await tester.pump(const Duration(seconds: 1));

    expect(setClientCalled, isTrue, reason: 'focusing the terminal opens a text input connection');
    expect(sentViewId, tester.view.viewId);
  });
}

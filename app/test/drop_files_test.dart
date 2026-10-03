import 'package:flutter_test/flutter_test.dart';
import 'package:tildeck/ui/drop_files.dart';

void main() {
  test('dropped paths are typed as a terminal types them', () {
    expect(droppedPathsInput([r'C:\work\a.txt', r'C:\My Files\b.txt']), r'C:\work\a.txt "C:\My Files\b.txt" ');
  });
}

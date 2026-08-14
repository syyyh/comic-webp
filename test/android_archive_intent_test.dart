import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android advertises ZIP and CBZ open/share support', () async {
    final manifest = await File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsString();

    expect(manifest, contains('android.intent.action.VIEW'));
    expect(manifest, contains('android.intent.action.SEND'));
    expect(manifest, contains('android.intent.category.DEFAULT'));
    expect(manifest, contains('application/zip'));
    expect(manifest, contains('application/x-cbz'));
    expect(manifest, contains('application/vnd.comicbook+zip'));
  });
}

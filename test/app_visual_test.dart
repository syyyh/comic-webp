import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:panelly/app.dart';
import 'package:panelly/app_controller.dart';

void main() {
  testWidgets('empty library fits a phone viewport', (tester) async {
    await _setPhoneViewport(tester);
    await tester.pumpWidget(PanellyApp(controller: AppController()));
    await tester.pumpAndSettle();

    expect(find.text('把漫画交给漫匣'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/empty_library.png'),
    );
  });

  testWidgets('settings fits a phone viewport', (tester) async {
    await _setPhoneViewport(tester);
    await tester.pumpWidget(PanellyApp(controller: AppController()));
    await tester.tap(find.text('设置'));
    await tester.pumpAndSettle();

    expect(find.text('深色模式'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/settings.png'),
    );
  });
}

Future<void> _setPhoneViewport(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(390, 844));
  addTearDown(() => tester.binding.setSurfaceSize(null));
}

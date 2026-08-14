import 'dart:collection';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:panelly/services/incoming_archive_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('panelly.test/incoming_archives');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() async {
    messenger.setMockMethodCallHandler(channel, null);
  });

  test('drains an archive queued before Flutter starts', () async {
    final platformEvents = Queue<Map<String, String>>.from(
      <Map<String, String>>[
        <String, String>{'type': 'archive', 'value': r'C:\cache\comic.cbz'},
      ],
    );
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'consumeIncomingArchiveEvent');
      return platformEvents.isEmpty ? null : platformEvents.removeFirst();
    });
    final service = IncomingArchiveService(channel: channel);
    final received = <IncomingArchiveEvent>[];
    final subscription = service.events.listen(received.add);

    await service.start();

    expect(received, hasLength(1));
    expect(
      (received.single as IncomingArchiveReady).path,
      endsWith('comic.cbz'),
    );
    await subscription.cancel();
    await service.dispose();
  });

  test('drains an archive that arrives while Flutter is running', () async {
    final platformEvents = Queue<Map<String, String>>();
    messenger.setMockMethodCallHandler(channel, (call) async {
      return platformEvents.isEmpty ? null : platformEvents.removeFirst();
    });
    final service = IncomingArchiveService(channel: channel);
    final eventFuture = service.events.first;
    await service.start();

    platformEvents.add(<String, String>{
      'type': 'archive',
      'value': r'C:\cache\shared.zip',
    });
    await messenger.handlePlatformMessage(
      channel.name,
      const StandardMethodCodec().encodeMethodCall(
        const MethodCall('incomingArchiveEvent'),
      ),
      (_) {},
    );

    final event = await eventFuture;
    expect(event, isA<IncomingArchiveReady>());
    expect((event as IncomingArchiveReady).path, endsWith('shared.zip'));
    await service.dispose();
  });

  test('forwards native copy failures to the UI layer', () async {
    final platformEvents = Queue<Map<String, String>>.from(
      <Map<String, String>>[
        <String, String>{'type': 'error', 'value': '没有读取权限'},
      ],
    );
    messenger.setMockMethodCallHandler(channel, (call) async {
      return platformEvents.isEmpty ? null : platformEvents.removeFirst();
    });
    final service = IncomingArchiveService(channel: channel);
    final eventFuture = service.events.first;

    await service.start();

    final event = await eventFuture;
    expect(event, isA<IncomingArchiveFailure>());
    expect((event as IncomingArchiveFailure).message, '没有读取权限');
    await service.dispose();
  });
}

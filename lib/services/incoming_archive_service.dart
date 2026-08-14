import 'dart:async';

import 'package:flutter/services.dart';

sealed class IncomingArchiveEvent {
  const IncomingArchiveEvent();
}

final class IncomingArchiveReady extends IncomingArchiveEvent {
  const IncomingArchiveReady(this.path);

  final String path;
}

final class IncomingArchiveFailure extends IncomingArchiveEvent {
  const IncomingArchiveFailure(this.message);

  final String message;
}

abstract interface class IncomingArchiveSource {
  Stream<IncomingArchiveEvent> get events;

  Future<void> start();

  Future<void> dispose();
}

class IncomingArchiveService implements IncomingArchiveSource {
  IncomingArchiveService({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(_channelName);

  static const _channelName = 'com.shanhai.panelly/incoming_archives';

  final MethodChannel _channel;
  final _events = StreamController<IncomingArchiveEvent>.broadcast();
  bool _started = false;
  bool _closed = false;
  bool _draining = false;
  bool _drainRequested = false;

  @override
  Stream<IncomingArchiveEvent> get events => _events.stream;

  @override
  Future<void> start() async {
    if (_started || _closed) return;
    _started = true;
    _channel.setMethodCallHandler(_handlePlatformCall);
    await _drainEvents();
  }

  Future<void> _handlePlatformCall(MethodCall call) async {
    if (call.method == 'incomingArchiveEvent') {
      await _drainEvents();
    }
  }

  Future<void> _drainEvents() async {
    if (_closed) return;
    if (_draining) {
      _drainRequested = true;
      return;
    }

    _draining = true;
    try {
      do {
        _drainRequested = false;
        while (!_closed) {
          final event = await _channel.invokeMapMethod<String, dynamic>(
            'consumeIncomingArchiveEvent',
          );
          if (event == null) break;

          final type = event['type'];
          final value = event['value'];
          if (type == 'archive' && value is String && value.isNotEmpty) {
            _events.add(IncomingArchiveReady(value));
          } else if (type == 'error' && value is String && value.isNotEmpty) {
            _events.add(IncomingArchiveFailure(value));
          }
        }
      } while (_drainRequested && !_closed);
    } on MissingPluginException {
      // Widget tests and unsupported platforms do not provide this channel.
    } on PlatformException {
      if (!_closed) {
        _events.add(const IncomingArchiveFailure('无法读取其他应用发送的压缩包'));
      }
    } finally {
      _draining = false;
    }
  }

  @override
  Future<void> dispose() async {
    if (_closed) return;
    _closed = true;
    _channel.setMethodCallHandler(null);
    await _events.close();
  }
}

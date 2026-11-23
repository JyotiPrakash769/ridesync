import 'dart:async';

import 'package:web_socket_channel/web_socket_channel.dart';

class FakeSink implements WebSocketSink {
  final List<dynamic> sent = [];
  bool closed = false;

  @override
  void add(dynamic data) => sent.add(data);

  @override
  Future<void> close([int? closeCode, String? closeReason]) async => closed = true;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Minimal in-memory WebSocketChannel. [fail] makes `ready` throw.
class FakeChannel implements WebSocketChannel {
  FakeChannel({this.fail = false});

  final bool fail;
  final _incoming = StreamController<dynamic>();
  final FakeSink fakeSink = FakeSink();
  int? _closeCode;

  @override
  Future<void> get ready => fail ? Future.error(Exception('connect failed')) : Future.value();

  @override
  Stream<dynamic> get stream => _incoming.stream;

  @override
  WebSocketSink get sink => fakeSink;

  @override
  int? get closeCode => _closeCode;

  @override
  String? get closeReason => null;

  @override
  String? get protocol => null;

  void serverSend(String data) => _incoming.add(data);

  void serverClose([int? code]) {
    _closeCode = code;
    _incoming.close();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

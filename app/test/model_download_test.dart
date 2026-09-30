// Plain tests (no widget binding), so HTTP goes to a real local server.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:quran_ai/asr/engine.dart';
import 'package:quran_ai/asr/on_device_engine.dart';

void main() {
  late HttpServer server;
  late Directory storage;
  final model = List<int>.generate(3 << 20, (i) => i % 251);
  var requests = <String?>[];
  // Bytes to send before dropping the connection, for the next request.
  int? cutAfter;

  setUp(() async {
    requests = [];
    cutAfter = null;
    storage = await Directory.systemTemp.createTemp('models');
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) async {
      requests.add(req.headers.value('range'));
      if (req.uri.path == '/missing.bin') {
        req.response.statusCode = 404;
        await req.response.close();
        return;
      }
      final range = req.headers.value('range');
      final from = range == null ? 0 : int.parse(RegExp(r'bytes=(\d+)-').firstMatch(range)!.group(1)!);
      final body = model.sublist(from);
      final cut = cutAfter;
      cutAfter = null;
      if (cut != null) {
        // Send the headers and part of the file, then drop the connection.
        final socket = await req.response.detachSocket(writeHeaders: false);
        socket.write('HTTP/1.1 ${range == null ? '200 OK' : '206 Partial Content'}\r\n'
            'Content-Length: ${body.length}\r\n\r\n');
        socket.add(body.sublist(0, cut));
        await socket.flush();
        socket.destroy();
        return;
      }
      req.response.statusCode = range == null ? 200 : 206;
      req.response.contentLength = body.length;
      req.response.add(body);
      await req.response.close();
    });
  });

  tearDown(() async {
    await server.close(force: true);
    await storage.delete(recursive: true);
  });

  ModelManager manager(String path) =>
      ModelManager(modelUrl: 'http://127.0.0.1:${server.port}$path', storage: () async => storage);

  test('pressing again while downloading joins the same download', () async {
    final m = manager('/model.bin');
    var downloading = false;
    final first = m.ensure(onProgress: (_) => downloading = m.isDownloading);
    final second = manager('/model.bin').ensure();
    final paths = await Future.wait([first, second]);
    expect(paths[0], paths[1]);
    expect(downloading, isTrue);
    expect(requests, hasLength(1));
    expect(await File(paths[0]).readAsBytes(), model);
    expect(m.isDownloading, isFalse);
    expect(ModelManager.progress.value, isNull);
  });

  test('a downloaded model is never downloaded again', () async {
    final m = manager('/model.bin');
    await m.ensure();
    expect(await m.isDownloaded(), isTrue);
    await m.ensure();
    await manager('/model.bin').ensure();
    expect(requests, hasLength(1));
  });

  test('an interrupted download resumes where it stopped', () async {
    final m = manager('/model.bin');
    cutAfter = 1 << 20;
    await expectLater(
      m.ensure(),
      throwsA(isA<RecognitionException>().having((e) => e.message, 'message', contains('يكمل من حيث توقف'))),
    );
    expect(await m.isDownloaded(), isFalse);
    final path = await m.ensure();
    expect(requests.last, 'bytes=${1 << 20}-');
    expect(await File(path).readAsBytes(), model);
  });

  test('a missing model says so instead of blaming the connection', () async {
    await expectLater(
      manager('/missing.bin').ensure(),
      throwsA(isA<RecognitionException>().having((e) => e.message, 'message', isNot(contains('الإنترنت')))),
    );
  });

  test('progress is reported to every waiting screen', () async {
    final a = <double?>[], b = <double?>[];
    final m = manager('/model.bin');
    await Future.wait([m.ensure(onProgress: a.add), manager('/model.bin').ensure(onProgress: b.add)]);
    expect(a.last, 1.0);
    expect(b.last, 1.0);
  });
}

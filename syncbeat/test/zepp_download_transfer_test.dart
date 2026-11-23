import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:syncbeat/features/audio_sources/public_audio_storage.dart';
import 'package:syncbeat/features/zepp/zepp_client.dart';
import 'package:syncbeat/features/zepp/zepp_download_transfer.dart';

const _file = PublishedAudio(
  'content://media/external/downloads/92',
  'Returned-2.mp3',
);
const _watch = ZeppDevice('Watch', 'AA');
const _other = ZeppDevice('Other', 'BB');

void main() {
  Future<void> send(
    ZeppDownloadTransfer transfer, [
    void Function(ZeppEvent)? onEvent,
  ]) => transfer.send(
    _file,
    title: 'Title & song',
    artist: 'Artist',
    onEvent: onEvent ?? (_) {},
  );

  test(
    'one configured watch: one send using the actual URI and coordination',
    () async {
      final client = _Client();
      final events = <ZeppEvent>[];
      await send(ZeppDownloadTransfer(client: client), events.add);
      expect(client.sends, 1);
      expect(client.filePath, _file.path);
      expect(client.coordinated, isTrue);
      expect(client.selected, _watch.address);
      expect(validateZeppMetadata(client.title!, required: true), isNull);
      expect(events.last.text, contains('Invio completato'));
      expect(client.verifications, 0);
    },
  );

  test('ambiguous configured watches never start a transfer', () async {
    final client = _Client()..watches = [_watch, _other];
    await expectLater(
      send(ZeppDownloadTransfer(client: client)),
      throwsA(isA<ZeppDownloadSetupRequired>()),
    );
    expect(client.sends, 0);
  });

  test(
    'a preferred watch is selected; its absence never selects another',
    () async {
      final client = _Client()
        ..watches = [_watch, _other]
        ..preferred = 'BB';
      await send(ZeppDownloadTransfer(client: client));
      expect(client.selected, 'BB');
      client.watches = [_watch];
      await expectLater(
        send(ZeppDownloadTransfer(client: client)),
        throwsA(isA<ZeppDownloadSetupRequired>()),
      );
      expect(client.sends, 1);
    },
  );

  test(
    'pending restore blocks the automatic send and gives manual recovery',
    () async {
      final client = _Client()..pendingRestore = true;
      await expectLater(
        send(ZeppDownloadTransfer(client: client)),
        throwsA(
          isA<ZeppException>().having(
            (e) => e.message,
            'message',
            contains('Impostazioni → App → Zepp → Autorizzazioni'),
          ),
        ),
      );
      expect(client.sends, 0);
    },
  );

  test('failure is reported once with no retry or success message', () async {
    final client = _Client()..fail = true;
    final events = <ZeppEvent>[];
    await expectLater(
      send(ZeppDownloadTransfer(client: client), events.add),
      throwsA(isA<ZeppException>()),
    );
    expect(client.sends, 1);
    expect(
      events.any((e) => e.text?.contains('Invio completato') == true),
      isFalse,
    );
    client.fail = false;
    await send(ZeppDownloadTransfer(client: client));
    expect(client.sends, 2, reason: 'A new explicit gesture may try once');
  });

  test(
    'cancelling during preparation prevents the later native send',
    () async {
      final client = _Client()..devicesGate = Completer<List<ZeppDevice>>();
      final transfer = ZeppDownloadTransfer(client: client);
      final preparing = send(transfer);
      await Future<void>.delayed(Duration.zero);
      await transfer.cancel();
      client.devicesGate!.complete([_watch]);
      await expectLater(preparing, throwsA(isA<ZeppException>()));
      expect(client.sends, 0);
      expect(
        client.cancels,
        0,
        reason: 'No unrelated native operation is cancelled',
      );
    },
  );

  test(
    'parallel downloads do not queue sends; cancellation reaches active send',
    () async {
      final client = _Client()..sendGate = Completer<void>();
      final transfer = ZeppDownloadTransfer(client: client);
      final active = send(transfer);
      await Future<void>.delayed(Duration.zero);
      expect(client.sends, 1);
      await expectLater(
        send(ZeppDownloadTransfer(client: _Client())),
        throwsA(isA<ZeppException>()),
      );
      await transfer.cancel();
      expect(client.cancels, 1);
      client.sendGate!.completeError(const ZeppException('Annullato'));
      await expectLater(active, throwsA(isA<ZeppException>()));
      expect(client.sends, 1);
    },
  );
}

class _Client extends ZeppClient {
  List<ZeppDevice> watches = [_watch];
  String? preferred;
  bool pendingRestore = false, fail = false;
  int sends = 0, cancels = 0, verifications = 0;
  String? selected, filePath, title;
  bool? coordinated;
  Completer<List<ZeppDevice>>? devicesGate;
  Completer<void>? sendGate;
  @override
  Future<String?> preferredDownloadDevice() async => preferred;
  @override
  Future<List<ZeppDevice>> devices() async =>
      devicesGate == null ? watches : devicesGate!.future;
  @override
  Future<String?> savedKey(ZeppDevice device) async => '0' * 32;
  @override
  Future<Map<String, dynamic>> coordinationStatus() async => {
    'enabled': true,
    'pendingRestore': pendingRestore,
  };
  @override
  Stream<ZeppEvent> get events => const Stream.empty();
  @override
  Future<void> send({
    required ZeppDevice device,
    required String key,
    required String path,
    required String title,
    required String artist,
    bool coordinateZepp = false,
  }) async {
    sends++;
    selected = device.address;
    filePath = path;
    this.title = title;
    coordinated = coordinateZepp;
    if (fail) throw const ZeppException('Invio fallito');
    await sendGate?.future;
  }

  @override
  Future<void> verify({
    required ZeppDevice device,
    required String key,
    bool coordinateZepp = false,
  }) async {
    verifications++;
  }

  @override
  Future<void> cancel() async {
    cancels++;
  }
}

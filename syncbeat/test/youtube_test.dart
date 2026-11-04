import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:syncbeat/features/audio_sources/audio_source.dart';
import 'package:syncbeat/features/audio_sources/staging_storage.dart';
import 'package:syncbeat/features/audio_sources/youtube_downloader.dart';
import 'package:syncbeat/features/audio_sources/youtube_provider.dart';
import 'package:syncbeat/models/spotify_models.dart';

const track = SpotifyTrack(
  id: 'spotify-one',
  title: 'Blue Sky',
  artists: ['Example Artist'],
  album: '',
  durationMs: 180000,
  isLocal: false,
);
YoutubeVideo video(
  String id, {
  String title = 'Example Artist - Blue Sky (Official Audio)',
  String channel = 'Example Artist',
  int duration = 180,
  bool verified = false,
}) => YoutubeVideo({
  'id': id,
  'title': title,
  'channel': channel,
  'duration': duration,
  'channel_is_verified': verified,
  if (verified) 'artist': 'Example Artist',
});

void main() {
  test('ranks artist/title, duration and verified artist channel', () {
    final ranked = const YoutubeMatcher().rank(track, [
      video(
        'aaaaaaaaaaa',
        title: 'Unrelated',
        channel: 'Someone',
        duration: 300,
      ),
      video('bbbbbbbbbbb', duration: 250),
      video('ccccccccccc'),
      video('ddddddddddd', verified: true),
    ]);
    expect(ranked.map((r) => r.video.id), [
      'ddddddddddd',
      'ccccccccccc',
      'bbbbbbbbbbb',
      'aaaaaaaaaaa',
    ]);
  });
  for (final marker in [
    'cover',
    'live',
    'remix',
    'karaoke',
    'sped-up',
    'slowed',
  ]) {
    test('penalizes $marker except when requested by Spotify title', () {
      final variant = video(
        'aaaaaaaaaaa',
        title: 'Blue Sky $marker Example Artist',
      );
      final regular = const YoutubeMatcher()
          .rank(track, [variant])
          .single
          .score;
      final requested = SpotifyTrack(
        id: 'x',
        title: 'Blue Sky $marker',
        artists: ['Example Artist'],
        album: '',
        durationMs: 180000,
        isLocal: false,
      );
      expect(
        const YoutubeMatcher().rank(requested, [variant]).single.score,
        greaterThan(regular),
      );
    });
  }
  test(
    'verification badge alone does not prove an official artist channel',
    () {
      final v = YoutubeVideo({
        'id': 'aaaaaaaaaaa',
        'title': 'Example Artist - Blue Sky',
        'channel': 'Example Artist',
        'channel_is_verified': true,
      });
      expect(v.isVerifiedChannel, isTrue);
      final unrelatedChannel = YoutubeVideo({
        ...v.metadata,
        'channel': 'Other verified uploader',
      });
      final unverified = YoutubeVideo({
        ...unrelatedChannel.metadata,
        'channel_is_verified': false,
      });
      final ranked = const YoutubeMatcher().rank(track, [
        unrelatedChannel,
      ]).single;
      expect(ranked.video.channelInfo!.oac.name, 'unknown');
      expect(
        ranked.score -
            const YoutubeMatcher().rank(track, [unverified]).single.score,
        closeTo(2, .001),
      );
    },
  );
  test('unknown duration cannot improve a match over a correct duration', () {
    final results = const YoutubeMatcher().rank(track, [
      video('aaaaaaaaaaa', duration: 0),
      video('bbbbbbbbbbb'),
    ]);
    expect(results.first.video.id, 'bbbbbbbbbbb');
  });
  test(
    'ties sort deterministically and unrelated results remain selectable',
    () {
      final results = const YoutubeMatcher().rank(track, [
        video('bbbbbbbbbbb'),
        video('aaaaaaaaaaa'),
        video('ccccccccccc', title: 'Other'),
      ]);
      expect(results.first.video.id, 'aaaaaaaaaaa');
      expect(results.length, 3);
    },
  );
  test(
    'associations survive repository recreation and can be replaced per Spotify ID',
    () async {
      SharedPreferences.setMockInitialValues({});
      await YoutubeAssociations().save(track.id, video('aaaaaaaaaaa'));
      expect((await YoutubeAssociations().read(track.id))!.id, 'aaaaaaaaaaa');
      await YoutubeAssociations().save(track.id, video('bbbbbbbbbbb'));
      expect((await YoutubeAssociations().read(track.id))!.id, 'bbbbbbbbbbb');
      expect(await YoutubeAssociations().read('other'), isNull);
    },
  );
  test(
    'approvals survive reopening, support revocation and reset for another video',
    () async {
      SharedPreferences.setMockInitialValues({});
      final repository = YoutubeAssociations();
      await repository.save(track.id, video('aaaaaaaaaaa'));
      expect(
        YoutubeAssociations.authorizationFor(
          (await repository.read(track.id))!,
        ).valid,
        isFalse,
      );
      await repository.saveAuthorization(
        track.id,
        'aaaaaaaaaaa',
        const YoutubeDownloadAuthorization(
          rightsAndPlatformPermission: true,
          conversionAndOfflineUse: true,
        ),
      );
      await repository.save(track.id, video('aaaaaaaaaaa'));
      expect(
        YoutubeAssociations.authorizationFor(
          (await YoutubeAssociations().read(track.id))!,
        ).valid,
        isTrue,
      );
      await repository.saveAuthorization(
        track.id,
        'aaaaaaaaaaa',
        const YoutubeDownloadAuthorization(
          rightsAndPlatformPermission: false,
          conversionAndOfflineUse: true,
        ),
      );
      expect(
        YoutubeAssociations.authorizationFor(
          (await repository.read(track.id))!,
        ).valid,
        isFalse,
      );
      await repository.save(track.id, video('bbbbbbbbbbb'));
      expect(
        YoutubeAssociations.authorizationFor(
          (await repository.read(track.id))!,
        ).valid,
        isFalse,
      );
      await expectLater(
        repository.saveAuthorization(
          track.id,
          'aaaaaaaaaaa',
          const YoutubeDownloadAuthorization(
            rightsAndPlatformPermission: true,
            conversionAndOfflineUse: true,
          ),
        ),
        throwsA(isA<AudioSourceException>()),
      );
    },
  );

  test(
    'atomic selection saves cannot inherit another video approvals',
    () async {
      SharedPreferences.setMockInitialValues({});
      const approved = YoutubeDownloadAuthorization(
        rightsAndPlatformPermission: true,
        conversionAndOfflineUse: true,
      );
      final first = YoutubeAssociations();
      final second = YoutubeAssociations();
      await Future.wait([
        first.save(track.id, video('aaaaaaaaaaa'), authorization: approved),
        second.save(track.id, video('bbbbbbbbbbb')),
      ]);
      final saved = (await second.read(track.id))!;
      expect(saved.id, 'bbbbbbbbbbb');
      expect(YoutubeAssociations.authorizationFor(saved).valid, isFalse);
      await expectLater(
        first.saveAuthorization(track.id, 'aaaaaaaaaaa', approved),
        throwsA(isA<AudioSourceException>()),
      );
      await second.save(
        track.id,
        video('bbbbbbbbbbb'),
        authorization: approved,
      );
      expect(
        YoutubeAssociations.authorizationFor(
          (await first.read(track.id))!,
        ).valid,
        isTrue,
      );
    },
  );

  test(
    'late approval cannot resurrect a replaced video across repositories',
    () async {
      SharedPreferences.setMockInitialValues({});
      final first = YoutubeAssociations();
      final second = YoutubeAssociations();
      await first.save(track.id, video('aaaaaaaaaaa'));
      final replacement = first.save(track.id, video('bbbbbbbbbbb'));
      final staleApproval = second.saveAuthorization(
        track.id,
        'aaaaaaaaaaa',
        const YoutubeDownloadAuthorization(
          rightsAndPlatformPermission: true,
          conversionAndOfflineUse: true,
        ),
      );
      await expectLater(staleApproval, throwsA(isA<AudioSourceException>()));
      await replacement;
      final saved = (await first.read(track.id))!;
      expect(saved.id, 'bbbbbbbbbbb');
      expect(YoutubeAssociations.authorizationFor(saved).valid, isFalse);
    },
  );

  for (final corrupt in [
    '{',
    '[]',
    '{"id":"aaaaaaaaaaa","title":12}',
    '{"id":true}',
  ]) {
    test('explicit save repairs corrupt selection: $corrupt', () async {
      SharedPreferences.setMockInitialValues({
        YoutubeAssociations.key(track.id): corrupt,
      });
      final repository = YoutubeAssociations();
      await expectLater(
        repository.read(track.id),
        throwsA(isA<AudioSourceException>()),
      );
      await repository.save(track.id, video('bbbbbbbbbbb'));
      final saved = (await repository.read(track.id))!;
      expect(saved.id, 'bbbbbbbbbbb');
      expect(YoutubeAssociations.authorizationFor(saved).valid, isFalse);
    });
  }

  test('corrupt association surfaces a recoverable error', () async {
    SharedPreferences.setMockInitialValues({
      YoutubeAssociations.key(track.id): '{',
    });
    await expectLater(
      YoutubeAssociations().read(track.id),
      throwsA(isA<AudioSourceException>()),
    );
  });
  test('rejects invalid video IDs', () {
    expect(() => YoutubeVideo({'id': '../bad'}), throwsFormatException);
  });
  test(
    'unauthorized download never invokes external tools or storage',
    () async {
      final downloader = YoutubeDownloader(
        tools: const YoutubeTools(executable: 'must-not-run'),
        storage: AppDirectoryStagingStorage(
          applicationDirectory: Directory('must-not-write'),
        ),
      );
      await expectLater(
        downloader.download(
          track: track,
          video: video('aaaaaaaaaaa'),
          authorization: const YoutubeDownloadAuthorization(
            evidence: '',
            rightsAndPlatformPermission: false,
            conversionAndOfflineUse: true,
          ),
          cancellation: DownloadCancellationToken(),
          onProgress: (_) {},
        ),
        throwsA(isA<AudioSourceException>()),
      );
    },
  );
}

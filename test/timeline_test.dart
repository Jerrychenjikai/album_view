import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:album_viewer/loaders/media_probe.dart';
import 'package:album_viewer/models/media_asset.dart';
import 'package:album_viewer/models/media_filter.dart';
import 'package:album_viewer/timeline/day_timeline_layout.dart';
import 'package:album_viewer/timeline/time_resolution.dart';
import 'package:album_viewer/timeline/timeline_metrics.dart';
import 'package:album_viewer/timeline/timeline_viewport.dart';

MediaAsset _asset(String id, DateTime at, {MediaKind kind = MediaKind.image, GpsInfo? gps, String album = 'roll'}) {
  return MediaAsset(
    id: id,
    filePath: '/photos/$album/$id.jpg',
    fileName: '$id.jpg',
    kind: kind,
    createdAt: at,
    albumName: album,
    gps: gps,
    width: 3000,
    height: 2000,
  );
}

void main() {
  test('filter keeps a closed time span, kind, gps and album', () {
    final inside = _asset(
      'a',
      DateTime(2024, 6, 2, 12),
      gps: const GpsInfo(latitude: 43.6, longitude: -79.3),
      album: 'Toronto',
    );
    final tooEarly = _asset('b', DateTime(2024, 5, 1));
    final video = _asset('c', DateTime(2024, 6, 2, 18), kind: MediaKind.video);
    final filter = MediaFilter(
      startInclusive: DateTime(2024, 6, 1),
      endInclusive: DateTime(2024, 6, 30, 23, 59, 59),
      kinds: const {MediaKind.image},
      requireGps: true,
      albumContains: 'tor',
    );
    expect(filter.accepts(inside), isTrue);
    expect(filter.accepts(tooEarly), isFalse);
    expect(filter.accepts(video), isFalse);
    expect(filter.accepts(_asset('d', DateTime(2024, 6, 2), album: 'Home')), isFalse);
  });

  test('one batch per local day, newest print on top', () {
    final assets = [
      _asset('1', DateTime(2024, 3, 2, 9)),
      _asset('2', DateTime(2024, 3, 2, 18)),
      _asset('3', DateTime(2024, 3, 4, 8)),
    ];
    final batches = DayTimelineLayout.arrange(
      assets: assets,
      trackCrossExtent: 800,
      pixelsPerDay: 160,
      topIndex: const {},
    );
    expect(batches.map((batch) => batch.id).toList(), ['2024-03-02', '2024-03-04']);
    expect(batches.first.items.map((item) => item.id).toList(), ['1', '2']);
    expect(batches.first.topItem?.id, '2');
    expect(batches.first.position.dx, lessThan(batches.last.position.dx));
    expect(batches.first.label, '3月2日');
  });

  test('hour, week and multi-year buckets follow the scale', () {
    const track = 800.0;
    final hours = DayTimelineLayout.arrange(
      assets: [
        _asset('a', DateTime(2024, 3, 2, 9, 10)),
        _asset('b', DateTime(2024, 3, 2, 9, 50)),
        _asset('c', DateTime(2024, 3, 2, 15, 1)),
      ],
      trackCrossExtent: track,
      pixelsPerDay: 4000,
      topIndex: const {},
    );
    expect(hours.map((batch) => batch.id).toList(), ['2024-03-02T09', '2024-03-02T15']);
    expect(TimeScale.resolutionFor(4000, track).label, '时');

    final weeks = DayTimelineLayout.arrange(
      assets: [
        _asset('m', DateTime(2024, 3, 4, 9)),
        _asset('w', DateTime(2024, 3, 6, 18)),
        _asset('n', DateTime(2024, 3, 12, 8)),
      ],
      trackCrossExtent: track,
      pixelsPerDay: 10,
      topIndex: const {},
    );
    expect(weeks.length, 2);
    expect(weeks.first.items.map((item) => item.id).toList(), ['m', 'w']);
    expect(TimeScale.resolutionFor(10, track).label, '周');

    expect(TimeScale.resolutionFor(0.02, track).label, '9年');
    final coarse = TimeScale.resolutionFor(0.02, track);
    final bucket = bucketFor(DateTime(2024, 6, 1), coarse);
    expect(bucket.id, 'y9:2016');
    expect(bucket.label, contains('2016'));
    expect(bucket.label, contains('2024'));

    final threeHours = TimeScale.resolutionFor(800, track);
    expect(threeHours.label, '3时');
    final morning = bucketFor(DateTime(2024, 3, 2, 10, 15), threeHours);
    final lateMorning = bucketFor(DateTime(2024, 3, 2, 11, 40), threeHours);
    final afternoon = bucketFor(DateTime(2024, 3, 2, 15, 1), threeHours);
    expect(morning.id, lateMorning.id);
    expect(morning.id, isNot(afternoon.id));

    final threeDays = TimeScale.resolutionFor(40, track);
    expect(threeDays.label, '3日');
    final fortnight = TimeScale.resolutionFor(6.4, track);
    expect(fortnight.label, '2周');
    final quarter = TimeScale.resolutionFor(1.2, track);
    expect(quarter.label, '3月');
    expect(bucketFor(DateTime(2024, 2, 2), quarter).id, bucketFor(DateTime(2024, 3, 20), quarter).id);
    expect(bucketFor(DateTime(2024, 2, 2), quarter).id, isNot(bucketFor(DateTime(2024, 5, 1), quarter).id));
  });

  test('ruler stays sparse when the scale changes', () {
    final day = rulerFor(pixelsPerDay: 168, startDays: 19800, endDays: 19800 + 1000 / 168);
    expect(day.ticks.length, inInclusiveRange(4, 40));
    final year = rulerFor(pixelsPerDay: 0.2, startDays: 19000, endDays: 19000 + 1400 / 0.2);
    expect(year.ticks.length, inInclusiveRange(2, 40));
  });

  test('batches spread across the track and do not overlap at min scale', () {
    final assets = List.generate(36, (index) {
      return _asset('$index', DateTime(2024, 1, 1).add(Duration(days: index)));
    });
    const track = 820.0;
    final ppd = TimelineMetrics.minPixelsPerDay(track);
    final batches = DayTimelineLayout.arrange(
      assets: assets,
      trackCrossExtent: track,
      pixelsPerDay: ppd,
      topIndex: const {},
    );
    final lanes = batches.map((batch) => batch.lane).toSet();
    expect(lanes.length, greaterThan(1));
    for (var i = 0; i < batches.length; i++) {
      for (var j = i + 1; j < batches.length; j++) {
        final a = batches[i];
        final b = batches[j];
        final overlapsX = (a.position.dx - b.position.dx).abs() < TimelineMetrics.footprintWidth;
        final overlapsY = (a.position.dy - b.position.dy).abs() < TimelineMetrics.footprintHeight;
        expect(overlapsX && overlapsY, isFalse, reason: '${a.id} overlaps ${b.id}');
      }
    }
  });

  test('a fresh viewport opens on today, not January 1970', () {
    final viewport = TimelineViewport();
    final today = timeDays(DateTime.now()) * viewport.pixelsPerDay;
    expect((viewport.scrollX - today).abs(), lessThan(1));
    expect(viewport.scrollX, greaterThan(1000));
  });

  test('scroll stops where no further photo would enter', () {
    const ppd = 100.0;
    const width = 500.0;
    const days = [1000.0, 1010.0];
    final earliest = clampTimelineScroll(
      scrollX: -100000,
      pixelsPerDay: ppd,
      viewWidth: width,
      dayMarks: days,
      edgePad: 50,
    );
    final latest = clampTimelineScroll(
      scrollX: 1000000,
      pixelsPerDay: ppd,
      viewWidth: width,
      dayMarks: days,
      edgePad: 50,
    );
    expect(earliest, closeTo(1000 * ppd - 50 - 32, 0.01));
    expect(latest, closeTo(1010 * ppd + 50 - width + 32, 0.01));
    final inside = clampTimelineScroll(
      scrollX: 1000 * ppd,
      pixelsPerDay: ppd,
      viewWidth: width,
      dayMarks: days,
      edgePad: 50,
    );
    expect(inside, 1000 * ppd);
  });

  test('a batch shows only the city that appears most often', () {
    final toronto = const GpsInfo(latitude: 43.6532, longitude: -79.3832);
    final kingston = const GpsInfo(latitude: 44.2312, longitude: -76.4860);
    final addressed = const GpsInfo(
      latitude: 43.65,
      longitude: -79.38,
      city: '120 King St, 多伦多, Ontario, Canada',
    );
    expect(toronto.cityName, '多伦多');
    expect(kingston.cityName, '金斯顿');
    expect(addressed.cityName, '多伦多');
    expect(addressed.label, '多伦多');
    final batches = DayTimelineLayout.arrange(
      assets: [
        _asset('a', DateTime(2024, 3, 2, 9), gps: toronto),
        _asset('b', DateTime(2024, 3, 2, 12), gps: toronto),
        _asset('c', DateTime(2024, 3, 2, 18), gps: kingston),
      ],
      trackCrossExtent: 800,
      pixelsPerDay: 160,
      topIndex: const {},
    );
    expect(batches.single.dominantCity, '多伦多');
  });

  test('zoom keeps the day under the cursor fixed', () {
    final viewport = TimelineViewport(pixelsPerDay: 100, scrollX: 500);
    viewport.zoomAt(focalScreenX: 80, factor: 2, minPixelsPerDay: 10);
    expect(viewport.pixelsPerDay, 200);
    expect(viewport.scrollX, closeTo(5.8 * 200 - 80, 0.001));
  });

  test('jpeg SOF and mp4 mvhd/tkhd are read from headers', () async {
    final jpeg = Uint8List.fromList([
      0xFF, 0xD8, //
      0xFF, 0xC0, //
      0x00, 0x0B, //
      0x08, //
      0x01, 0x00, // height 256
      0x01, 0x80, // width 384
      0x01, 0x01, 0x11, 0x00, //
      0xFF, 0xD9,
    ]);
    final still = await probeHeader(jpeg, '.jpg');
    expect(still.width, 384);
    expect(still.height, 256);

    final video = await probeHeader(_sampleMp4(timescale: 1000, duration: 2500, width: 1920, height: 1080), '.mp4');
    expect(video.duration, const Duration(milliseconds: 2500));
    expect(video.width, 1920);
    expect(video.height, 1080);
  });

  test('gps printable values become signed degrees', () {
    final gps = parseGpsTags('[43, 38, 30]', 'N', '79, 23, 0', 'W', 76);
    expect(gps, isNotNull);
    expect(gps!.latitude, closeTo(43 + 38 / 60 + 30 / 3600, 0.0001));
    expect(gps.longitude, closeTo(-(79 + 23 / 60), 0.0001));
    expect(gps.altitude, 76);
  });
}

Uint8List _sampleMp4({
  required int timescale,
  required int duration,
  required int width,
  required int height,
}) {
  List<int> u32(int value) => [(value >> 24) & 0xFF, (value >> 16) & 0xFF, (value >> 8) & 0xFF, value & 0xFF];
  List<int> box(String type, List<int> content) {
    final size = 8 + content.length;
    return [...u32(size), ...type.codeUnits, ...content];
  }

  final mvhd = box('mvhd', [
    0, 0, 0, 0, // version + flags
    ...u32(0), // creation
    ...u32(0), // modification
    ...u32(timescale),
    ...u32(duration),
  ]);
  final tkhd = box('tkhd', [
    ...u32(width << 16),
    ...u32(height << 16),
  ]);
  final trak = box('trak', tkhd);
  final moov = box('moov', [...mvhd, ...trak]);
  return Uint8List.fromList(moov);
}

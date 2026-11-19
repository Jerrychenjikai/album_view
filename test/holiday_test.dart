import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:album_viewer/models/holiday.dart';
import 'package:album_viewer/models/media_asset.dart';
import 'package:album_viewer/models/media_batch.dart';
import 'package:album_viewer/timeline/time_resolution.dart';
import 'package:album_viewer/ui/batch_stack.dart';
import 'package:album_viewer/ui/holiday_sticker.dart';

MediaAsset _sampleAsset(String id, DateTime at) {
  return MediaAsset(
    id: id,
    filePath: '/photos/$id.jpg',
    fileName: '$id.jpg',
    kind: MediaKind.image,
    createdAt: at,
  );
}

void main() {
  group('Holiday matching and overlap tests', () {
    test('FixedDateHoliday matches calendar dates in local time', () {
      final newYear = HolidayRegistry.findHolidayForDate(DateTime(2024, 1, 1, 10, 30));
      expect(newYear?.id, 'new_year');

      final halloween = HolidayRegistry.findHolidayForDate(DateTime(2024, 10, 31, 23, 59));
      expect(halloween?.id, 'halloween');

      final christmas = HolidayRegistry.findHolidayForDate(DateTime(2024, 12, 25, 0, 1));
      expect(christmas?.id, 'christmas');

      final regularDay = HolidayRegistry.findHolidayForDate(DateTime(2024, 10, 30, 23, 59));
      expect(regularDay, isNull);

      final boxingDay = HolidayRegistry.findHolidayForDate(DateTime(2024, 12, 26, 0, 0));
      expect(boxingDay, isNull);
    });

    test('LunarHoliday matches traditional Chinese holidays across years', () {
      // 2024:
      // 春节: 2024-02-10 (正月初一)
      final spring2024 = HolidayRegistry.findHolidayForDate(DateTime(2024, 2, 10, 9, 0));
      expect(spring2024?.id, 'spring_festival');
      expect(spring2024?.name, '农历春节');

      // 端午: 2024-06-10 (五月初五)
      final dragon2024 = HolidayRegistry.findHolidayForDate(DateTime(2024, 6, 10, 18, 0));
      expect(dragon2024?.id, 'dragon_boat');
      expect(dragon2024?.name, '端午节');

      // 中秋: 2024-09-17 (八月十五)
      final autumn2024 = HolidayRegistry.findHolidayForDate(DateTime(2024, 9, 17, 20, 0));
      expect(autumn2024?.id, 'mid_autumn');
      expect(autumn2024?.name, '中秋节');

      // 2025:
      // 春节: 2025-01-29
      final spring2025 = HolidayRegistry.findHolidayForDate(DateTime(2025, 1, 29, 0, 0));
      expect(spring2025?.id, 'spring_festival');

      // 端午: 2025-05-31
      final dragon2025 = HolidayRegistry.findHolidayForDate(DateTime(2025, 5, 31, 12, 0));
      expect(dragon2025?.id, 'dragon_boat');

      // 中秋: 2025-10-06
      final autumn2025 = HolidayRegistry.findHolidayForDate(DateTime(2025, 10, 6, 21, 30));
      expect(autumn2025?.id, 'mid_autumn');

      // 2026:
      // 春节: 2026-02-17
      final spring2026 = HolidayRegistry.findHolidayForDate(DateTime(2026, 2, 17));
      expect(spring2026?.id, 'spring_festival');

      // Normal days near holidays do not match
      expect(HolidayRegistry.findHolidayForDate(DateTime(2024, 2, 9)), isNull);
      expect(HolidayRegistry.findHolidayForDate(DateTime(2024, 2, 11)), isNull);
      expect(HolidayRegistry.findHolidayForDate(DateTime(2024, 6, 9)), isNull);
      expect(HolidayRegistry.findHolidayForDate(DateTime(2024, 9, 16)), isNull);
    });

    test('LunarHoliday overlapsRange detects ranges covering lunar holidays', () {
      final dragonBoat = HolidayRegistry.holidays.firstWhere((h) => h.id == 'dragon_boat');
      // Week range covering June 10, 2024 (Dragon Boat Festival)
      expect(dragonBoat.overlapsRange(DateTime(2024, 6, 8), DateTime(2024, 6, 15)), isTrue);
      // Week range before Dragon Boat
      expect(dragonBoat.overlapsRange(DateTime(2024, 6, 1), DateTime(2024, 6, 8)), isFalse);

      final midAutumn = HolidayRegistry.holidays.firstWhere((h) => h.id == 'mid_autumn');
      // 3-day range covering Sept 17, 2024 (Mid-Autumn)
      expect(midAutumn.overlapsRange(DateTime(2024, 9, 16), DateTime(2024, 9, 19)), isTrue);
      expect(midAutumn.overlapsRange(DateTime(2024, 9, 18), DateTime(2024, 9, 21)), isFalse);

      final springFestival = HolidayRegistry.holidays.firstWhere((h) => h.id == 'spring_festival');
      // 1-day range covering Jan 29, 2025
      expect(springFestival.overlapsRange(DateTime(2025, 1, 29), DateTime(2025, 1, 30)), isTrue);
    });

    test('Holiday overlapsRange handles single days, intervals and year boundaries', () {
      // Christmas: Dec 25
      final christmas = HolidayRegistry.holidays.firstWhere((h) => h.id == 'christmas');

      // Exact day [2024-12-25 00:00, 2024-12-26 00:00)
      expect(christmas.overlapsRange(DateTime(2024, 12, 25), DateTime(2024, 12, 26)), isTrue);

      // Eve only [2024-12-24 00:00, 2024-12-25 00:00) -> does not overlap Christmas Day
      expect(christmas.overlapsRange(DateTime(2024, 12, 24), DateTime(2024, 12, 25)), isFalse);

      // Day after [2024-12-26 00:00, 2024-12-27 00:00)
      expect(christmas.overlapsRange(DateTime(2024, 12, 26), DateTime(2024, 12, 27)), isFalse);

      // Week spanning Dec 22 to Dec 29
      expect(christmas.overlapsRange(DateTime(2024, 12, 22), DateTime(2024, 12, 29)), isTrue);

      // New Year across year boundary: Dec 29, 2024 to Jan 5, 2025
      final newYear = HolidayRegistry.holidays.firstWhere((h) => h.id == 'new_year');
      expect(newYear.overlapsRange(DateTime(2024, 12, 29), DateTime(2025, 1, 5)), isTrue);

      // Halloween 3-day range: Oct 30 to Nov 2
      final halloween = HolidayRegistry.holidays.firstWhere((h) => h.id == 'halloween');
      expect(halloween.overlapsRange(DateTime(2024, 10, 30), DateTime(2024, 11, 2)), isTrue);
    });
  });

  group('Timeline batch resolution and holiday decoration rules', () {
    test('Shows decoration only when resolution <= 1 week and batch time overlaps holiday', () {
      final christmasBatch = MediaBatch(
        id: '2024-12-25',
        items: [_sampleAsset('p1', DateTime(2024, 12, 25, 14, 0))],
        position: Offset.zero,
        topIndex: 0,
        timeRangeStart: DateTime(2024, 12, 25, 0, 0),
        timeRangeEnd: DateTime(2024, 12, 26, 0, 0),
      );

      // Resolution 1 hour (<= 1 week)
      expect(HolidayRegistry.findHolidayForBatch(christmasBatch, TimeResolution.hour)?.id, 'christmas');

      // Resolution 1 day (<= 1 week)
      expect(HolidayRegistry.findHolidayForBatch(christmasBatch, TimeResolution.day)?.id, 'christmas');

      // Resolution 3 days (<= 1 week)
      const res3Days = TimeResolution(unit: TimeUnit.days, label: '3日', days: 3, step: 3);
      expect(HolidayRegistry.findHolidayForBatch(christmasBatch, res3Days)?.id, 'christmas');

      // Resolution 1 week (<= 1 week)
      expect(HolidayRegistry.findHolidayForBatch(christmasBatch, TimeResolution.week)?.id, 'christmas');

      // Resolution 2 weeks (> 1 week) -> MUST BE NULL
      const res2Weeks = TimeResolution(unit: TimeUnit.weeks, label: '2周', days: 14, step: 14);
      expect(HolidayRegistry.findHolidayForBatch(christmasBatch, res2Weeks), isNull);

      // Resolution 1 month (> 1 week) -> MUST BE NULL
      expect(HolidayRegistry.findHolidayForBatch(christmasBatch, TimeResolution.month), isNull);

      // Resolution 1 year (> 1 week) -> MUST BE NULL
      expect(HolidayRegistry.findHolidayForBatch(christmasBatch, TimeResolution.year), isNull);
    });

    test('Non-holiday batch at <= 1 week resolution does not show decoration', () {
      final normalBatch = MediaBatch(
        id: '2024-06-15',
        items: [_sampleAsset('p1', DateTime(2024, 6, 15, 14, 0))],
        position: Offset.zero,
        topIndex: 0,
        timeRangeStart: DateTime(2024, 6, 15, 0, 0),
        timeRangeEnd: DateTime(2024, 6, 16, 0, 0),
      );

      expect(HolidayRegistry.findHolidayForBatch(normalBatch, TimeResolution.day), isNull);
      expect(HolidayRegistry.findHolidayForBatch(normalBatch, TimeResolution.week), isNull);
    });
  });

  group('Batch preview polaroid decoration rules (30% probability and batch guarantee)', () {
    test('previewStickerProbability is set to 30%', () {
      expect(HolidayRegistry.previewStickerProbability, 0.30);
    });

    test('Non-holiday photos never show decoration', () {
      for (var i = 0; i < 50; i++) {
        final asset = _sampleAsset('norm_$i', DateTime(2024, 7, 10, 12, i));
        expect(HolidayRegistry.holidayForPreviewAsset(asset), isNull);
      }
    });

    test('Holiday photos show decoration with ~30% base probability and stable result per asset', () {
      var decoratedCount = 0;
      const total = 500;
      for (var i = 0; i < total; i++) {
        final asset = _sampleAsset('photo_$i', DateTime(2024, 10, 31, 12, 0));
        final h1 = HolidayRegistry.holidayForPreviewAsset(asset);
        final h2 = HolidayRegistry.holidayForPreviewAsset(asset);
        // Result must be stable across multiple calls for same asset
        expect(h1, equals(h2));
        if (h1 != null) {
          expect(h1.id, 'halloween');
          decoratedCount++;
        }
      }

      // 30% of 500 is 150. Allow reasonable statistical variance (+- 45)
      final fraction = decoratedCount / total;
      expect(fraction, greaterThan(0.22));
      expect(fraction, lessThan(0.38));
    });

    test('Batch containing holiday photo guarantees at least one decorated photo', () {
      // Find an asset ID whose hash is >= 0.30 (would normally NOT be decorated)
      MediaAsset? highHashAsset;
      for (var i = 0; i < 100; i++) {
        final asset = _sampleAsset('candidate_$i', DateTime(2024, 12, 25, 10, 0));
        if (HolidayRegistry.holidayForPreviewAsset(asset) == null) {
          highHashAsset = asset;
          break;
        }
      }
      expect(highHashAsset, isNotNull);

      // Single photo in batch: normally wouldn't get a sticker, but batch guarantee forces at least one!
      final singleBatch = [highHashAsset!];
      final decorations = HolidayRegistry.decoratedAssetsForBatch(singleBatch);
      expect(decorations.length, 1);
      expect(decorations[highHashAsset.id]?.id, 'christmas');

      // Test holidayForPreviewAsset with batchItems passed
      expect(
        HolidayRegistry.holidayForPreviewAsset(highHashAsset, batchItems: singleBatch)?.id,
        'christmas',
      );
    });

    test('Batch with mixed normal and holiday photos decorates holiday photos, never normal photos', () {
      final normalAsset1 = _sampleAsset('norm_1', DateTime(2024, 6, 1));
      final normalAsset2 = _sampleAsset('norm_2', DateTime(2024, 6, 2));
      final holidayAsset = _sampleAsset('xmas_1', DateTime(2024, 12, 25, 8, 0));

      final batch = [normalAsset1, normalAsset2, holidayAsset];
      final decorations = HolidayRegistry.decoratedAssetsForBatch(batch);

      expect(decorations.containsKey('norm_1'), isFalse);
      expect(decorations.containsKey('norm_2'), isFalse);
      expect(decorations.containsKey('xmas_1'), isTrue);
      expect(decorations['xmas_1']?.id, 'christmas');
    });

    test('Batch with 0 holiday photos produces empty decorations', () {
      final batch = [
        _sampleAsset('a1', DateTime(2024, 5, 1)),
        _sampleAsset('a2', DateTime(2024, 5, 2)),
      ];
      final decorations = HolidayRegistry.decoratedAssetsForBatch(batch);
      expect(decorations, isEmpty);
    });
  });

  group('Extensibility and variant selection', () {
    test('Variant index is always 1, 2, or 3 and generates correct asset path', () {
      final holidays = ['christmas', 'halloween', 'new_year', 'spring_festival', 'dragon_boat', 'mid_autumn'];
      for (final id in holidays) {
        final holiday = HolidayRegistry.holidays.firstWhere((h) => h.id == id);
        for (var i = 0; i < 10; i++) {
          final variant = holiday.variantForSeed('seed-$i');
          expect(variant, inInclusiveRange(1, 3));
          final path = holiday.assetPath(variant);
          expect(path, matches(RegExp('^assets/holidays/${holiday.assetPrefix}_[123]\\.png\$')));
        }
      }
    });

    test('Can register a new custom holiday easily', () {
      const valentine = FixedDateHoliday(
        id: 'valentine',
        name: '情人节',
        assetPrefix: 'valentine',
        month: 2,
        day: 14,
      );
      HolidayRegistry.holidays.add(valentine);

      final match = HolidayRegistry.findHolidayForDate(DateTime(2024, 2, 14, 18, 0));
      expect(match?.id, 'valentine');
      expect(match?.name, '情人节');
      expect(match?.assetPath(1), 'assets/holidays/valentine_1.png');

      // Clean up test registry
      HolidayRegistry.holidays.removeWhere((h) => h.id == 'valentine');
    });
  });

  group('Widget rendering tests for holiday decorations', () {
    testWidgets('BatchStack displays HolidayStickerWidget when resolution <= 1 week', (tester) async {
      final christmasBatch = MediaBatch(
        id: '2024-12-25',
        items: [_sampleAsset('c1', DateTime(2024, 12, 25, 12, 0))],
        position: Offset.zero,
        topIndex: 0,
        timeRangeStart: DateTime(2024, 12, 25),
        timeRangeEnd: DateTime(2024, 12, 26),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BatchStack(
              batch: christmasBatch,
              onTap: () {},
              resolution: TimeResolution.day,
            ),
          ),
        ),
      );

      expect(find.byType(HolidayStickerWidget), findsOneWidget);
    });

    testWidgets('BatchStack does not display HolidayStickerWidget when resolution > 1 week', (tester) async {
      final christmasBatch = MediaBatch(
        id: '2024-12-25',
        items: [_sampleAsset('c1', DateTime(2024, 12, 25, 12, 0))],
        position: Offset.zero,
        topIndex: 0,
        timeRangeStart: DateTime(2024, 12, 25),
        timeRangeEnd: DateTime(2024, 12, 26),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BatchStack(
              batch: christmasBatch,
              onTap: () {},
              resolution: TimeResolution.month,
            ),
          ),
        ),
      );

      expect(find.byType(HolidayStickerWidget), findsNothing);
    });
  });
}

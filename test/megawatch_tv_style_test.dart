import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:megawatch/services/storage_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('megawatch_tv_style coercion (total, both directions)', () {
    test('an unknown stored value reads as grid', () async {
      // Written by a newer build, read by this one: land on the layout that
      // always existed rather than rendering nothing.
      SharedPreferences.setMockInitialValues({
        'megawatch_tv_style': 'holodeck',
      });
      expect(await StorageService.getMegaWatchTvStyle(), 'grid');
      expect(StorageService.megawatchTvStyleCached, 'grid');
    });

    test('an unknown value passed to the setter persists as grid', () async {
      SharedPreferences.setMockInitialValues({});
      await StorageService.setMegaWatchTvStyle('holodeck');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('megawatch_tv_style'), 'grid');
      expect(StorageService.megawatchTvStyleCached, 'grid');
    });

    test('spotlight round-trips, and the mirror is published before the read',
        () async {
      SharedPreferences.setMockInitialValues({});
      final write = StorageService.setMegaWatchTvStyle('spotlight');
      // Mirror BEFORE the await — anything reading synchronously on the next
      // frame already sees the choice.
      expect(StorageService.megawatchTvStyleCached, 'spotlight');
      await write;
      expect(await StorageService.getMegaWatchTvStyle(), 'spotlight');
    });

    test('an absent key reads as grid', () async {
      SharedPreferences.setMockInitialValues({});
      expect(await StorageService.getMegaWatchTvStyle(), 'grid');
    });
  });
}

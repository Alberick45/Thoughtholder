import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

void main() {
  test('daily goal celebration date persists across restart', () async {
    final dir = await Directory.systemTemp.createTemp('th_hive_');
    Hive.init(dir.path);
    var box = await Hive.openBox('app_settings');
    expect(box.get('last_daily_goal_celebrated_date', defaultValue: ''), '');
    await box.put('last_daily_goal_celebrated_date', '2026-11-27');
    await box.close();
    box = await Hive.openBox('app_settings');
    expect(box.get('last_daily_goal_celebrated_date'), '2026-11-27');
    await box.close();
    await Hive.close();
    await dir.delete(recursive: true);
  });
}

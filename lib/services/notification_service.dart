import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../constants.dart';
import '../helpers/date_helpers.dart';
import '../helpers/stock_math.dart';
import '../models/medicine.dart';

/// Local refill reminders.
///
/// Because consumption is fully deterministic, we do not need a background
/// job: for every medicine we can compute the exact date its stock will fall
/// to the warning threshold and schedule a concrete notification for that
/// day. The whole set is rebuilt whenever data changes, so the reminders
/// always reflect the current stock and dosages.
class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  static const String _channelId = 'medstock_refill';
  static const String _channelName = 'Refill reminders';
  static const String _channelDesc =
      'Warns you before a medicine runs out of stock.';

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _ready = false;

  Future<void> init() async {
    if (_ready) return;

    tzdata.initializeTimeZones();
    await _setLocalTimezone();

    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
    );
    _ready = true;
  }

  /// Resolves the device's IANA zone so a 9 a.m. reminder really fires at
  /// 9 a.m. local. Falls back to UTC rather than failing initialisation.
  Future<void> _setLocalTimezone() async {
    try {
      final info = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(info.identifier));
    } catch (e) {
      debugPrint('Medstock: could not resolve local timezone ($e) — using UTC');
      tz.setLocalLocation(tz.UTC);
    }
  }

  /// Asks for POST_NOTIFICATIONS on Android 13+. Safe to call repeatedly.
  Future<bool> requestPermission() async {
    await init();
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android == null) return false;
    return await android.requestNotificationsPermission() ?? false;
  }

  Future<bool> areNotificationsEnabled() async {
    await init();
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    return await android?.areNotificationsEnabled() ?? false;
  }

  /// Cancels every pending reminder and re-schedules from current data.
  Future<void> rescheduleAll(List<Medicine> medicines) async {
    await init();
    await _plugin.cancelAll();

    for (final medicine in medicines) {
      await _scheduleFor(medicine);
    }
  }

  Future<void> _scheduleFor(Medicine medicine) async {
    final id = medicine.id;
    if (id == null || !medicine.reminderEnabled) return;

    final reminderDay = StockMath.reminderDateFor(medicine);
    if (reminderDay == null) return;

    final status = StockMath.status(medicine);
    final runOut = status.runOutDate;
    if (runOut == null) return;

    // Fire at the configured hour on the reminder day. If that moment has
    // already passed but stock is still running down, nudge tomorrow morning
    // instead of dropping the reminder entirely.
    final now = tz.TZDateTime.now(tz.local);
    var when = tz.TZDateTime(
      tz.local,
      reminderDay.year,
      reminderDay.month,
      reminderDay.day,
      K.reminderHour,
    );

    if (!when.isAfter(now)) {
      if (!runOut.isAfter(Dates.today())) return; // already out; nothing to warn
      final tomorrow = now.add(const Duration(days: 1));
      when = tz.TZDateTime(
        tz.local,
        tomorrow.year,
        tomorrow.month,
        tomorrow.day,
        K.reminderHour,
      );
    }

    final daysAtReminder = Dates.daysBetween(
      Dates.dayOf(DateTime(when.year, when.month, when.day)),
      runOut,
    );

    final body = daysAtReminder <= 0
        ? 'Stock has run out. Time to reorder.'
        : 'About $daysAtReminder ${daysAtReminder == 1 ? 'day' : 'days'} of '
            'stock left — reorder soon.';

    await _plugin.zonedSchedule(
      id: id,
      title: '${medicine.displayName} is running low',
      body: body,
      scheduledDate: when,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: _channelDesc,
          importance: Importance.high,
          priority: Priority.high,
          // Medicine names are health data: keep them off a locked screen.
          // The notification still appears, but its content is hidden until
          // the device is unlocked.
          visibility: NotificationVisibility.private,
          styleInformation: BigTextStyleInformation(''),
        ),
      ),
      // Inexact scheduling avoids needing the SCHEDULE_EXACT_ALARM permission;
      // a refill nudge does not need to-the-minute accuracy.
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      payload: 'medicine:$id',
    );
  }

  Future<List<PendingNotificationRequest>> pending() async {
    await init();
    return _plugin.pendingNotificationRequests();
  }

  Future<void> cancelAll() async {
    await init();
    await _plugin.cancelAll();
  }
}

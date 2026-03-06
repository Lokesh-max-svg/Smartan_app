import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._();
  factory NotificationService() => _instance;
  NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;

  // Callback when user taps the "Dismiss" action
  static void Function()? onDismissAction;

  static const int reidNotificationId = 1001;

  Future<void> init() async {
    if (_initialized) return;

    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: false,
      requestSoundPermission: true,
    );

    final didInit = await _plugin.initialize(
      const InitializationSettings(
        android: androidSettings,
        iOS: iosSettings,
      ),
      onDidReceiveNotificationResponse: _onNotificationResponse,
    );
    debugPrint('NotificationService: init result=$didInit');

    // Request permission on Android 13+
    final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (androidPlugin != null) {
      final granted = await androidPlugin.requestNotificationsPermission();
      debugPrint('NotificationService: permission granted=$granted');

      // Create notification channel explicitly
      await androidPlugin.createNotificationChannel(
        const AndroidNotificationChannel(
          'reid_status_channel',
          'Identification Status',
          description: 'Alerts when you are not yet identified in the gym',
          importance: Importance.high,
        ),
      );
      debugPrint('NotificationService: channel created');
    }

    _initialized = true;
  }

  static void _onNotificationResponse(NotificationResponse response) {
    debugPrint('NotificationService: response actionId=${response.actionId}');
    if (response.actionId == 'close_reid') {
      onDismissAction?.call();
    }
  }

  Future<void> showReidAlert() async {
    try {
      if (!_initialized) await init();

      const androidDetails = AndroidNotificationDetails(
        'reid_status_channel',
        'Identification Status',
        channelDescription:
            'Alerts when you are not yet identified in the gym',
        importance: Importance.high,
        priority: Priority.high,
        ongoing: true,
        autoCancel: false,
        playSound: true,
        enableVibration: true,
        actions: [
          AndroidNotificationAction(
            'close_reid',
            'Close',
            showsUserInterface: false,
            cancelNotification: true,
          ),
        ],
      );

      const iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentSound: true,
      );

      await _plugin.show(
        reidNotificationId,
        'Not yet identified',
        'Please stand in front of the camera to be identified',
        const NotificationDetails(
          android: androidDetails,
          iOS: iosDetails,
        ),
      );
      debugPrint('NotificationService: notification shown');
    } catch (e) {
      debugPrint('NotificationService: showReidAlert error=$e');
    }
  }

  Future<void> cancelReidAlert() async {
    try {
      await _plugin.cancel(reidNotificationId);
    } catch (e) {
      debugPrint('NotificationService: cancelReidAlert error=$e');
    }
  }
}

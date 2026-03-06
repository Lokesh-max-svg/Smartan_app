import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'notification_service.dart';
import 'api_client.dart';

/// Reid Monitor Service - Uses backend API with polling instead of Firestore listeners
class ReidMonitorService {
  static final ReidMonitorService _instance = ReidMonitorService._();
  factory ReidMonitorService() => _instance;
  ReidMonitorService._();

  final NotificationService _notificationService = NotificationService();
  final AudioPlayer _beepPlayer = AudioPlayer();

  // Public observable state for UI
  final ValueNotifier<int> reidStatus = ValueNotifier<int>(0);
  final ValueNotifier<bool> alertDismissed = ValueNotifier<bool>(false);

  // Internal state
  Timer? _pollingTimer;
  Timer? _alertTimer;
  Uint8List? _beepBytes;
  String? _activeSessionDocId;
  bool _soundEnabled = true;

  bool get isMonitoring => _pollingTimer != null;
  String? get activeSessionDocId => _activeSessionDocId;
  bool get soundEnabled => _soundEnabled;

  static const String _soundPrefKey = 'reid_sound_enabled';
  static const Duration _pollingInterval = Duration(seconds: 3); // Poll every 3 seconds

  Future<void> startMonitoring(String sessionDocId) async {
    // If already monitoring this session, no-op
    if (_activeSessionDocId == sessionDocId && _pollingTimer != null) {
      return;
    }

    // Stop any previous monitoring
    await stopMonitoring();

    _activeSessionDocId = sessionDocId;
    _beepBytes ??= _generateBeepWav();
    await _loadSoundPreference();
    await _notificationService.init();
    NotificationService.onDismissAction = _dismissAlert;

    // Reset state
    reidStatus.value = 0;
    alertDismissed.value = false;

    // Start polling timer instead of Firestore listener
    _pollingTimer = Timer.periodic(_pollingInterval, (_) async {
      await _pollSessionStatus();
    });

    // Initial poll
    await _pollSessionStatus();
  }

  /// Poll session status from backend API
  Future<void> _pollSessionStatus() async {
    if (_activeSessionDocId == null) return;

    try {
      final response = await ApiClient.getSession(_activeSessionDocId!);
      
      if (response['success'] != true) {
        debugPrint('ReidMonitorService: Failed to get session status');
        return;
      }

      final session = response['session'] as Map<String, dynamic>;
      final newReidStatus = session['reid_status'] as int? ?? 0;
      final sessionStatus = session['status'] as String? ?? 'Active';

      // If session closed, stop monitoring
      if (sessionStatus == 'Closed') {
        await stopMonitoring();
        return;
      }

      reidStatus.value = newReidStatus;

      if (newReidStatus == 0) {
        _startReidAlert();
      } else if (newReidStatus == 1) {
        alertDismissed.value = false;
        _stopReidAlert();
      }
    } catch (e) {
      debugPrint('ReidMonitorService: polling error=$e');
    }
  }

  Future<void> stopMonitoring() async {
    _stopReidAlert();
    _pollingTimer?.cancel();
    _pollingTimer = null;
    _activeSessionDocId = null;
    reidStatus.value = 0;
    alertDismissed.value = false;
    NotificationService.onDismissAction = null;
  }

  void dismissAlert() => _dismissAlert();

  void _dismissAlert() {
    alertDismissed.value = true;
    _stopReidAlert();
  }

  void _startReidAlert() {
    if (alertDismissed.value || _alertTimer != null) return;
    _triggerAlert();
    _notificationService.showReidAlert().catchError((e) {
      debugPrint('ReidMonitorService: notification error=$e');
    });
    _alertTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (reidStatus.value == 0 && !alertDismissed.value) {
        _triggerAlert();
      } else {
        _stopReidAlert();
      }
    });
  }

  void _stopReidAlert() {
    _alertTimer?.cancel();
    _alertTimer = null;
    _notificationService.cancelReidAlert();
  }

  void _triggerAlert() {
    HapticFeedback.vibrate();
    if (_soundEnabled && _beepBytes != null) {
      _beepPlayer.play(BytesSource(_beepBytes!));
    }
  }

  Future<void> _loadSoundPreference() async {
    final prefs = await SharedPreferences.getInstance();
    _soundEnabled = prefs.getBool(_soundPrefKey) ?? true;
  }

  Future<void> setSoundEnabled(bool enabled) async {
    _soundEnabled = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_soundPrefKey, enabled);
  }

  /// Generate a short beep tone as WAV bytes (no audio file needed)
  Uint8List _generateBeepWav({
    int frequency = 1000,
    double durationSeconds = 0.3,
    int sampleRate = 44100,
  }) {
    final numSamples = (sampleRate * durationSeconds).toInt();
    final dataSize = numSamples * 2; // 16-bit mono
    final fileSize = 36 + dataSize;

    final buffer = ByteData(44 + dataSize);

    // RIFF header
    buffer.setUint32(0, 0x46464952, Endian.big); // "RIFF"
    buffer.setUint32(4, fileSize, Endian.little);
    buffer.setUint32(8, 0x45564157, Endian.big); // "WAVE"

    // fmt chunk
    buffer.setUint32(12, 0x20746D66, Endian.big); // "fmt "
    buffer.setUint32(16, 16, Endian.little); // Chunk size
    buffer.setUint16(20, 1, Endian.little); // Audio format (PCM)
    buffer.setUint16(22, 1, Endian.little); // Num channels (mono)
    buffer.setUint32(24, sampleRate, Endian.little);
    buffer.setUint32(28, sampleRate * 2, Endian.little); // Byte rate
    buffer.setUint16(32, 2, Endian.little); // Block align
    buffer.setUint16(34, 16, Endian.little); // Bits per sample

    // data chunk
    buffer.setUint32(36, 0x61746164, Endian.big); // "data"
    buffer.setUint32(40, dataSize, Endian.little);

    // Generate sine wave samples
    for (int i = 0; i < numSamples; i++) {
      final t = i / sampleRate;
      final value = (sin(2 * pi * frequency * t) * 0x7FFF).toInt();
      buffer.setInt16(44 + i * 2, value, Endian.little);
    }

    return buffer.buffer.asUint8List();
  }
}

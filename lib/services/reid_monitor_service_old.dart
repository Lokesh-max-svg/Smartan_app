import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'notification_service.dart';

class ReidMonitorService {
  static final ReidMonitorService _instance = ReidMonitorService._();
  factory ReidMonitorService() => _instance;
  ReidMonitorService._();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final NotificationService _notificationService = NotificationService();
  final AudioPlayer _beepPlayer = AudioPlayer();

  // Public observable state for UI
  final ValueNotifier<int> reidStatus = ValueNotifier<int>(0);
  final ValueNotifier<bool> alertDismissed = ValueNotifier<bool>(false);

  // Internal state
  StreamSubscription<DocumentSnapshot>? _sessionSubscription;
  Timer? _alertTimer;
  Uint8List? _beepBytes;
  String? _activeSessionDocId;
  bool _soundEnabled = true;

  bool get isMonitoring => _sessionSubscription != null;
  String? get activeSessionDocId => _activeSessionDocId;
  bool get soundEnabled => _soundEnabled;

  static const String _soundPrefKey = 'reid_sound_enabled';

  Future<void> startMonitoring(String sessionDocId) async {
    // If already monitoring this session, no-op
    if (_activeSessionDocId == sessionDocId && _sessionSubscription != null) {
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

    // Start Firestore listener
    _sessionSubscription = _firestore
        .collection('sessions')
        .doc(sessionDocId)
        .snapshots()
        .listen((snapshot) {
      if (!snapshot.exists) return;

      final data = snapshot.data();
      final newReidStatus = data?['reid_status'] as int? ?? 0;
      final sessionStatus = data?['status'] as String? ?? 'Active';

      // If session closed, stop monitoring
      if (sessionStatus == 'Closed') {
        stopMonitoring();
        return;
      }

      reidStatus.value = newReidStatus;

      if (newReidStatus == 0) {
        _startReidAlert();
      } else if (newReidStatus == 1) {
        alertDismissed.value = false;
        _stopReidAlert();
      }
    }, onError: (e) {
      debugPrint('ReidMonitorService: listener error=$e');
    });
  }

  Future<void> stopMonitoring() async {
    _stopReidAlert();
    _sessionSubscription?.cancel();
    _sessionSubscription = null;
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
    final bytes = ByteData(44 + dataSize);

    // RIFF header
    final riff = 'RIFF'.codeUnits;
    final wave = 'WAVE'.codeUnits;
    final fmt = 'fmt '.codeUnits;
    final data = 'data'.codeUnits;
    for (int i = 0; i < 4; i++) {
      bytes.setUint8(i, riff[i]);
      bytes.setUint8(8 + i, wave[i]);
      bytes.setUint8(12 + i, fmt[i]);
      bytes.setUint8(36 + i, data[i]);
    }
    bytes.setUint32(4, fileSize, Endian.little);
    bytes.setUint32(16, 16, Endian.little); // chunk size
    bytes.setUint16(20, 1, Endian.little); // PCM
    bytes.setUint16(22, 1, Endian.little); // mono
    bytes.setUint32(24, sampleRate, Endian.little);
    bytes.setUint32(28, sampleRate * 2, Endian.little); // byte rate
    bytes.setUint16(32, 2, Endian.little); // block align
    bytes.setUint16(34, 16, Endian.little); // bits per sample
    bytes.setUint32(40, dataSize, Endian.little);

    // Sine wave with fade-in/out to avoid click
    for (int i = 0; i < numSamples; i++) {
      double envelope = 1.0;
      final fadeLen = (sampleRate * 0.02).toInt(); // 20ms fade
      if (i < fadeLen) envelope = i / fadeLen;
      if (i > numSamples - fadeLen) envelope = (numSamples - i) / fadeLen;
      final sample =
          (sin(2 * pi * frequency * i / sampleRate) * 32767 * 0.6 * envelope)
              .toInt();
      bytes.setInt16(
          44 + i * 2, sample.clamp(-32768, 32767), Endian.little);
    }

    return bytes.buffer.asUint8List();
  }
}

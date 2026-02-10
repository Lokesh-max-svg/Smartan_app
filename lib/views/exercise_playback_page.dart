import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:archive/archive.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:math' as math;

class ExercisePlaybackPage extends StatefulWidget {
  final Map<String, dynamic> exercise;
  final String sessionId;

  const ExercisePlaybackPage({
    super.key,
    required this.exercise,
    required this.sessionId,
  });

  @override
  State<ExercisePlaybackPage> createState() => _ExercisePlaybackPageState();
}

class _ExercisePlaybackPageState extends State<ExercisePlaybackPage> {
  final FirebaseStorage _storage = FirebaseStorage.instance;

  List<Map<String, dynamic>> _gcsFolders = [];

  // All parsed frames stored in memory for smooth playback
  List<_ParsedFrame> _allFrames = [];

  bool _isLoading = true;
  bool _isPlaying = false;
  int _currentFrameIndex = 0;
  String? _errorMessage;
  Timer? _playbackTimer;

  // Loading progress
  int _downloadedFiles = 0;
  int _totalFiles = 0;
  String _loadingStatus = 'Initializing...';
  bool _loadedFromCache = false;

  // 3D viewer state - initial rotation to show body upright facing forward
  double _rotationX = -0.1;  // Slight tilt for better view
  double _rotationY = 0.0;
  double _scale = 1.5;  // Default zoom 1.5x
  Offset _lastPanPosition = Offset.zero;
  bool _flipVertical = true;  // Flip to correct upside-down orientation

  // Playback speed (fps)
  double _playbackSpeed = 5.0;  // Default 5 fps

  // Point density (1.0 = all points, 0.1 = 10% of points)
  double _density = 1.0;

  // Point color presets
  static const List<Color> _colorPresets = [
    Color(0xFF4ECDC4),  // Teal (default)
    Color(0xFFA4FEB7),  // Green
    Color(0xFFFF6B6B),  // Red/Coral
    Color(0xFFFFE66D),  // Yellow
    Color(0xFFAB83FF),  // Purple
    Color(0xFF74B9FF),  // Blue
    Color(0xFFFFFFFF),  // White
    Color(0xFFFF9F43),  // Orange
  ];
  int _selectedColorIndex = 0;

  // Show controls panel
  bool _showControls = false;

  // Weight per recording (extracted from filename)
  List<double> _recordingWeights = [];

  // Cache expiry: 7 days
  static const int _cacheExpiryDays = 7;

  @override
  void initState() {
    super.initState();
    _loadAllFrames();
  }

  @override
  void dispose() {
    _playbackTimer?.cancel();
    super.dispose();
  }

  /// Get the cache directory for this exercise
  Future<Directory> _getCacheDirectory() async {
    final appDir = await getApplicationDocumentsDirectory();
    final exerciseName = (widget.exercise['name'] ?? 'unknown').toString().replaceAll(' ', '_');
    final cacheDir = Directory('${appDir.path}/pose_cache/${widget.sessionId}/$exerciseName');
    if (!await cacheDir.exists()) {
      await cacheDir.create(recursive: true);
    }
    return cacheDir;
  }

  /// Clean up old cache files (older than 7 days)
  Future<void> _cleanOldCache() async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final cacheRootDir = Directory('${appDir.path}/pose_cache');

      if (!await cacheRootDir.exists()) return;

      final now = DateTime.now();
      final expiryDate = now.subtract(Duration(days: _cacheExpiryDays));

      await for (final entity in cacheRootDir.list(recursive: true)) {
        if (entity is File) {
          final stat = await entity.stat();
          if (stat.modified.isBefore(expiryDate)) {
            await entity.delete();
            debugPrint('Deleted old cache file: ${entity.path}');
          }
        }
      }

      // Clean up empty directories
      await for (final entity in cacheRootDir.list(recursive: true)) {
        if (entity is Directory) {
          try {
            final contents = await entity.list().toList();
            if (contents.isEmpty) {
              await entity.delete();
            }
          } catch (_) {}
        }
      }
    } catch (e) {
      debugPrint('Error cleaning cache: $e');
    }
  }

  /// Check if cache exists and is valid
  Future<bool> _isCacheValid() async {
    try {
      final cacheDir = await _getCacheDirectory();
      final metaFile = File('${cacheDir.path}/meta.json');

      if (!await metaFile.exists()) return false;

      final metaJson = jsonDecode(await metaFile.readAsString());
      final cachedAt = DateTime.parse(metaJson['cachedAt']);
      final frameCount = metaJson['frameCount'] as int;

      // Check if cache is expired
      final expiryDate = DateTime.now().subtract(Duration(days: _cacheExpiryDays));
      if (cachedAt.isBefore(expiryDate)) {
        debugPrint('Cache expired');
        return false;
      }

      // Check if all frame files exist
      for (int i = 0; i < frameCount; i++) {
        final frameFile = File('${cacheDir.path}/frame_$i.bin');
        if (!await frameFile.exists()) {
          debugPrint('Missing cache file: frame_$i.bin');
          return false;
        }
      }

      debugPrint('Cache is valid with $frameCount frames');
      return true;
    } catch (e) {
      debugPrint('Cache validation error: $e');
      return false;
    }
  }

  /// Load frames from local cache
  Future<bool> _loadFromCache() async {
    try {
      final cacheDir = await _getCacheDirectory();
      final metaFile = File('${cacheDir.path}/meta.json');
      final metaJson = jsonDecode(await metaFile.readAsString());
      final frameCount = metaJson['frameCount'] as int;
      final recordingBoundaries = List<int>.from(metaJson['recordingBoundaries']);
      final recordingWeights = List<double>.from(
        (metaJson['recordingWeights'] as List<dynamic>?)?.map((e) => (e as num).toDouble()) ?? []
      );

      // Set the weights from cache
      _recordingWeights = recordingWeights;

      setState(() {
        _loadingStatus = 'Loading from cache...';
        _totalFiles = frameCount;
      });

      List<_ParsedFrame> frames = [];

      for (int i = 0; i < frameCount; i++) {
        final frameFile = File('${cacheDir.path}/frame_$i.bin');
        final bytes = await frameFile.readAsBytes();
        final vertices = _parseVertices(bytes);

        // Determine recording index from boundaries
        int recordingIndex = 0;
        for (int j = 0; j < recordingBoundaries.length; j++) {
          if (i < recordingBoundaries[j]) {
            recordingIndex = j;
            break;
          }
        }

        frames.add(_ParsedFrame(
          vertices: vertices,
          recordingIndex: recordingIndex,
        ));

        if (i % 20 == 0) {
          setState(() {
            _downloadedFiles = i + 1;
            _loadingStatus = 'Loading from cache... ${i + 1}/$frameCount';
          });
        }
      }

      setState(() {
        _allFrames = frames;
        _loadedFromCache = true;
      });

      debugPrint('Loaded $frameCount frames from cache, weights: $_recordingWeights');
      return true;
    } catch (e) {
      debugPrint('Error loading from cache: $e');
      return false;
    }
  }

  /// Save frames to local cache
  Future<void> _saveToCache(List<Uint8List> rawFrames, List<int> recordingBoundaries) async {
    try {
      final cacheDir = await _getCacheDirectory();

      // Save each frame
      for (int i = 0; i < rawFrames.length; i++) {
        final frameFile = File('${cacheDir.path}/frame_$i.bin');
        await frameFile.writeAsBytes(rawFrames[i]);
      }

      // Save metadata
      final metaFile = File('${cacheDir.path}/meta.json');
      await metaFile.writeAsString(jsonEncode({
        'cachedAt': DateTime.now().toIso8601String(),
        'frameCount': rawFrames.length,
        'recordingBoundaries': recordingBoundaries,
        'recordingWeights': _recordingWeights,
        'sessionId': widget.sessionId,
        'exerciseName': widget.exercise['name'],
      }));

      debugPrint('Saved ${rawFrames.length} frames to cache');
    } catch (e) {
      debugPrint('Error saving to cache: $e');
    }
  }

  /// Load all frames - checks cache first, then downloads from Firebase
  Future<void> _loadAllFrames() async {
    // Clean old cache files in background
    _cleanOldCache();

    debugPrint('=== Loading frames for session: ${widget.sessionId} ===');
    debugPrint('Exercise name: ${widget.exercise['name']}');
    debugPrint('Exercise data: ${widget.exercise}');

    var folders = widget.exercise['gcs_folders'] as List<dynamic>? ?? [];
    debugPrint('Initial gcs_folders from widget: ${folders.length}');

    // If no gcs_folders in exercise data, fetch from Firestore sessions collection
    String? userId;
    if (folders.isEmpty) {
      setState(() {
        _loadingStatus = 'Fetching recording data...';
      });

      try {
        debugPrint('Fetching session with sessionId: ${widget.sessionId}');

        // First try to get by document ID
        var sessionDoc = await FirebaseFirestore.instance
            .collection('sessions')
            .doc(widget.sessionId)
            .get();

        // If not found by doc ID, query by sessionId field
        if (!sessionDoc.exists) {
          debugPrint('Not found by doc ID, querying by sessionId field...');
          final querySnapshot = await FirebaseFirestore.instance
              .collection('sessions')
              .where('sessionId', isEqualTo: widget.sessionId)
              .limit(1)
              .get();

          if (querySnapshot.docs.isNotEmpty) {
            sessionDoc = querySnapshot.docs.first;
            debugPrint('Found session by sessionId field: ${sessionDoc.id}');
          }
        }

        debugPrint('Session doc exists: ${sessionDoc.exists}');
        if (sessionDoc.exists) {
          final sessionData = sessionDoc.data();
          userId = sessionData?['userId'] as String?;
          debugPrint('UserId from session: $userId');
          debugPrint('Session data keys: ${sessionData?.keys.toList()}');

          final exercises = sessionData?['exercises'] as List<dynamic>? ?? [];
          final exerciseName = widget.exercise['name'] as String? ?? '';
          final normalizedExerciseName = exerciseName.toLowerCase().replaceAll(' ', '_');
          debugPrint('Looking for exercise: $exerciseName (normalized: $normalizedExerciseName) in ${exercises.length} exercises');

          // Find matching exercise by name
          for (final ex in exercises) {
            final exMap = ex as Map<String, dynamic>;
            final exName = exMap['name'] as String? ?? '';
            final normalizedExName = exName.toLowerCase().replaceAll(' ', '_');
            debugPrint('  Checking: $exName (normalized: $normalizedExName) - gcs_folders: ${(exMap['gcs_folders'] as List?)?.length ?? 0}');

            // Match by exact name or normalized name
            if (exName == exerciseName || normalizedExName == normalizedExerciseName) {
              folders = exMap['gcs_folders'] as List<dynamic>? ?? [];
              debugPrint('Fetched ${folders.length} gcs_folders from Firestore for $exerciseName');
              break;
            }
          }

          // If still no folders, check if gcs_folders exist at session level (legacy format)
          if (folders.isEmpty) {
            final sessionGcsFolders = sessionData?['gcs_folders'] as List<dynamic>? ?? [];
            if (sessionGcsFolders.isNotEmpty) {
              debugPrint('Found ${sessionGcsFolders.length} gcs_folders at session level');
              // Filter by exercise name
              final filteredFolders = <dynamic>[];
              for (final folder in sessionGcsFolders) {
                final folderMap = folder as Map<String, dynamic>;
                final path = folderMap['path'] as String? ?? '';
                if (path.contains(normalizedExerciseName)) {
                  filteredFolders.add(folder);
                }
              }
              folders = filteredFolders;
              debugPrint('Filtered to ${folders.length} folders for $exerciseName');
            }
          }
        }
      } catch (e) {
        debugPrint('Error fetching gcs_folders from Firestore: $e');
      }
    }

    // Fallback: scan Storage directly if no gcs_folders found
    debugPrint('After Firestore fetch - folders: ${folders.length}, userId: $userId');
    if (folders.isEmpty && userId != null) {
      setState(() {
        _loadingStatus = 'Scanning storage for recordings...';
      });

      try {
        final exerciseName = (widget.exercise['name'] as String? ?? '').toLowerCase().replaceAll(' ', '_');
        final storagePath = 'pose_data/$userId/${widget.sessionId}';
        debugPrint('Scanning storage: $storagePath for exercise: $exerciseName');

        final storageRef = _storage.ref(storagePath);
        final listResult = await storageRef.listAll();

        // Filter folders matching this exercise name
        final matchingFolders = <Map<String, dynamic>>[];
        for (final prefix in listResult.prefixes) {
          final folderName = prefix.name;
          // Pattern: exerciseName_cam_X_X_timestamp (e.g., front_raise_cam_1_6_1770706423)
          if (folderName.startsWith(exerciseName)) {
            final parsed = _parseGcsFolderName(folderName);
            if (parsed != null) {
              matchingFolders.add({
                'path': '$storagePath/$folderName',
                'camera': parsed['camera'],
                'batch': parsed['batch'],
                'timestamp': parsed['timestamp'],
              });
              debugPrint('Found folder: $folderName -> batch ${parsed['batch']}');
            }
          }
        }

        folders = matchingFolders;
        debugPrint('Found ${folders.length} folders from Storage scan');
      } catch (e) {
        debugPrint('Error scanning storage: $e');
      }
    }

    _gcsFolders = folders.map((f) => Map<String, dynamic>.from(f)).toList();

    // Sort by batch number first (primary), then by timestamp (secondary)
    _gcsFolders.sort((a, b) {
      final batchA = a['batch'] as int? ?? 0;
      final batchB = b['batch'] as int? ?? 0;
      if (batchA != batchB) {
        return batchA.compareTo(batchB);
      }
      final timestampA = a['timestamp'] as int? ?? 0;
      final timestampB = b['timestamp'] as int? ?? 0;
      return timestampA.compareTo(timestampB);
    });

    if (_gcsFolders.isEmpty) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'No recordings available';
      });
      return;
    }

    // Check if we have valid cache
    if (await _isCacheValid()) {
      final loaded = await _loadFromCache();
      if (loaded && _allFrames.isNotEmpty) {
        setState(() {
          _isLoading = false;
        });
        return;
      }
    }

    // Check if paths are in pose_data (new ZIP format) or old format (individual files)
    final firstPath = _gcsFolders.first['path'] as String? ?? '';
    final isNewFormat = firstPath.contains('pose_data') || firstPath.endsWith('.zip');

    if (isNewFormat) {
      await _loadFromZipFiles();
    } else {
      await _loadFromIndividualFiles();
    }
  }

  /// Load frames from ZIP files (new optimized format - 1 download per recording)
  Future<void> _loadFromZipFiles() async {
    try {
      setState(() {
        _loadingStatus = 'Downloading recordings...';
        _totalFiles = _gcsFolders.length;
      });

      List<_ParsedFrame> allFrames = [];
      List<Uint8List> rawFramesForCache = [];
      List<int> recordingBoundaries = [];

      for (int i = 0; i < _gcsFolders.length; i++) {
        final folder = _gcsFolders[i];
        var path = folder['path'] as String;
        final batch = folder['batch'] as int? ?? 0;

        // If path doesn't end with .zip, look for ZIP file inside the folder
        if (!path.endsWith('.zip')) {
          final folderName = path.split('/').last;
          path = '$path/$folderName.zip';
        }

        setState(() {
          _loadingStatus = 'Downloading batch $batch (${i + 1}/${_gcsFolders.length})...';
          _downloadedFiles = i;
        });

        debugPrint('Downloading ZIP: $path');

        // Download the ZIP file (single request!)
        final ref = _storage.ref(path);
        final zipData = await ref.getData(50 * 1024 * 1024); // 50MB max

        if (zipData == null) {
          debugPrint('Failed to download ZIP: $path');
          continue;
        }

        debugPrint('ZIP downloaded: ${zipData.length} bytes');

        // Extract frames from ZIP
        final archive = ZipDecoder().decodeBytes(zipData);

        // Get .bin files and sort by frame number
        final binFiles = archive.files
            .where((f) => f.name.endsWith('.bin') && f.isFile)
            .toList();

        // Sort by frame number (extract number from filename)
        binFiles.sort((a, b) {
          final numA = _extractFrameNumber(a.name);
          final numB = _extractFrameNumber(b.name);
          return numA.compareTo(numB);
        });

        debugPrint('Extracted ${binFiles.length} frames from ZIP');

        // Extract weight from first filename
        double weight = 0.0;
        if (binFiles.isNotEmpty) {
          weight = _extractWeight(binFiles.first.name);
          debugPrint('  Weight: ${weight > 0 ? "${weight}kg" : "N/A"}');
        }
        _recordingWeights.add(weight);

        // Parse each frame
        for (final file in binFiles) {
          final content = file.content;
          if (content.isEmpty) continue;

          final bytes = Uint8List.fromList(content);
          final decompressed = _decompressData(bytes);
          final vertices = _parseVertices(decompressed);

          rawFramesForCache.add(decompressed);
          allFrames.add(_ParsedFrame(
            vertices: vertices,
            recordingIndex: i,
          ));
        }

        // Track recording boundary
        recordingBoundaries.add(allFrames.length);
      }

      // Save to cache
      if (rawFramesForCache.isNotEmpty) {
        _saveToCache(rawFramesForCache, recordingBoundaries);
      }

      setState(() {
        _allFrames = allFrames;
        _isLoading = false;
        _downloadedFiles = _gcsFolders.length;
      });

      debugPrint('Loaded ${allFrames.length} total frames from ${_gcsFolders.length} ZIP files');
    } catch (e) {
      debugPrint('Error loading from ZIP: $e');
      setState(() {
        _isLoading = false;
        _errorMessage = 'Failed to load: $e';
      });
    }
  }

  /// Parse GCS folder name to extract camera, batch, timestamp
  /// Format: {exercise_name}_cam_{camera}_{batch}_{timestamp}
  /// e.g., "front_raise_cam_1_6_1770706423"
  Map<String, int>? _parseGcsFolderName(String folderName) {
    // Match pattern: anything_cam_X_X_timestamp
    final match = RegExp(r'_cam_(\d+)_(\d+)_(\d+)$').firstMatch(folderName);
    if (match == null) return null;

    return {
      'camera': int.tryParse(match.group(1) ?? '0') ?? 0,
      'batch': int.tryParse(match.group(2) ?? '0') ?? 0,
      'timestamp': int.tryParse(match.group(3) ?? '0') ?? 0,
    };
  }

  /// Extract frame number from filename like "cam_1_track6_entry3_front_raise_5.0_frame0033.bin"
  int _extractFrameNumber(String filename) {
    final match = RegExp(r'frame(\d+)\.bin$').firstMatch(filename);
    if (match != null) {
      return int.tryParse(match.group(1) ?? '0') ?? 0;
    }
    return 0;
  }

  /// Extract weight from filename like "cam_1_track6_entry3_front_raise_5.0_frame0033.bin"
  /// Returns the weight (e.g., 5.0) or 0.0 if not found
  double _extractWeight(String filename) {
    // Pattern: exercise_name_WEIGHT_frame where WEIGHT is like "5.0" or "10.5"
    final match = RegExp(r'_(\d+\.?\d*)_frame\d+\.bin$').firstMatch(filename);
    if (match != null) {
      return double.tryParse(match.group(1) ?? '0') ?? 0.0;
    }
    return 0.0;
  }

  // Number of concurrent downloads (for legacy individual file downloads)
  static const int _parallelDownloads = 20;

  /// Load frames from individual files (legacy format - multiple downloads)
  Future<void> _loadFromIndividualFiles() async {
    try {
      setState(() {
        _loadingStatus = 'Scanning recordings...';
      });

      List<_FileToDownload> allFilesToDownload = [];

      for (int i = 0; i < _gcsFolders.length; i++) {
        final folder = _gcsFolders[i];
        final path = folder['path'] as String;
        final batch = folder['batch'] as int? ?? 0;

        final ref = _storage.ref(path);
        final result = await ref.listAll();

        final binFiles = result.items.where((f) => f.name.endsWith('.bin')).toList();
        binFiles.sort((a, b) => a.name.compareTo(b.name));

        for (final file in binFiles) {
          allFilesToDownload.add(_FileToDownload(
            ref: file,
            recordingIndex: i,
            globalIndex: allFilesToDownload.length,
          ));
        }

        setState(() {
          _loadingStatus = 'Batch $batch: ${binFiles.length} files';
        });
      }

      final totalCount = allFilesToDownload.length;
      setState(() {
        _totalFiles = totalCount;
        _loadingStatus = 'Downloading $totalCount frames...';
      });

      // Prepare result arrays (pre-sized for correct ordering)
      final results = List<_DownloadResult?>.filled(totalCount, null);
      int completedCount = 0;

      // Download in parallel batches
      for (int batchStart = 0; batchStart < totalCount; batchStart += _parallelDownloads) {
        final batchEnd = (batchStart + _parallelDownloads).clamp(0, totalCount);
        final batch = allFilesToDownload.sublist(batchStart, batchEnd);

        // Download batch in parallel
        final futures = batch.map((file) async {
          try {
            final data = await file.ref.getData(10 * 1024 * 1024);
            if (data != null) {
              final decompressed = _decompressData(data);
              final vertices = _parseVertices(decompressed);
              return _DownloadResult(
                globalIndex: file.globalIndex,
                recordingIndex: file.recordingIndex,
                decompressed: decompressed,
                vertices: vertices,
              );
            }
          } catch (e) {
            debugPrint('Error downloading ${file.ref.name}: $e');
          }
          return null;
        }).toList();

        // Wait for batch to complete
        final batchResults = await Future.wait(futures);

        // Store results in correct order
        for (final result in batchResults) {
          if (result != null) {
            results[result.globalIndex] = result;
          }
        }

        completedCount += batch.length;
        setState(() {
          _downloadedFiles = completedCount;
          _loadingStatus = 'Downloading... $completedCount/$totalCount';
        });
      }

      // Convert results to frames (maintaining order)
      List<_ParsedFrame> frames = [];
      List<Uint8List> rawFramesForCache = [];
      List<int> recordingBoundaries = [];
      int lastRecordingIndex = -1;

      for (final result in results) {
        if (result != null) {
          // Track recording boundaries
          if (result.recordingIndex != lastRecordingIndex && lastRecordingIndex >= 0) {
            recordingBoundaries.add(frames.length);
          }
          lastRecordingIndex = result.recordingIndex;

          rawFramesForCache.add(result.decompressed);
          frames.add(_ParsedFrame(
            vertices: result.vertices,
            recordingIndex: result.recordingIndex,
          ));
        }
      }
      // Add final boundary
      recordingBoundaries.add(frames.length);

      // Save to cache in background
      if (rawFramesForCache.isNotEmpty) {
        _saveToCache(rawFramesForCache, recordingBoundaries);
      }

      setState(() {
        _allFrames = frames;
        _isLoading = false;
      });

      debugPrint('Loaded ${frames.length} frames total');
    } catch (e) {
      debugPrint('Error loading frames: $e');
      setState(() {
        _isLoading = false;
        _errorMessage = 'Failed to load: $e';
      });
    }
  }

  Uint8List _decompressData(Uint8List compressedData) {
    try {
      final archive = XZDecoder().decodeBytes(compressedData);
      return Uint8List.fromList(archive);
    } catch (e) {
      // Return raw data if decompression fails
      return compressedData;
    }
  }

  /// Convert int16 (2 bytes) to double using scale factor
  double _int16ToDouble(Uint8List bytes, int offset) {
    final value = bytes[offset] | (bytes[offset + 1] << 8);
    final signedValue = value > 32767 ? value - 65536 : value;
    const scale = 1000.0;
    return signedValue / scale;
  }

  List<List<double>> _parseVertices(Uint8List data) {
    final vertices = <List<double>>[];

    for (int i = 0; i < data.length - 5; i += 6) {
      try {
        final x = _int16ToDouble(data, i);
        final y = _int16ToDouble(data, i + 2);
        final z = _int16ToDouble(data, i + 4);

        if (x.isNaN || y.isNaN || z.isNaN ||
            x.isInfinite || y.isInfinite || z.isInfinite) {
          continue;
        }

        vertices.add([x, y, z]);
      } catch (e) {
        break;
      }
    }

    return vertices;
  }

  void _play() {
    if (_allFrames.isEmpty) return;

    setState(() {
      _isPlaying = true;
    });

    _startPlaybackTimer();
  }

  void _startPlaybackTimer() {
    _playbackTimer?.cancel();
    final interval = (1000 / _playbackSpeed).round();
    _playbackTimer = Timer.periodic(Duration(milliseconds: interval), (timer) {
      if (!_isPlaying) {
        timer.cancel();
        return;
      }

      setState(() {
        _currentFrameIndex = (_currentFrameIndex + 1) % _allFrames.length;
      });
    });
  }

  void _pause() {
    _playbackTimer?.cancel();
    setState(() {
      _isPlaying = false;
    });
  }

  void _seekTo(double value) {
    final index = (value * (_allFrames.length - 1)).round();
    setState(() {
      _currentFrameIndex = index.clamp(0, _allFrames.length - 1);
    });
  }

  int get _currentRecordingIndex {
    if (_allFrames.isEmpty || _currentFrameIndex >= _allFrames.length) return 0;
    return _allFrames[_currentFrameIndex].recordingIndex;
  }

  int get _currentBatchNumber {
    final recIdx = _currentRecordingIndex;
    if (recIdx >= 0 && recIdx < _gcsFolders.length) {
      return _gcsFolders[recIdx]['batch'] as int? ?? 0;
    }
    return 0;
  }

  double get _currentWeight {
    final recIdx = _currentRecordingIndex;
    if (recIdx >= 0 && recIdx < _recordingWeights.length) {
      return _recordingWeights[recIdx];
    }
    return 0.0;
  }

  @override
  Widget build(BuildContext context) {
    final exerciseName = widget.exercise['name'] ?? 'Exercise';

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(exerciseName),
            _buildRepsInfo(),
            Expanded(child: _buildViewer()),
            _buildControls(),
          ],
        ),
      ),
    );
  }

  Widget _buildRepsInfo() {
    final targetReps = widget.exercise['reps'] ?? 0;
    final currentReps = widget.exercise['current_reps'] ?? 0;
    final sets = widget.exercise['sets'] ?? 1;
    final isCompleted = widget.exercise['completed'] ?? false;

    final completionPercent = targetReps > 0
        ? ((currentReps / targetReps) * 100).clamp(0, 100).toInt()
        : 0;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isCompleted
              ? Colors.green.withAlpha(100)
              : const Color(0xFF0D4F48).withAlpha(100),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildRepsStat(
            'TARGET',
            '$targetReps',
            Icons.flag_outlined,
            const Color(0xFF0D4F48),
          ),
          Container(
            width: 1,
            height: 32,
            color: Colors.white24,
          ),
          _buildRepsStat(
            'COMPLETED',
            '$currentReps',
            Icons.check_circle_outline,
            isCompleted ? Colors.green : Colors.orange,
          ),
          Container(
            width: 1,
            height: 32,
            color: Colors.white24,
          ),
          _buildRepsStat(
            'SETS',
            '$sets',
            Icons.repeat,
            Colors.blueAccent,
          ),
          Container(
            width: 1,
            height: 32,
            color: Colors.white24,
          ),
          _buildRepsStat(
            'WEIGHT',
            _currentWeight > 0 ? '${_currentWeight}kg' : '-',
            Icons.fitness_center,
            Colors.purple,
          ),
          Container(
            width: 1,
            height: 32,
            color: Colors.white24,
          ),
          _buildRepsStat(
            'PROGRESS',
            '$completionPercent%',
            isCompleted ? Icons.emoji_events : Icons.trending_up,
            isCompleted ? Colors.green : Colors.orange,
          ),
        ],
      ),
    );
  }

  Widget _buildRepsStat(String label, String value, IconData icon, Color color) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            color: color,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(
            color: Colors.white54,
            fontSize: 9,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _buildHeader(String exerciseName) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.arrow_back, color: Colors.white),
          ),
          Expanded(
            child: Text(
              exerciseName.toString().replaceAll('_', ' ').toUpperCase(),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_loadedFromCache)
                Container(
                  margin: const EdgeInsets.only(right: 6),
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.green.withAlpha(50),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.green.withAlpha(100)),
                  ),
                  child: const Icon(Icons.cached, color: Colors.green, size: 14),
                ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0D4F48),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      'REC ${_currentRecordingIndex + 1}/${_gcsFolders.length}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _currentWeight > 0
                        ? 'Weight: ${_currentWeight}kg'
                        : 'Batch: $_currentBatchNumber',
                    style: const TextStyle(
                      color: Colors.white54,
                      fontSize: 9,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildViewer() {
    if (_isLoading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(color: Color(0xFF0D4F48)),
            const SizedBox(height: 16),
            Text(
              _loadingStatus,
              style: const TextStyle(color: Colors.white70),
              textAlign: TextAlign.center,
            ),
            if (_totalFiles > 0) ...[
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 48),
                child: LinearProgressIndicator(
                  value: _totalFiles > 0 ? _downloadedFiles / _totalFiles : 0,
                  backgroundColor: Colors.grey[800],
                  valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF0D4F48)),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '$_downloadedFiles / $_totalFiles frames',
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
            ],
          ],
        ),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 48),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                _errorMessage!,
                style: const TextStyle(color: Colors.red),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () {
                setState(() {
                  _isLoading = true;
                  _errorMessage = null;
                  _allFrames = [];
                });
                _loadAllFrames();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0D4F48),
              ),
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (_allFrames.isEmpty) {
      return const Center(
        child: Text('No frames available', style: TextStyle(color: Colors.white70)),
      );
    }

    final currentVertices = _allFrames[_currentFrameIndex].vertices;

    return GestureDetector(
      onScaleStart: (details) {
        _lastPanPosition = details.focalPoint;
      },
      onScaleUpdate: (details) {
        setState(() {
          final delta = details.focalPoint - _lastPanPosition;
          _rotationY += delta.dx * 0.01;
          _rotationX += delta.dy * 0.01;
          _lastPanPosition = details.focalPoint;
          _scale = (_scale * details.scale).clamp(0.5, 3.0);
        });
      },
      child: currentVertices.isNotEmpty
          ? CustomPaint(
              painter: _PoseMeshPainter(
                vertices: currentVertices,
                rotationX: _rotationX,
                rotationY: _rotationY,
                scale: _scale,
                flipVertical: _flipVertical,
                density: _density,
                pointColor: _colorPresets[_selectedColorIndex],
              ),
              size: Size.infinite,
            )
          : const Center(
              child: Text('No vertex data', style: TextStyle(color: Colors.white70)),
            ),
    );
  }

  Widget _buildControls() {
    final progress = _allFrames.isEmpty
        ? 0.0
        : _currentFrameIndex / (_allFrames.length - 1).clamp(1, double.infinity);

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: BoxDecoration(
        color: Colors.grey[900],
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Frame info and settings toggle
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Frame ${_currentFrameIndex + 1}',
                style: const TextStyle(color: Colors.white70, fontSize: 11),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${_allFrames.length} frames',
                    style: const TextStyle(color: Colors.white70, fontSize: 11),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () => setState(() => _showControls = !_showControls),
                    child: Icon(
                      _showControls ? Icons.expand_less : Icons.tune,
                      color: _showControls ? const Color(0xFF4ECDC4) : Colors.white54,
                      size: 20,
                    ),
                  ),
                ],
              ),
            ],
          ),

          // Progress slider
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: const Color(0xFF0D4F48),
              inactiveTrackColor: Colors.grey[700],
              thumbColor: const Color(0xFF0D4F48),
              trackHeight: 3,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
            ),
            child: Slider(
              value: progress.clamp(0.0, 1.0),
              onChanged: _allFrames.isEmpty ? null : _seekTo,
            ),
          ),

          // Playback buttons
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                onPressed: _allFrames.isEmpty
                    ? null
                    : () => setState(() => _currentFrameIndex = 0),
                icon: const Icon(Icons.skip_previous, color: Colors.white),
              ),
              IconButton(
                onPressed: _currentFrameIndex > 0
                    ? () => setState(() => _currentFrameIndex--)
                    : null,
                icon: const Icon(Icons.navigate_before, color: Colors.white),
              ),
              const SizedBox(width: 8),
              Container(
                decoration: const BoxDecoration(
                  color: Color(0xFF0D4F48),
                  shape: BoxShape.circle,
                ),
                child: IconButton(
                  onPressed: _allFrames.isEmpty
                      ? null
                      : (_isPlaying ? _pause : _play),
                  icon: Icon(
                    _isPlaying ? Icons.pause : Icons.play_arrow,
                    color: Colors.white,
                  ),
                  iconSize: 32,
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                onPressed: _currentFrameIndex < _allFrames.length - 1
                    ? () => setState(() => _currentFrameIndex++)
                    : null,
                icon: const Icon(Icons.navigate_next, color: Colors.white),
              ),
              IconButton(
                onPressed: _allFrames.isEmpty
                    ? null
                    : () => setState(() => _currentFrameIndex = _allFrames.length - 1),
                icon: const Icon(Icons.skip_next, color: Colors.white),
              ),
            ],
          ),

          // Advanced controls panel
          if (_showControls) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey[850],
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  // Tilt X
                  _buildSliderRow(
                    label: 'Tilt X',
                    value: _rotationX,
                    min: -math.pi / 2,
                    max: math.pi / 2,
                    displayValue: '${(_rotationX * 180 / math.pi).toStringAsFixed(0)}°',
                    onChanged: (v) => setState(() => _rotationX = v),
                  ),
                  const SizedBox(height: 8),

                  // Rotation Y
                  _buildSliderRow(
                    label: 'Rotate Y',
                    value: _rotationY % (2 * math.pi),
                    min: 0,
                    max: 2 * math.pi,
                    displayValue: '${((_rotationY * 180 / math.pi) % 360).toStringAsFixed(0)}°',
                    onChanged: (v) => setState(() => _rotationY = v),
                  ),
                  const SizedBox(height: 8),

                  // Playback speed
                  _buildSliderRow(
                    label: 'Speed',
                    value: _playbackSpeed,
                    min: 5,
                    max: 60,
                    displayValue: '${_playbackSpeed.toInt()} fps',
                    onChanged: (v) {
                      setState(() => _playbackSpeed = v);
                      if (_isPlaying) {
                        _startPlaybackTimer();
                      }
                    },
                  ),
                  const SizedBox(height: 8),

                  // Zoom
                  _buildSliderRow(
                    label: 'Zoom',
                    value: _scale,
                    min: 0.5,
                    max: 3.0,
                    displayValue: '${_scale.toStringAsFixed(1)}x',
                    onChanged: (v) => setState(() => _scale = v),
                  ),
                  const SizedBox(height: 8),

                  // Density
                  _buildSliderRow(
                    label: 'Density',
                    value: _density,
                    min: 0.1,
                    max: 1.0,
                    displayValue: '${(_density * 100).toInt()}%',
                    onChanged: (v) => setState(() => _density = v),
                  ),
                  const SizedBox(height: 12),

                  // Color selector
                  Row(
                    children: [
                      const SizedBox(
                        width: 60,
                        child: Text('Color', style: TextStyle(color: Colors.white70, fontSize: 11)),
                      ),
                      Expanded(
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: List.generate(_colorPresets.length, (index) {
                            final isSelected = _selectedColorIndex == index;
                            return GestureDetector(
                              onTap: () => setState(() => _selectedColorIndex = index),
                              child: Container(
                                width: 28,
                                height: 28,
                                decoration: BoxDecoration(
                                  color: _colorPresets[index],
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: isSelected ? Colors.white : Colors.transparent,
                                    width: 2,
                                  ),
                                  boxShadow: isSelected
                                      ? [BoxShadow(color: _colorPresets[index].withAlpha(150), blurRadius: 8)]
                                      : null,
                                ),
                                child: isSelected
                                    ? const Icon(Icons.check, color: Colors.black54, size: 16)
                                    : null,
                              ),
                            );
                          }),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Flip vertical toggle and reset
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          const Text('Flip', style: TextStyle(color: Colors.white70, fontSize: 12)),
                          const SizedBox(width: 8),
                          GestureDetector(
                            onTap: () => setState(() => _flipVertical = !_flipVertical),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: _flipVertical ? const Color(0xFF0D4F48) : Colors.grey[700],
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Text(
                                _flipVertical ? 'ON' : 'OFF',
                                style: const TextStyle(color: Colors.white, fontSize: 11),
                              ),
                            ),
                          ),
                        ],
                      ),
                      GestureDetector(
                        onTap: () {
                          setState(() {
                            _rotationX = -0.1;
                            _rotationY = 0.0;
                            _scale = 1.5;
                            _flipVertical = true;
                            _playbackSpeed = 5.0;
                            _density = 1.0;
                            _selectedColorIndex = 0;
                          });
                          if (_isPlaying) {
                            _startPlaybackTimer();
                          }
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.grey[700],
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: const Text(
                            'Reset',
                            style: TextStyle(color: Colors.white, fontSize: 11),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSliderRow({
    required String label,
    required double value,
    required double min,
    required double max,
    required String displayValue,
    required ValueChanged<double> onChanged,
  }) {
    return Row(
      children: [
        SizedBox(
          width: 60,
          child: Text(label, style: const TextStyle(color: Colors.white70, fontSize: 11)),
        ),
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: const Color(0xFF0D4F48),
              inactiveTrackColor: Colors.grey[700],
              thumbColor: const Color(0xFF0D4F48),
              trackHeight: 2,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
            ),
            child: Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              onChanged: onChanged,
            ),
          ),
        ),
        SizedBox(
          width: 45,
          child: Text(
            displayValue,
            style: const TextStyle(color: Colors.white54, fontSize: 10),
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }
}

class _ParsedFrame {
  final List<List<double>> vertices;
  final int recordingIndex;

  _ParsedFrame({
    required this.vertices,
    required this.recordingIndex,
  });
}

class _FileToDownload {
  final Reference ref;
  final int recordingIndex;
  final int globalIndex;

  _FileToDownload({
    required this.ref,
    required this.recordingIndex,
    required this.globalIndex,
  });
}

class _DownloadResult {
  final int globalIndex;
  final int recordingIndex;
  final Uint8List decompressed;
  final List<List<double>> vertices;

  _DownloadResult({
    required this.globalIndex,
    required this.recordingIndex,
    required this.decompressed,
    required this.vertices,
  });
}

class _PoseMeshPainter extends CustomPainter {
  final List<List<double>> vertices;
  final double rotationX;
  final double rotationY;
  final double scale;
  final bool flipVertical;
  final double density;
  final Color pointColor;

  _PoseMeshPainter({
    required this.vertices,
    required this.rotationX,
    required this.rotationY,
    required this.scale,
    required this.flipVertical,
    required this.density,
    required this.pointColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (vertices.isEmpty) return;

    final pointPaint = Paint()
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;

    final centerX = size.width / 2;
    final centerY = size.height / 2;
    final baseScale = size.height / 4 * scale;
    final flipFactor = flipVertical ? -1.0 : 1.0;

    // Calculate step based on density (1.0 = every vertex, 0.1 = every 10th)
    final step = (1.0 / density.clamp(0.1, 1.0)).round();

    final projectedPoints = <Offset>[];
    final depths = <double>[];

    for (int i = 0; i < vertices.length; i += step) {
      final vertex = vertices[i];
      if (vertex.length < 3) continue;

      double x = vertex[0];
      double y = vertex[1] * flipFactor;  // Apply flip
      double z = vertex[2];

      if (x.isNaN || y.isNaN || z.isNaN ||
          x.isInfinite || y.isInfinite || z.isInfinite) {
        continue;
      }

      // Rotate around Y axis
      final cosY = math.cos(rotationY);
      final sinY = math.sin(rotationY);
      final newX = x * cosY - z * sinY;
      final newZ = x * sinY + z * cosY;
      x = newX;
      z = newZ;

      // Rotate around X axis
      final cosX = math.cos(rotationX);
      final sinX = math.sin(rotationX);
      final newY = y * cosX - z * sinX;
      final newZ2 = y * sinX + z * cosX;
      y = newY;
      z = newZ2;

      final screenX = centerX + x * baseScale;
      final screenY = centerY - y * baseScale;

      if (screenX.isNaN || screenY.isNaN || z.isNaN) {
        continue;
      }

      projectedPoints.add(Offset(screenX, screenY));
      depths.add(z);
    }

    if (projectedPoints.isEmpty || depths.isEmpty) return;

    double minDepth = depths.reduce(math.min);
    double maxDepth = depths.reduce(math.max);
    double depthRange = maxDepth - minDepth;
    if (depthRange < 0.001 || depthRange.isNaN) depthRange = 1;

    for (int i = 0; i < projectedPoints.length; i++) {
      final point = projectedPoints[i];

      if (point.dx.isNaN || point.dy.isNaN) continue;

      final depthNorm = ((depths[i] - minDepth) / depthRange).clamp(0.0, 1.0);
      final alpha = (0.3 + 0.7 * (1 - depthNorm)).clamp(0.0, 1.0);
      final pointSize = (1.5 + 1.5 * (1 - depthNorm)).clamp(1.0, 3.0);

      // Create a darker version of the point color for depth effect
      final darkColor = Color.fromARGB(
        (pointColor.a * 255).round().clamp(0, 255),
        ((pointColor.r * 255) * 0.4).round().clamp(0, 255),
        ((pointColor.g * 255) * 0.4).round().clamp(0, 255),
        ((pointColor.b * 255) * 0.4).round().clamp(0, 255),
      );
      pointPaint.color = Color.lerp(
        darkColor,
        pointColor,
        1 - depthNorm,
      )!.withAlpha((alpha * 255).round());

      canvas.drawCircle(point, pointSize, pointPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _PoseMeshPainter oldDelegate) {
    return oldDelegate.vertices != vertices ||
           oldDelegate.rotationX != rotationX ||
           oldDelegate.rotationY != rotationY ||
           oldDelegate.scale != scale ||
           oldDelegate.flipVertical != flipVertical ||
           oldDelegate.density != density ||
           oldDelegate.pointColor != pointColor;
  }
}

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'workout_tracking_page.dart';

class SessionEmbeddingPage extends StatefulWidget {
  final String sessionId;
  final String sessionDocId;

  const SessionEmbeddingPage({
    super.key,
    required this.sessionId,
    required this.sessionDocId,
  });

  @override
  State<SessionEmbeddingPage> createState() => _SessionEmbeddingPageState();
}

class _SessionEmbeddingPageState extends State<SessionEmbeddingPage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  int embeddingStatus = 0;
  bool isLoading = true;
  Timer? _statusCheckTimer;

  @override
  void initState() {
    super.initState();
    _loadSessionStatus();
    _startStatusPolling();
  }

  @override
  void dispose() {
    _statusCheckTimer?.cancel();
    super.dispose();
  }

  void _startStatusPolling() {
    _statusCheckTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      if (embeddingStatus == 0) {
        _loadSessionStatus();
      } else {
        // Stop polling once embedding is complete
        timer.cancel();
      }
    });
  }

  Future<void> _loadSessionStatus() async {
    try {
      final sessionDoc = await _firestore
          .collection('sessions')
          .doc(widget.sessionDocId)
          .get();

      if (sessionDoc.exists) {
        final data = sessionDoc.data();
        setState(() {
          embeddingStatus = data?['embedding_status'] ?? 0;
          isLoading = false;
        });

        // Check if embedding_status is 1
        if (embeddingStatus == 1) {
          debugPrint('Embedding completed, navigating to workout tracking page');
          if (mounted) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (context) => WorkoutTrackingPage(
                  sessionId: widget.sessionId,
                  sessionDocId: widget.sessionDocId,
                ),
              ),
            );
          }
        }
      } else {
        setState(() {
          isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading session status: $e');
      setState(() {
        isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return Scaffold(
        backgroundColor: const Color(0xFF0D4F48),
        body: Center(
          child: Image.asset(
            'asset/images/loading1.gif',
            width: 200,
            height: 200,
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text(
          'User Recognition',
          style: TextStyle(color: Colors.white),
        ),
        backgroundColor: const Color(0xFF0D4F48),
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 0,
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const SizedBox(height: 40),

                    // Session ID
                    Text(
                      'Session ID: ${widget.sessionId}',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF0D4F48),
                      ),
                    ),

                    const SizedBox(height: 40),

                    // Embedding Status Icon with Animation
                    SizedBox(
                      width: 150,
                      height: 150,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          // Animated circular progress indicator for status 0
                          if (embeddingStatus == 0)
                            SizedBox(
                              width: 150,
                              height: 150,
                              child: CircularProgressIndicator(
                                strokeWidth: 3,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  Colors.orange.withOpacity(0.7),
                                ),
                              ),
                            ),
                          // Inner container with icon
                          Container(
                            width: 150,
                            height: 150,
                            decoration: BoxDecoration(
                              color: embeddingStatus == 0
                                  ? Colors.orange.withOpacity(0.1)
                                  : Colors.green.withOpacity(0.1),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: embeddingStatus == 0
                                    ? Colors.orange
                                    : Colors.green,
                                width: 3,
                              ),
                            ),
                            child: Icon(
                              embeddingStatus == 0
                                  ? Icons.person_search
                                  : Icons.check_circle,
                              size: 80,
                              color: embeddingStatus == 0
                                  ? Colors.orange
                                  : Colors.green,
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 40),

                    // Status Message
                    Text(
                      embeddingStatus == 0
                          ? 'Please Stand for Embedding Collection'
                          : 'Embedding Collection Complete',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: embeddingStatus == 0
                            ? Colors.orange.shade700
                            : Colors.green.shade700,
                      ),
                    ),

                    const SizedBox(height: 20),

                    // Instructions
                    if (embeddingStatus == 0)
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Instructions:',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF0D4F48),
                              ),
                            ),
                            const SizedBox(height: 12),
                            _buildInstruction(
                              '1. Stand in the designated lobby area',
                            ),
                            _buildInstruction(
                              '2. Face the camera directly',
                            ),
                            _buildInstruction(
                              '3. Ensure good lighting conditions',
                            ),
                            _buildInstruction(
                              '4. Wait for recognition to complete',
                            ),
                          ],
                        ),
                      ),

                    const SizedBox(height: 30),

                    // Refresh Button
                    if (embeddingStatus == 0)
                      ElevatedButton.icon(
                        onPressed: _loadSessionStatus,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Check Status'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF0D4F48),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 30,
                            vertical: 15,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),

            // Terms and Conditions Box
            Container(
              margin: const EdgeInsets.all(20),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: Colors.red.shade300,
                  width: 2,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.warning_amber_rounded,
                        color: Colors.red.shade700,
                        size: 24,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Important Terms',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.red.shade700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _buildTerm(
                    Icons.access_time,
                    'Session valid for 3 hours only',
                  ),
                  const SizedBox(height: 8),
                  _buildTerm(
                    Icons.person_off,
                    'No multiple users allowed during data collection',
                  ),
                  const SizedBox(height: 8),
                  _buildTerm(
                    Icons.checkroom,
                    'Session must be re-created if user changes clothes',
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInstruction(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.arrow_right,
            color: Color(0xFF0D4F48),
            size: 20,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 14,
                color: Colors.black87,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTerm(IconData icon, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          icon,
          color: Colors.red.shade700,
          size: 18,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 13,
              color: Colors.red.shade900,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}

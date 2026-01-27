import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:image_picker/image_picker.dart';
import '../services/gym_service.dart';
import '../models/gym.dart';

class GymVerificationPage extends StatefulWidget {
  const GymVerificationPage({super.key});

  @override
  State<GymVerificationPage> createState() => _GymVerificationPageState();
}

class _GymVerificationPageState extends State<GymVerificationPage> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final GymService _gymService = GymService();
  final TextEditingController _gymIdController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  bool _isLoading = false;
  bool _showScanner = false;
  MobileScannerController? _scannerController;
  List<Map<String, dynamic>> pendingGyms = [];
  bool isLoadingPending = true;
  File? _proofImage;
  final ImagePicker _imagePicker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _loadPendingGyms();
  }

  Future<void> _loadPendingGyms() async {
    final currentUser = _auth.currentUser;
    if (currentUser != null) {
      final allGyms = await _gymService.getUserGymsWithDetails(currentUser.uid);
      setState(() {
        pendingGyms = allGyms.where((gym) => gym['status'] == 2).toList();
        isLoadingPending = false;
      });
    }
  }

  @override
  void dispose() {
    _gymIdController.dispose();
    _scannerController?.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    try {
      final XFile? image = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 80,
      );

      if (image != null) {
        setState(() {
          _proofImage = File(image.path);
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error picking image: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _verifyAndSaveGym(String gymId) async {
    // Check if image is uploaded
    if (_proofImage == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please upload proof of membership (image)'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final currentUser = _auth.currentUser;
      if (currentUser == null) {
        throw 'User not authenticated';
      }

      // Validate gym ID
      final gym = await _gymService.validateGymId(gymId);

      if (gym == null) {
        throw 'Invalid gym ID. Please check and try again.';
      }

      // Upload proof image to Firebase Storage
      final imageUrl = await _gymService.uploadProofImage(
        currentUser.uid,
        gymId,
        _proofImage!,
      );

      // Save gym data locally
      await _gymService.saveGymDataLocally(gym);

      // Associate user with gym (saves to Firestore users collection with status 2 - pending)
      await _gymService.associateUserWithGym(
        currentUser.uid,
        gymId,
        proofImageUrl: imageUrl,
      );

      // Reload pending gyms to show the new one
      await _loadPendingGyms();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white),
                const SizedBox(width: 10),
                Expanded(
                  child: Text('Request sent to ${gym.name}. Waiting for admin approval.'),
                ),
              ],
            ),
            backgroundColor: Colors.orange,
            duration: const Duration(seconds: 3),
          ),
        );

        // Clear the text field and image
        _gymIdController.clear();
        setState(() {
          _proofImage = null;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString()),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _handleQRCodeScanned(BarcodeCapture capture) {
    final List<Barcode> barcodes = capture.barcodes;
    if (barcodes.isNotEmpty) {
      final String? code = barcodes.first.rawValue;
      if (code != null && code.isNotEmpty) {
        _scannerController?.stop();
        setState(() {
          _showScanner = false;
        });
        _verifyAndSaveGym(code);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D4F48),
      body: Stack(
        children: [
          SafeArea(
            child: _showScanner ? _buildScanner() : _buildManualEntry(),
          ),
          if (_isLoading) _buildLoader(),
        ],
      ),
    );
  }

  Widget _buildManualEntry() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const SizedBox(height: 40),
          Image.asset(
            'asset/images/smartan.jpg',
            width: MediaQuery.of(context).size.width * 0.5,
          ),
          const SizedBox(height: 40),
          const Text(
            'Verify Gym Membership',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            'Scan QR code or enter gym ID to continue',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: Colors.white70,
            ),
          ),
          const SizedBox(height: 30),

          // Pending Gyms Table
          if (pendingGyms.isNotEmpty) ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.15),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.orange, width: 2),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: const [
                      Icon(Icons.hourglass_empty, color: Colors.orange, size: 22),
                      SizedBox(width: 10),
                      Text(
                        'Pending Approval',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 15),
                  _buildPendingGymsTable(),
                ],
              ),
            ),
            const SizedBox(height: 30),
          ],

          const SizedBox(height: 20),

          // QR Code Scanner Button
          GestureDetector(
            onTap: () {
              setState(() {
                _showScanner = true;
                _scannerController = MobileScannerController();
              });
            },
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(40),
              decoration: BoxDecoration(
                color: const Color(0xFFA4FEB7),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                children: const [
                  Icon(
                    Icons.qr_code_scanner,
                    size: 80,
                    color: Color(0xFF0D4F48),
                  ),
                  SizedBox(height: 15),
                  Text(
                    'Scan QR Code',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF0D4F48),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 30),

          // Divider
          Row(
            children: const [
              Expanded(child: Divider(color: Colors.white30)),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 15),
                child: Text('OR', style: TextStyle(color: Colors.white70)),
              ),
              Expanded(child: Divider(color: Colors.white30)),
            ],
          ),
          const SizedBox(height: 30),

          // Manual Entry
          Form(
            key: _formKey,
            child: Column(
              children: [
                TextFormField(
                  controller: _gymIdController,
                  cursorColor: Colors.white,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'Enter Gym ID',
                    hintStyle: const TextStyle(color: Colors.white70, fontSize: 13),
                    prefixIcon: const Icon(Icons.fitness_center, color: Colors.white),
                    filled: false,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
                    enabledBorder: OutlineInputBorder(
                      borderSide: const BorderSide(color: Colors.white70),
                      borderRadius: BorderRadius.circular(10.0),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderSide: const BorderSide(color: Colors.white, width: 2),
                      borderRadius: BorderRadius.circular(10.0),
                    ),
                    errorBorder: OutlineInputBorder(
                      borderSide: const BorderSide(color: Colors.redAccent),
                      borderRadius: BorderRadius.circular(10.0),
                    ),
                    focusedErrorBorder: OutlineInputBorder(
                      borderSide: const BorderSide(color: Colors.redAccent, width: 2),
                      borderRadius: BorderRadius.circular(10.0),
                    ),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Gym ID is required';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 20),

                // Proof of Membership Section
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Upload Proof of Membership *',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                GestureDetector(
                  onTap: _pickImage,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: _proofImage != null ? const Color(0xFFA4FEB7) : Colors.white70,
                        width: 2,
                        style: BorderStyle.solid,
                      ),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: _proofImage != null
                        ? Column(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Image.file(
                                  _proofImage!,
                                  height: 150,
                                  width: double.infinity,
                                  fit: BoxFit.cover,
                                ),
                              ),
                              const SizedBox(height: 10),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: const [
                                  Icon(Icons.check_circle, color: Color(0xFFA4FEB7), size: 20),
                                  SizedBox(width: 8),
                                  Text(
                                    'Image uploaded',
                                    style: TextStyle(
                                      color: Color(0xFFA4FEB7),
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 5),
                              const Text(
                                'Tap to change',
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          )
                        : Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: const [
                              Icon(
                                Icons.cloud_upload_outlined,
                                color: Colors.white70,
                                size: 40,
                              ),
                              SizedBox(height: 10),
                              Text(
                                'Tap to upload image',
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 14,
                                ),
                              ),
                              SizedBox(height: 5),
                              Text(
                                'JPG, JPEG, PNG',
                                style: TextStyle(
                                  color: Colors.white54,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                  ),
                ),
                const SizedBox(height: 30),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: () {
                      if (_formKey.currentState!.validate()) {
                        _verifyAndSaveGym(_gymIdController.text.trim());
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: const Text(
                      'Verify & Continue',
                      style: TextStyle(
                        color: Color(0xFF0D4F48),
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScanner() {
    return Column(
      children: [
        // Header
        Padding(
          padding: const EdgeInsets.all(20.0),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white),
                onPressed: () {
                  _scannerController?.dispose();
                  setState(() {
                    _showScanner = false;
                    _scannerController = null;
                  });
                },
              ),
              const SizedBox(width: 10),
              const Text(
                'Scan Gym QR Code',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),

        // Scanner
        Expanded(
          child: Container(
            margin: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFFA4FEB7), width: 3),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(17),
              child: MobileScanner(
                controller: _scannerController,
                onDetect: _handleQRCodeScanned,
              ),
            ),
          ),
        ),

        // Instructions
        Padding(
          padding: const EdgeInsets.all(20.0),
          child: Container(
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Text(
              'Position the QR code within the frame to scan',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 14,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPendingGymsTable() {
    return Table(
      border: TableBorder.all(
        color: Colors.orange.withOpacity(0.3),
        width: 1,
        borderRadius: BorderRadius.circular(8),
      ),
      columnWidths: const {
        0: FlexColumnWidth(2),
        1: FlexColumnWidth(1),
      },
      children: [
        // Header row
        TableRow(
          decoration: BoxDecoration(
            color: Colors.orange.withOpacity(0.2),
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(8),
              topRight: Radius.circular(8),
            ),
          ),
          children: const [
            Padding(
              padding: EdgeInsets.all(12.0),
              child: Text(
                'Gym Name',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.all(12.0),
              child: Text(
                'Status',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ),
        // Data rows
        ...pendingGyms.map((gymData) {
          final gym = gymData['gym'];
          return TableRow(
            children: [
              Padding(
                padding: const EdgeInsets.all(12.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      gym.name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      gym.address,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 11,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(12.0),
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.orange,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text(
                      'Pending',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        }),
      ],
    );
  }

  Widget _buildLoader() {
    return Container(
      color: Colors.black54,
      child: Center(
        child: Image.asset(
          'asset/images/loading1.gif',
          width: 200,
          height: 200,
        ),
      ),
    );
  }
}

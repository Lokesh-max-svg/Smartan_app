import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../controllers/user_info_controller.dart';

class UserInfoPage extends StatefulWidget {
  const UserInfoPage({super.key});

  @override
  State<UserInfoPage> createState() => _UserInfoPageState();
}

class _UserInfoPageState extends State<UserInfoPage> {
  final _formKey = GlobalKey<FormState>();
  final healthIssuesController = TextEditingController();
  int _currentStep = 0;
  int _selectedHeight = 170;
  int _selectedWeight = 70;

  static const _teal = Color(0xFF0D4F48);
  static const _accent = Color(0xFF4EEADB);

  @override
  void dispose() {
    healthIssuesController.dispose();
    super.dispose();
  }

  void _goNext() => setState(() => _currentStep++);
  void _goBack() => setState(() => _currentStep--);

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => UserInfoController(),
      child: Consumer<UserInfoController>(
        builder: (context, controller, _) {
          return Scaffold(
            body: Stack(
              children: [
                Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFF0A3D38), _teal, Color(0xFF0E5C54)],
                    ),
                  ),
                ),
                Positioned(
                  top: -80,
                  right: -60,
                  child: Container(
                    width: 200,
                    height: 200,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withValues(alpha: 0.04),
                    ),
                  ),
                ),
                Positioned(
                  bottom: -40,
                  left: -40,
                  child: Container(
                    width: 160,
                    height: 160,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withValues(alpha: 0.03),
                    ),
                  ),
                ),
                _buildBody(context, controller),
                if (controller.isLoading) _buildLoader(),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildBody(BuildContext context, UserInfoController controller) {
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: SafeArea(
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
                child: Column(
                  children: [
                    // 4-step progress bar
                    Row(
                      children: List.generate(4, (i) {
                        final isActive = i <= _currentStep;
                        final isCurrent = i == _currentStep;
                        return Expanded(
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 300),
                            height: isCurrent ? 4 : 3,
                            margin: EdgeInsets.only(right: i < 3 ? 6 : 0),
                            decoration: BoxDecoration(
                              color: isActive
                                  ? _accent
                                  : Colors.white.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        );
                      }),
                    ),
                    const SizedBox(height: 32),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 250),
                      child: _buildTitle(),
                    ),
                  ],
                ),
              ),
              // Step content
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  child: _buildStepContent(controller),
                ),
              ),
              // Bottom buttons
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
                child: _buildBottomButtons(controller),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTitle() {
    final titles = [
      {"title": "How Tall Are You?", "sub": "Set your height for accurate tracking"},
      {"title": "What's Your Weight?", "sub": "We'll track your progress over time"},
      {"title": "Your Fitness Level?", "sub": "This helps us set the right intensity"},
      {"title": "Any Health Concerns?", "sub": "Your safety is our priority"},
    ];
    final data = titles[_currentStep];
    return Column(
      key: ValueKey(_currentStep),
      children: [
        Text(
          data["title"]!,
          style: const TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w700,
            color: Colors.white,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          data["sub"]!,
          style: TextStyle(
            fontSize: 14,
            color: Colors.white.withValues(alpha: 0.5),
          ),
        ),
      ],
    );
  }

  Widget _buildStepContent(UserInfoController controller) {
    switch (_currentStep) {
      case 0:
        return _buildHeightStep(key: const ValueKey(0));
      case 1:
        return _buildWeightStep(key: const ValueKey(1));
      case 2:
        return _buildExpertiseStep(controller, key: const ValueKey(2));
      case 3:
        return _buildHealthStep(controller, key: const ValueKey(3));
      default:
        return const SizedBox.shrink();
    }
  }

  // ── Step 1: Height ──

  Widget _buildHeightStep({Key? key}) {
    return Column(
      key: key,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _buildValueDisplay(_selectedHeight, "cm"),
        const SizedBox(height: 48),
        _RulerPicker(
          minValue: 100,
          maxValue: 250,
          initialValue: _selectedHeight,
          onChanged: (v) => setState(() => _selectedHeight = v),
        ),
      ],
    );
  }

  // ── Step 2: Weight ──

  Widget _buildWeightStep({Key? key}) {
    return Column(
      key: key,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _buildValueDisplay(_selectedWeight, "kg"),
        const SizedBox(height: 48),
        _RulerPicker(
          minValue: 30,
          maxValue: 200,
          initialValue: _selectedWeight,
          onChanged: (v) => setState(() => _selectedWeight = v),
        ),
      ],
    );
  }

  Widget _buildValueDisplay(int value, String unit) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 20),
      decoration: BoxDecoration(
        color: _accent.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text(
            '$value',
            style: const TextStyle(
              fontSize: 76,
              fontWeight: FontWeight.w800,
              color: Colors.white,
              height: 1.1,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            unit,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w600,
              color: Colors.white.withValues(alpha: 0.35),
            ),
          ),
        ],
      ),
    );
  }

  // ── Step 3: Expertise ──

  Widget _buildExpertiseStep(UserInfoController controller, {Key? key}) {
    final data = [
      {'level': 'Novice', 'emoji': '🌱', 'detail': 'Learning proper form & basics'},
      {'level': 'Intermediate', 'emoji': '💪', 'detail': 'Comfortable with most exercises'},
      {'level': 'Strong', 'emoji': '🔥', 'detail': 'Ready for intense workouts'},
    ];

    return SingleChildScrollView(
      key: key,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      child: Column(
        children: data.map((item) {
          final level = item['level'] as String;
          final isSelected = controller.selectedExpertise == level;
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: GestureDetector(
              onTap: () => controller.setExpertise(level),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: isSelected
                      ? _accent.withValues(alpha: 0.12)
                      : Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isSelected ? _accent : Colors.transparent,
                    width: 1.5,
                  ),
                ),
                child: Row(
                  children: [
                    Text(item['emoji'] as String,
                        style: const TextStyle(fontSize: 32)),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            level,
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                              color: isSelected ? _accent : Colors.white,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            item['detail'] as String,
                            style: TextStyle(
                              fontSize: 13,
                              color: isSelected
                                  ? _accent.withValues(alpha: 0.7)
                                  : Colors.white.withValues(alpha: 0.4),
                            ),
                          ),
                        ],
                      ),
                    ),
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isSelected ? _accent : Colors.transparent,
                        border: Border.all(
                          color: isSelected ? _accent : Colors.white30,
                          width: 2,
                        ),
                      ),
                      child: isSelected
                          ? const Icon(Icons.check, size: 14, color: _teal)
                          : null,
                    ),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  // ── Step 4: Health ──

  Widget _buildHealthStep(UserInfoController controller, {Key? key}) {
    return SingleChildScrollView(
      key: key,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _healthOption(
                  emoji: "✅",
                  label: "All good",
                  subtitle: "No issues",
                  isSelected: !controller.hasHealthIssues,
                  onTap: () => controller.setHealthIssues(false),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _healthOption(
                  emoji: "⚕️",
                  label: "Have concerns",
                  subtitle: "Tell us more",
                  isSelected: controller.hasHealthIssues,
                  onTap: () => controller.setHealthIssues(true),
                ),
              ),
            ],
          ),
          if (controller.hasHealthIssues) ...[
            const SizedBox(height: 20),
            Container(
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(16),
              ),
              child: TextFormField(
                controller: healthIssuesController,
                maxLines: 4,
                cursorColor: _accent,
                style: const TextStyle(fontSize: 15, color: Colors.white),
                validator: (value) {
                  if (controller.hasHealthIssues &&
                      (value == null || value.trim().isEmpty)) {
                    return 'Please describe your health concerns';
                  }
                  return null;
                },
                decoration: InputDecoration(
                  hintText:
                      "Describe any injuries, conditions,\nor limitations...",
                  hintStyle: TextStyle(
                    color: Colors.white.withValues(alpha: 0.25),
                    fontSize: 14,
                    height: 1.5,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.all(20),
                  errorStyle: const TextStyle(color: Color(0xFFFF8A80)),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _healthOption({
    required String emoji,
    required String label,
    required String subtitle,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
        decoration: BoxDecoration(
          color: isSelected
              ? _accent.withValues(alpha: 0.12)
              : Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? _accent : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: Column(
          children: [
            Text(emoji, style: const TextStyle(fontSize: 32)),
            const SizedBox(height: 12),
            Text(
              label,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: isSelected ? _accent : Colors.white,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 12,
                color: isSelected
                    ? _accent.withValues(alpha: 0.6)
                    : Colors.white.withValues(alpha: 0.35),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Bottom Buttons ──

  Widget _buildBottomButtons(UserInfoController controller) {
    return Row(
      children: [
        if (_currentStep > 0) ...[
          GestureDetector(
            onTap: _goBack,
            child: Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(
                Icons.arrow_back_rounded,
                color: Colors.white70,
                size: 22,
              ),
            ),
          ),
          const SizedBox(width: 12),
        ],
        Expanded(
          child: GestureDetector(
            onTap: () => _handleAction(controller),
            child: Container(
              height: 52,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Center(
                child: Text(
                  _currentStep == 3 ? "Complete Setup" : "Continue",
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: _teal,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _handleAction(UserInfoController controller) async {
    if (_currentStep < 3) {
      _goNext();
    } else {
      // Get userId from SharedPreferences (saved by backend login)
      final prefs = await SharedPreferences.getInstance();
      final userId = prefs.getString('user_id');
      
      if (userId != null && userId.isNotEmpty) {
        // Only send data to backend when Complete Setup is clicked
        controller.saveUserInfo(
          context: context,
          formKey: _formKey,
          userId: userId,
          height: _selectedHeight.toDouble(),
          weight: _selectedWeight.toDouble(),
          healthIssuesDescription: controller.hasHealthIssues
              ? healthIssuesController.text
              : null,
        );
      } else {
        // Show error if userId is not found
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Error: User ID not found. Please log in again.'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
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

// ── Horizontal Ruler Picker ──

class _RulerPicker extends StatefulWidget {
  final int minValue;
  final int maxValue;
  final int initialValue;
  final ValueChanged<int> onChanged;

  const _RulerPicker({
    required this.minValue,
    required this.maxValue,
    required this.initialValue,
    required this.onChanged,
  });

  @override
  State<_RulerPicker> createState() => _RulerPickerState();
}

class _RulerPickerState extends State<_RulerPicker> {
  late ScrollController _scrollController;
  late int _selectedValue;
  static const double _itemWidth = 14.0;
  static const _teal = Color(0xFF0D4F48);
  static const _accent = Color(0xFF4EEADB);

  @override
  void initState() {
    super.initState();
    _selectedValue = widget.initialValue;
    _scrollController = ScrollController(
      initialScrollOffset:
          (widget.initialValue - widget.minValue) * _itemWidth,
    );
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScrollUpdate() {
    final offset = _scrollController.offset;
    final index =
        (offset / _itemWidth).round().clamp(0, widget.maxValue - widget.minValue);
    final newValue = widget.minValue + index;
    if (newValue != _selectedValue) {
      _selectedValue = newValue;
      widget.onChanged(newValue);
      HapticFeedback.selectionClick();
    }
  }

  void _snapToValue() {
    final targetOffset =
        (_selectedValue - widget.minValue) * _itemWidth;
    _scrollController.animateTo(
      targetOffset.toDouble(),
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final halfWidth = screenWidth / 2;

    return SizedBox(
      height: 90,
      child: Stack(
        alignment: Alignment.bottomCenter,
        children: [
          // Ruler ticks
          NotificationListener<ScrollNotification>(
            onNotification: (notification) {
              if (notification is ScrollUpdateNotification) {
                _onScrollUpdate();
              } else if (notification is ScrollEndNotification) {
                _snapToValue();
              }
              return true;
            },
            child: ListView.builder(
              controller: _scrollController,
              scrollDirection: Axis.horizontal,
              padding: EdgeInsets.symmetric(horizontal: halfWidth),
              itemCount: widget.maxValue - widget.minValue + 1,
              itemBuilder: (context, index) {
                final value = widget.minValue + index;
                final isMajor = value % 10 == 0;
                final isMid = value % 5 == 0 && !isMajor;
                return SizedBox(
                  width: _itemWidth,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      if (isMajor)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Text(
                            '$value',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.white.withValues(alpha: 0.4),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        )
                      else
                        const Spacer(),
                      Container(
                        width: isMajor ? 2 : 1,
                        height: isMajor ? 40 : isMid ? 26 : 14,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(
                            alpha: isMajor ? 0.45 : isMid ? 0.25 : 0.15,
                          ),
                          borderRadius: BorderRadius.circular(1),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          // Left fade
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            width: 50,
            child: IgnorePointer(
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [_teal, _teal.withValues(alpha: 0)],
                  ),
                ),
              ),
            ),
          ),
          // Right fade
          Positioned(
            right: 0,
            top: 0,
            bottom: 0,
            width: 50,
            child: IgnorePointer(
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [_teal.withValues(alpha: 0), _teal],
                  ),
                ),
              ),
            ),
          ),
          // Center indicator line
          Positioned(
            bottom: 0,
            child: Container(
              width: 3,
              height: 56,
              decoration: BoxDecoration(
                color: _accent,
                borderRadius: BorderRadius.circular(2),
                boxShadow: [
                  BoxShadow(
                    color: _accent.withValues(alpha: 0.4),
                    blurRadius: 10,
                    spreadRadius: 1,
                  ),
                ],
              ),
            ),
          ),
          // Triangle indicator
          Positioned(
            bottom: 58,
            child: CustomPaint(
              size: const Size(14, 8),
              painter: _TrianglePainter(color: _accent),
            ),
          ),
        ],
      ),
    );
  }
}

class _TrianglePainter extends CustomPainter {
  final Color color;
  _TrianglePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width / 2, size.height)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

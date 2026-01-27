import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../controllers/user_info_controller.dart';

class UserInfoPage extends StatefulWidget {
  const UserInfoPage({super.key});

  @override
  State<UserInfoPage> createState() => _UserInfoPageState();
}

class _UserInfoPageState extends State<UserInfoPage> {
  final _formKey = GlobalKey<FormState>();
  final heightController = TextEditingController();
  final weightController = TextEditingController();
  final healthIssuesController = TextEditingController();

  @override
  void dispose() {
    heightController.dispose();
    weightController.dispose();
    healthIssuesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => UserInfoController(),
      child: Consumer<UserInfoController>(
        builder: (context, controller, _) {
          return Scaffold(
            backgroundColor: const Color(0xFF0D4F48),
            body: Stack(
              children: [
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
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                _logo(),
                const SizedBox(height: 20),
                const Text(
                  "Complete Your Profile",
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  "Tell us about yourself",
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.white70,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 40),

                // Height Input
                _input(
                  controller: heightController,
                  hint: "Height (cm)",
                  icon: Icons.height,
                  keyboardType: TextInputType.number,
                  validator: (value) {
                    if (value == null || value.isEmpty) return 'Height required';
                    final height = double.tryParse(value);
                    if (height == null || height <= 0) {
                      return 'Enter a valid height';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 20),

                // Weight Input
                _input(
                  controller: weightController,
                  hint: "Weight (kg)",
                  icon: Icons.monitor_weight,
                  keyboardType: TextInputType.number,
                  validator: (value) {
                    if (value == null || value.isEmpty) return 'Weight required';
                    final weight = double.tryParse(value);
                    if (weight == null || weight <= 0) {
                      return 'Enter a valid weight';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 30),

                // Gym Expertise
                _expertiseSection(controller),
                const SizedBox(height: 30),

                // Health Issues Section
                _healthIssuesSection(controller),

                if (controller.hasHealthIssues) ...[
                  const SizedBox(height: 20),
                  _input(
                    controller: healthIssuesController,
                    hint: "Describe your health issues",
                    icon: Icons.medical_services,
                    maxLines: 4,
                    validator: (value) {
                      if (controller.hasHealthIssues &&
                          (value == null || value.trim().isEmpty)) {
                        return 'Please describe your health issues';
                      }
                      return null;
                    },
                  ),
                ],

                const SizedBox(height: 40),
                _submitButton(controller),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _logo() {
    return Image.asset(
      'asset/images/smartan.jpg',
      width: MediaQuery.of(context).size.width * 0.4,
    );
  }

  Widget _input({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    String? Function(String?)? validator,
    TextInputType keyboardType = TextInputType.text,
    int maxLines = 1,
  }) {
    return TextFormField(
      controller: controller,
      cursorColor: Colors.white,
      keyboardType: keyboardType,
      maxLines: maxLines,
      style: const TextStyle(color: Colors.white),
      validator: validator,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Colors.white70, fontSize: 13),
        prefixIcon: Icon(icon, color: Colors.white),
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
    );
  }

  Widget _expertiseSection(UserInfoController controller) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "Gym Expertise",
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 15),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: controller.expertiseLevels.map((level) {
            final isSelected = controller.selectedExpertise == level;
            return GestureDetector(
              onTap: () => controller.setExpertise(level),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: isSelected ? Colors.white : Colors.transparent,
                  border: Border.all(
                    color: Colors.white,
                    width: 2,
                  ),
                  borderRadius: BorderRadius.circular(25),
                ),
                child: Text(
                  level,
                  style: TextStyle(
                    color: isSelected ? const Color(0xFF0D4F48) : Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _healthIssuesSection(UserInfoController controller) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "Any Health Issues?",
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 15),
        Row(
          children: [
            Expanded(
              child: GestureDetector(
                onTap: () => controller.setHealthIssues(false),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    color: !controller.hasHealthIssues
                        ? Colors.white
                        : Colors.transparent,
                    border: Border.all(
                      color: Colors.white,
                      width: 2,
                    ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Center(
                    child: Text(
                      "No",
                      style: TextStyle(
                        color: !controller.hasHealthIssues
                            ? const Color(0xFF0D4F48)
                            : Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 15),
            Expanded(
              child: GestureDetector(
                onTap: () => controller.setHealthIssues(true),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    color: controller.hasHealthIssues
                        ? Colors.white
                        : Colors.transparent,
                    border: Border.all(
                      color: Colors.white,
                      width: 2,
                    ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Center(
                    child: Text(
                      "Yes",
                      style: TextStyle(
                        color: controller.hasHealthIssues
                            ? const Color(0xFF0D4F48)
                            : Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _submitButton(UserInfoController controller) {
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: ElevatedButton(
        onPressed: () {
          final user = FirebaseAuth.instance.currentUser;
          if (user != null) {
            controller.saveUserInfo(
              context: context,
              formKey: _formKey,
              userId: user.uid,
              height: double.tryParse(heightController.text) ?? 0,
              weight: double.tryParse(weightController.text) ?? 0,
              healthIssuesDescription: controller.hasHealthIssues
                  ? healthIssuesController.text
                  : null,
            );
          }
        },
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
        child: const Text(
          "Complete Setup",
          style: TextStyle(
            color: Colors.black,
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
      ),
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

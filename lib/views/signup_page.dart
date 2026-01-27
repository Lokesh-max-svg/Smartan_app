import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../controllers/signup_controller.dart';

class SignupPage extends StatefulWidget {
  const SignupPage({super.key});

  @override
  State<SignupPage> createState() => _SignupPageState();
}

class _SignupPageState extends State<SignupPage> {
  final _formKey = GlobalKey<FormState>();
  final emailController = TextEditingController();
  final nameController = TextEditingController();
  final passwordController = TextEditingController();
  final rePasswordController = TextEditingController();

  @override
  void dispose() {
    emailController.dispose();
    nameController.dispose();
    passwordController.dispose();
    rePasswordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => SignupController(),
      child: Consumer<SignupController>(
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

  Widget _buildBody(BuildContext context, SignupController controller) {
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
                  "Welcome Back!",
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.white,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 5),
                const Text(
                  "Let's begin the fitness journey",
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.white,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 40),

                _input(
                  controller: emailController,
                  hint: "Email",
                  icon: Icons.email,
                  validator: (value) {
                    if (value == null || value.isEmpty) return 'Email required';
                    if (!RegExp(r'^[^@]+@[^@]+\.[^@]+').hasMatch(value)) {
                      return 'Enter a valid email';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 20),

                _input(
                  controller: nameController,
                  hint: "Username",
                  icon: Icons.person,
                  validator: (value) {
                    if (value == null || value.isEmpty) return 'Username required';
                    return null;
                  },
                ),
                const SizedBox(height: 20),

                _input(
                  controller: passwordController,
                  hint: "Password",
                  icon: Icons.lock,
                  obscure: true,
                  validator: (value) {
                    if (value == null || value.isEmpty) return 'Password required';
                    if (value.length < 6) return 'Password must be at least 6 characters';
                    return null;
                  },
                ),
                const SizedBox(height: 20),

                _input(
                  controller: rePasswordController,
                  hint: "Re-Enter Password",
                  icon: Icons.lock,
                  obscure: true,
                  validator: (value) {
                    if (value != passwordController.text) return 'Passwords do not match';
                    return null;
                  },
                ),

                const SizedBox(height: 40),
                _signupButton(controller),

                const SizedBox(height: 30),
                _divider(),

                const SizedBox(height: 20),
                _googleButton(controller),

                const SizedBox(height: 40),
                _loginText(),
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
      width: MediaQuery.of(context).size.width * 0.6,
    );
  }

  Widget _input({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    String? Function(String?)? validator,
    bool obscure = false,
  }) {
    return TextFormField(
      controller: controller,
      cursorColor: Colors.white,
      obscureText: obscure,
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

  Widget _signupButton(SignupController controller) {
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: ElevatedButton(
        onPressed: () => controller.signUp(
          context: context,
          formKey: _formKey,
          email: emailController.text,
          username: nameController.text,
          password: passwordController.text,
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
        child: const Text(
          "Create Account",
          style: TextStyle(
            color: Colors.black,
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
      ),
    );
  }

  Widget _divider() {
    return Row(
      children: const [
        Expanded(child: Divider(color: Colors.white30)),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 10),
          child: Text("OR", style: TextStyle(color: Colors.white70)),
        ),
        Expanded(child: Divider(color: Colors.white30)),
      ],
    );
  }

  Widget _googleButton(SignupController controller) {
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: OutlinedButton.icon(
        onPressed: () => controller.signUpWithGoogle(context),
        icon: Image.asset(
          'asset/images/google.png',
          width: 20,
        ),
        label: const Text(
          "Sign up with Google",
          style: TextStyle(color: Colors.white),
        ),
        style: OutlinedButton.styleFrom(
          side: const BorderSide(color: Colors.white),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
    );
  }

  Widget _loginText() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Text(
          "Already an Existing user - ",
          style: TextStyle(color: Colors.white70),
        ),
        GestureDetector(
          onTap: () {
            Navigator.pushReplacementNamed(context, '/login');
          },
          child: const Text(
            "Log In",
            style: TextStyle(
              color: Color(0xFFA4FEB7),
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
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

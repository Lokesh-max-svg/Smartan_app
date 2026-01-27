import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../controllers/login_controller.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final emailController = TextEditingController();
  final passwordController = TextEditingController();



  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => LoginController(),
      child: Consumer<LoginController>(
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

  Widget _buildBody(BuildContext context, LoginController controller) {
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: SizedBox(
            height: MediaQuery.of(context).size.height -
                MediaQuery.of(context).padding.top,
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _logo(),
                  const SizedBox(height: 20),
                  const Text(
                    "Welcome Back! Login to continue",
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      letterSpacing: 1
                    ),
                  ),
                  const SizedBox(height: 40),

                  _input(
                    controller: emailController,
                    hint: "Email",
                    icon: Icons.email,
                  ),
                  const SizedBox(height: 20),
                  _input(
                    controller: passwordController,
                    hint: "Password",
                    icon: Icons.lock,
                    obscure: true,
                  ),

                  const SizedBox(height: 10),
                  _forgotPassword(),

                  const SizedBox(height: 30),
                  _loginButton(controller),

                  const SizedBox(height: 30),
                  _divider(),

                  const SizedBox(height: 20),
                _googleButton(controller), // pass the controller directly
                  const SizedBox(height: 30),
                  _signupText(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _logo() {
    return Image.asset(
      'asset/images/smartan.jpg',
      width: 250,
    );
  }

  Widget _input({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    bool obscure = false,
  }) {
    return TextFormField(
      controller: controller,
      cursorColor: Colors.white,
      obscureText: obscure,
      style: const TextStyle(color: Colors.white),
      validator: (v) => v == null || v.isEmpty ? '$hint required' : null,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Colors.white70),
        prefixIcon: Icon(icon, color: Colors.white),

        // 🔑 IMPORTANT PART
        enabledBorder: const UnderlineInputBorder(
          borderSide: BorderSide(color: Colors.white70, width: 1),
        ),
        focusedBorder: const UnderlineInputBorder(
          borderSide: BorderSide(color: Colors.white, width: 2),
        ),
        errorBorder: const UnderlineInputBorder(
          borderSide: BorderSide(color: Colors.redAccent),
        ),
        focusedErrorBorder: const UnderlineInputBorder(
          borderSide: BorderSide(color: Colors.redAccent, width: 2),
        ),
      ),
    );
  }


  Widget _loginButton(LoginController controller) {
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: ElevatedButton(
        onPressed: () => controller.login(
          context: context,
          formKey: _formKey,
          email: emailController.text,
          password: passwordController.text,
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
        child: const Text(
          "Login",
          style: TextStyle(
            color: Colors.black,
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
      ),
    );
  }

  Widget _forgotPassword() {
    return Align(
      alignment: Alignment.centerRight,
      child: TextButton(
        onPressed: () {
          // Navigate to ForgetPage
        },
        child: const Text(
          "Forgot Password?",
          style: TextStyle(color: Colors.white70),
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



  Widget _googleButton(LoginController controller) {
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: OutlinedButton.icon(
        onPressed: () => controller.signInWithGoogle(context),
        icon: Image.asset(
          'asset/images/google.png',
          width: 20,
        ),
        label: const Text(
          "Sign in with Google",
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






  Widget _signupText() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Text("Don't have an account? ",
            style: TextStyle(color: Colors.white70)),
        GestureDetector(
          onTap: () {
            Navigator.pushNamed(context, '/signup');
          },
          child: const Text(
            "Sign up",
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
      child: const Center(
        child: CircularProgressIndicator(color: Colors.white),
      ),
    );
  }
}

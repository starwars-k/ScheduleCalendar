import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:calendar_frontend/initialSetupPage.dart';

class LoginPage extends StatefulWidget {
  final String backendBaseUrl;
  final void Function(String token, String username, UserAppSettings settings, bool isRegisterMode) onLoginSuccess;
  const LoginPage({
    super.key,
    required this.backendBaseUrl,
    required this.onLoginSuccess,
  });

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _isRegisterMode = false;
  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void dispose(){
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _sumbmitAuth() async {
    if(_isSubmitting) return; // Prevent multiple submissionss
    final username = _usernameController.text.trim();
    final password = _passwordController.text;

    if(username.isEmpty || password.isEmpty){
      setState(() {
        _errorMessage = 'Please enter both username and password.';
      });
      return;
    }

    FocusScope.of(context).unfocus(); // Dismiss the keyboard

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    final endpoint = _isRegisterMode ? '/api/auth/register' : '/api/auth/login';
    final uri = Uri.parse('${widget.backendBaseUrl}$endpoint');

    try{
      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'username': username, 'password': password}),
      );
      Map<String, dynamic> data = {};
      if (response.body.isNotEmpty) {
        try {
          final decoded = jsonDecode(response.body);
          if (decoded is Map<String, dynamic>) {
            data = decoded;
          }
        } catch (_) {}
      }
      if(response.statusCode == 200 || response.statusCode == 201){
        final token = data['token'] as String;
        final username = data['username'] as String;
        final settings = UserAppSettings.fromJson(data);

        // Store the token and username in SharedPreferences
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('auth_token', token);
        await prefs.setString('auth_username', username);
        if (data['userId'] != null) {
          await prefs.setString('auth_userId', data['userId'].toString());
        }
        await settings.saveToCache();

        if(mounted){
          widget.onLoginSuccess(token, username, settings, _isRegisterMode);
        }
      }else{
        setState(() {
          _errorMessage = data['error']?.toString() ?? 'Server error (${response.statusCode}). Please try again.';
        });
      }
    }catch(e){
      setState(() {
        _errorMessage = 'Network error. Please check your connection and try again.';
      });
    }finally{
      if(mounted){
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }
  @override
  Widget build(BuildContext context) {
    const Color appleRed = Color(0xFFFF3B30);
    const Color appleGroupedBg = Color(0xFFF2F2F7);
    const Color appleHairline = Color(0xFFE5E5EA);
    const Color appleSecondaryLabel = Color(0xFF8E8E93);

    return Scaffold(
      backgroundColor: appleGroupedBg,
      body: AbsorbPointer(
        absorbing: _isSubmitting,
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 400),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Apple Calendar Icon Badge
                    Center(
                      child: Container(
                        width: 72,
                        height: 72,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(18),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.08),
                              blurRadius: 16,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              DateTime.now().month.toString(),
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: appleRed,
                              ),
                            ),
                            Text(
                              DateTime.now().day.toString(),
                              style: const TextStyle(
                                fontSize: 30,
                                fontWeight: FontWeight.w300,
                                height: 1.05,
                                color: Colors.black,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      _isRegisterMode ? 'Create Account' : 'Schedule Calendar',
                      style: const TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.5,
                        color: Colors.black,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _isRegisterMode
                          ? 'Create an account to sync your calendar'
                          : 'Sign in to access your schedule',
                      style: const TextStyle(fontSize: 14, color: appleSecondaryLabel),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    CupertinoSlidingSegmentedControl<bool>(
                      groupValue: _isRegisterMode,
                      children: const {
                        false: Padding(
                          padding: EdgeInsets.symmetric(vertical: 7),
                          child: Text('Sign In', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                        ),
                        true: Padding(
                          padding: EdgeInsets.symmetric(vertical: 7),
                          child: Text('Create Account', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                        ),
                      },
                      onValueChanged: (val) {
                        if (val != null) {
                          setState(() {
                            _isRegisterMode = val;
                            _errorMessage = null;
                            _passwordController.clear();
                          });
                        }
                      },
                    ),
                    const SizedBox(height: 18),
                    // iOS Grouped Input Card
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                            child: TextField(
                              controller: _usernameController,
                              enabled: !_isSubmitting,
                              decoration: const InputDecoration(
                                hintText: 'Username (min 3 characters)',
                                hintStyle: TextStyle(color: CupertinoColors.placeholderText),
                                border: InputBorder.none,
                              ),
                            ),
                          ),
                          const Divider(height: 1, thickness: 0.5, indent: 16, color: appleHairline),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                            child: TextField(
                              controller: _passwordController,
                              enabled: !_isSubmitting,
                              obscureText: true,
                              onSubmitted: (_) => _sumbmitAuth(),
                              decoration: const InputDecoration(
                                hintText: 'Password (min 6 characters)',
                                hintStyle: TextStyle(color: CupertinoColors.placeholderText),
                                border: InputBorder.none,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (_errorMessage != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        _errorMessage!,
                        style: const TextStyle(color: appleRed, fontSize: 13),
                        textAlign: TextAlign.center,
                      ),
                    ],
                    const SizedBox(height: 22),
                    CupertinoButton(
                      color: appleRed,
                      borderRadius: BorderRadius.circular(12),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      onPressed: _isSubmitting ? null : _sumbmitAuth,
                      child: _isSubmitting
                          ? const CupertinoActivityIndicator(color: Colors.white)
                          : Text(
                              _isRegisterMode ? 'Create Account' : 'Sign In',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

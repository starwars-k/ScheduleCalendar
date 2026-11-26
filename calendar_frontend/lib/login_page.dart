import 'dart:convert';
import 'package:flutter/material.dart';
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
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isRegisterMode ? 'Create Account' : 'Login'),
      ),
      body: AbsorbPointer(
        absorbing: _isSubmitting,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    _isRegisterMode ? 'Create Account' : 'Login',
                    style: Theme.of(context).textTheme.headlineSmall,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24.0),
                  TextField(
                    controller: _usernameController,
                    enabled: !_isSubmitting,
                    decoration: InputDecoration(
                      labelText: _isRegisterMode ? 'Username (min 3 characters)' : 'Username',
                      border: OutlineInputBorder()
                    ),
                  ),
                  const SizedBox(height: 16.0),
                  TextField(
                    controller: _passwordController,
                    enabled: !_isSubmitting,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Password(min 6 characters)',
                      border: OutlineInputBorder()
                    ),
                  ),
                  if(_errorMessage != null) ...[
                    const SizedBox(height: 12.0),
                    Text(
                      _errorMessage!,
                      style: const TextStyle(color: Colors.red),
                    ),
                  ],
                  const SizedBox(height: 20.0),
                  ElevatedButton(
                    onPressed: _isSubmitting ? null : _sumbmitAuth,
                    child: _isSubmitting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2.0),
                        )
                      : Text(_isRegisterMode ? 'Create Account' : 'Login'),
                  ),
                  TextButton(
                    onPressed: _isSubmitting ? null : (){
                      setState(() {
                        _isRegisterMode = !_isRegisterMode;
                        _errorMessage = null;
                        _passwordController.clear();
                      });
                    },
                    child: Text(_isRegisterMode ? 'Already have an account? Login' : 'Don\'t have an account? Create one'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

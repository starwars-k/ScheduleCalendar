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
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _isRegisterMode = false;
  bool _isSubmitting = false;
  bool _obscurePassword = true;
  bool _isJapanese = false;
  String? _errorMessage;
  String? _successMessage;

  @override
  void dispose() {
    _usernameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _sumbmitAuth() async {
    if (_isSubmitting) return;
    final identifierOrUsername = _usernameController.text.trim();
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    if (identifierOrUsername.isEmpty || password.isEmpty || (_isRegisterMode && email.isEmpty)) {
      setState(() {
        _errorMessage = _isJapanese
            ? 'すべての必須項目を入力してください。'
            : 'Please fill in all required fields.';
        _successMessage = null;
      });
      return;
    }

    if (_isRegisterMode && !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
      setState(() {
        _errorMessage = _isJapanese
            ? '有効なメールアドレスを入力してください。'
            : 'Please enter a valid email address.';
        _successMessage = null;
      });
      return;
    }

    FocusScope.of(context).unfocus();

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
      _successMessage = null;
    });

    final endpoint = _isRegisterMode ? '/api/auth/register' : '/api/auth/login';
    final uri = Uri.parse('${widget.backendBaseUrl}$endpoint');

    try {
      final Map<String, dynamic> payload = _isRegisterMode
          ? {
              'username': identifierOrUsername,
              'email': email,
              'password': password,
              'language': _isJapanese ? 'ja' : 'en',
            }
          : {
              'identifier': identifierOrUsername,
              'username': identifierOrUsername,
              'password': password,
            };

      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
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
      if (response.statusCode == 200 || response.statusCode == 201) {
        final token = data['token'] as String;
        final username = data['username'] as String;
        final settings = UserAppSettings.fromJson(data);

        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('auth_token', token);
        await prefs.setString('auth_username', username);
        if (data['userId'] != null) {
          await prefs.setString('auth_userId', data['userId'].toString());
        }
        await settings.saveToCache();

        if (mounted) {
          widget.onLoginSuccess(token, username, settings, _isRegisterMode);
        }
      } else {
        setState(() {
          _errorMessage = data['error']?.toString() ??
              (_isJapanese
                  ? 'サーバーエラー (${response.statusCode}) が発生しました。'
                  : 'Server error (${response.statusCode}). Please try again.');
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = _isJapanese
            ? '通信エラーが発生しました。接続を確認して再試行してください。'
            : 'Network error. Please check your connection and try again.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  Future<void> _showForgotPasswordModal() async {
    final emailCtrl = TextEditingController();
    final resetTokenCtrl = TextEditingController();
    final newPasswordCtrl = TextEditingController();
    bool stepTwo = false;
    bool sending = false;
    bool obscureNewPassword = true;
    String? modalError;
    String? modalInfo;

    const Color appleRed = Color(0xFFFF3B30);
    const Color appleGroupedBg = Color(0xFFF2F2F7);
    const Color appleHairline = Color(0xFFE5E5EA);
    const Color appleSecondaryLabel = Color(0xFF8E8E93);

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      constraints: const BoxConstraints(maxWidth: 460),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          Future<void> requestResetCode() async {
            final emailText = emailCtrl.text.trim();
            if (emailText.isEmpty) {
              setModalState(() {
                modalError = _isJapanese
                    ? 'メールアドレスを入力してください。'
                    : 'Please enter your email address.';
              });
              return;
            }
            if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(emailText)) {
              setModalState(() {
                modalError = _isJapanese
                    ? '有効なメールアドレスを入力してください。'
                    : 'Please enter a valid email address.';
              });
              return;
            }
            setModalState(() {
              sending = true;
              modalError = null;
            });
            try {
              final res = await http.post(
                Uri.parse('${widget.backendBaseUrl}/api/auth/forgot-password'),
                headers: {'Content-Type': 'application/json'},
                body: jsonEncode({'email': emailText}),
              );
              final Map<String, dynamic> body = res.body.isNotEmpty
                  ? jsonDecode(res.body) as Map<String, dynamic>
                  : {};
              if (res.statusCode == 200) {
                final returnedToken = body['resetToken']?.toString() ?? '';
                if (returnedToken.isNotEmpty) {
                  resetTokenCtrl.text = returnedToken;
                }
                setModalState(() {
                  stepTwo = true;
                  modalInfo = body['emailSent'] == true
                      ? (_isJapanese
                          ? '登録メールアドレスにリセットコードを送信しました。'
                          : 'A reset code has been sent to your email.')
                      : (_isJapanese
                          ? '下の再設定コードと新しいパスワードを入力してください。'
                          : 'Enter the reset code below and choose a new password.');
                });
              } else {
                setModalState(() {
                  modalError = body['error']?.toString() ??
                      (_isJapanese
                          ? 'このメールアドレスのアカウントが見つかりません。'
                          : 'No account found with that email address.');
                });
              }
            } catch (_) {
              setModalState(() {
                modalError = _isJapanese
                    ? '通信エラーが発生しました。'
                    : 'Network error. Please try again.';
              });
            } finally {
              setModalState(() => sending = false);
            }
          }

          Future<void> submitNewPassword() async {
            final code = resetTokenCtrl.text.trim();
            final newPass = newPasswordCtrl.text;
            if (code.isEmpty || newPass.length < 6) {
              setModalState(() {
                modalError = _isJapanese
                    ? 'リセットコードと6文字以上の新しいパスワードを入力してください。'
                    : 'Enter the reset code and a password (min 6 characters).';
              });
              return;
            }
            setModalState(() {
              sending = true;
              modalError = null;
            });
            try {
              final res = await http.post(
                Uri.parse('${widget.backendBaseUrl}/api/auth/reset-password'),
                headers: {'Content-Type': 'application/json'},
                body: jsonEncode({
                  'resetToken': code,
                  'newPassword': newPass,
                }),
              );
              final Map<String, dynamic> body = res.body.isNotEmpty
                  ? jsonDecode(res.body) as Map<String, dynamic>
                  : {};
              if (res.statusCode == 200) {
                if (ctx.mounted) Navigator.pop(ctx);
                if (mounted) {
                  setState(() {
                    _passwordController.clear();
                    _errorMessage = null;
                    _successMessage = _isJapanese
                        ? 'パスワードを更新しました。新しいパスワードでログインしてください。'
                        : 'Password updated. Please sign in with your new password.';
                  });
                }
              } else {
                setModalState(() {
                  modalError = body['error']?.toString() ??
                      (_isJapanese ? 'コードが無効または期限切れです。' : 'Invalid or expired reset code.');
                });
              }
            } catch (_) {
              setModalState(() {
                modalError = _isJapanese ? '通信エラーが発生しました。' : 'Network error. Please try again.';
              });
            } finally {
              setModalState(() => sending = false);
            }
          }

          return Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
              child: Container(
                color: appleGroupedBg,
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Container(
                        width: 36,
                        height: 5,
                        decoration: BoxDecoration(
                          color: const Color(0xFFC7C7CC),
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        CupertinoButton(
                          padding: EdgeInsets.zero,
                          onPressed: () => Navigator.pop(ctx),
                          child: Text(
                            _isJapanese ? 'キャンセル' : 'Cancel',
                            style: const TextStyle(color: appleRed, fontSize: 15),
                          ),
                        ),
                        Text(
                          _isJapanese ? 'パスワード再設定' : 'Reset Password',
                          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(width: 60),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      stepTwo
                          ? (modalInfo ?? '')
                          : (_isJapanese
                              ? '登録済みのメールアドレスを入力してください。'
                              : 'Enter your registered email address.'),
                      style: const TextStyle(fontSize: 13, color: appleSecondaryLabel),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        children: [
                          if (!stepTwo)
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                              child: TextField(
                                controller: emailCtrl,
                                enabled: !sending,
                                keyboardType: TextInputType.emailAddress,
                                autofillHints: const [AutofillHints.email],
                                decoration: InputDecoration(
                                  hintText: _isJapanese ? 'メールアドレス' : 'Email address',
                                  hintStyle: const TextStyle(color: CupertinoColors.placeholderText),
                                  border: InputBorder.none,
                                ),
                              ),
                            )
                          else ...[
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                              child: TextField(
                                controller: resetTokenCtrl,
                                enabled: !sending,
                                decoration: InputDecoration(
                                  hintText: _isJapanese ? 'リセットコード' : 'Reset Code',
                                  hintStyle: const TextStyle(color: CupertinoColors.placeholderText),
                                  border: InputBorder.none,
                                ),
                              ),
                            ),
                            const Divider(height: 1, thickness: 0.5, indent: 16, color: appleHairline),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                              child: TextField(
                                controller: newPasswordCtrl,
                                enabled: !sending,
                                obscureText: obscureNewPassword,
                                decoration: InputDecoration(
                                  hintText: _isJapanese ? '新しいパスワード（6文字以上）' : 'New Password (min 6 chars)',
                                  hintStyle: const TextStyle(color: CupertinoColors.placeholderText),
                                  border: InputBorder.none,
                                  suffixIcon: IconButton(
                                    icon: Icon(
                                      obscureNewPassword ? CupertinoIcons.eye : CupertinoIcons.eye_slash,
                                      size: 19,
                                      color: appleSecondaryLabel,
                                    ),
                                    onPressed: () => setModalState(() => obscureNewPassword = !obscureNewPassword),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (modalError != null) ...[
                      const SizedBox(height: 10),
                      Text(
                        modalError!,
                        style: const TextStyle(color: appleRed, fontSize: 13),
                        textAlign: TextAlign.center,
                      ),
                    ],
                    const SizedBox(height: 18),
                    CupertinoButton(
                      color: appleRed,
                      borderRadius: BorderRadius.circular(12),
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      onPressed: sending ? null : (stepTwo ? submitNewPassword : requestResetCode),
                      child: sending
                          ? const CupertinoActivityIndicator(color: Colors.white)
                          : Text(
                              stepTwo
                                  ? (_isJapanese ? 'パスワードを変更' : 'Update Password')
                                  : (_isJapanese ? '次へ' : 'Continue'),
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
          );
        },
      ),
    );
    emailCtrl.dispose();
    resetTokenCtrl.dispose();
    newPasswordCtrl.dispose();
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
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 400),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Language Selector (English / 日本語)
                    Align(
                      alignment: Alignment.centerRight,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: appleHairline, width: 0.8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(CupertinoIcons.globe, color: appleRed, size: 17),
                            const SizedBox(width: 6),
                            DropdownButtonHideUnderline(
                              child: DropdownButton<bool>(
                                value: _isJapanese,
                                isDense: true,
                                icon: const Icon(
                                  CupertinoIcons.chevron_up_chevron_down,
                                  size: 14,
                                  color: appleSecondaryLabel,
                                ),
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                  color: Colors.black87,
                                ),
                                items: const [
                                  DropdownMenuItem<bool>(
                                    value: false,
                                    child: Text('English'),
                                  ),
                                  DropdownMenuItem<bool>(
                                    value: true,
                                    child: Text('日本語 (Japanese)'),
                                  ),
                                ],
                                onChanged: _isSubmitting
                                    ? null
                                    : (bool? val) {
                                        if (val != null) {
                                          setState(() {
                                            _isJapanese = val;
                                            _errorMessage = null;
                                          });
                                        }
                                      },
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    // Custom Schedule App Badge (Non-Apple Calendar Icon)
                    Center(
                      child: Container(
                        width: 72,
                        height: 72,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [Color(0xFFFF3B30), Color(0xFFFF6B5B)],
                          ),
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: appleRed.withOpacity(0.28),
                              blurRadius: 16,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.event_available_rounded,
                          size: 38,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      _isRegisterMode
                          ? (_isJapanese ? 'アカウント作成' : 'Create Account')
                          : 'Schedule Calendar',
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
                          ? (_isJapanese
                              ? 'アカウントを作成して予定を同期します'
                              : 'Create an account to sync your calendar')
                          : (_isJapanese
                              ? 'ログインしてスケジュールを確認'
                              : 'Sign in to access your schedule'),
                      style: const TextStyle(fontSize: 14, color: appleSecondaryLabel),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    CupertinoSlidingSegmentedControl<bool>(
                      groupValue: _isRegisterMode,
                      children: {
                        false: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 7),
                          child: Text(
                            _isJapanese ? 'ログイン' : 'Sign In',
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                          ),
                        ),
                        true: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 7),
                          child: Text(
                            _isJapanese ? '新規登録' : 'Create Account',
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                          ),
                        ),
                      },
                      onValueChanged: (val) {
                        if (val != null) {
                          setState(() {
                            _isRegisterMode = val;
                            _errorMessage = null;
                            _successMessage = null;
                            _passwordController.clear();
                          });
                        }
                      },
                    ),
                    const SizedBox(height: 18),
                    // Grouped Input Card
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
                              keyboardType: _isRegisterMode ? TextInputType.text : TextInputType.emailAddress,
                              decoration: InputDecoration(
                                hintText: _isRegisterMode
                                    ? (_isJapanese ? 'ユーザー名（3文字以上）' : 'Username (min 3 characters)')
                                    : (_isJapanese ? 'ユーザー名またはメールアドレス' : 'Username or Email'),
                                hintStyle: const TextStyle(color: CupertinoColors.placeholderText),
                                border: InputBorder.none,
                              ),
                            ),
                          ),
                          if (_isRegisterMode) ...[
                            const Divider(height: 1, thickness: 0.5, indent: 16, color: appleHairline),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                              child: TextField(
                                controller: _emailController,
                                enabled: !_isSubmitting,
                                keyboardType: TextInputType.emailAddress,
                                decoration: InputDecoration(
                                  hintText: _isJapanese ? 'メールアドレス' : 'Email address',
                                  hintStyle: const TextStyle(color: CupertinoColors.placeholderText),
                                  border: InputBorder.none,
                                ),
                              ),
                            ),
                          ],
                          const Divider(height: 1, thickness: 0.5, indent: 16, color: appleHairline),
                          Padding(
                            padding: const EdgeInsets.only(left: 16, right: 6, top: 4, bottom: 4),
                            child: TextField(
                              controller: _passwordController,
                              enabled: !_isSubmitting,
                              obscureText: _obscurePassword,
                              onSubmitted: (_) => _sumbmitAuth(),
                              decoration: InputDecoration(
                                hintText: _isJapanese
                                    ? 'パスワード（6文字以上）'
                                    : 'Password (min 6 characters)',
                                hintStyle: const TextStyle(color: CupertinoColors.placeholderText),
                                border: InputBorder.none,
                                suffixIcon: IconButton(
                                  icon: Icon(
                                    _obscurePassword ? CupertinoIcons.eye : CupertinoIcons.eye_slash,
                                    size: 19,
                                    color: appleSecondaryLabel,
                                  ),
                                  onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (!_isRegisterMode)
                      Align(
                        alignment: Alignment.centerRight,
                        child: CupertinoButton(
                          padding: const EdgeInsets.only(top: 6, right: 2),
                          minSize: 28,
                          onPressed: _isSubmitting ? null : _showForgotPasswordModal,
                          child: Text(
                            _isJapanese ? 'パスワードをお忘れですか？' : 'Forgot Password?',
                            style: const TextStyle(fontSize: 13, color: appleRed),
                          ),
                        ),
                      ),
                    if (_successMessage != null) ...[
                      const SizedBox(height: 10),
                      Text(
                        _successMessage!,
                        style: const TextStyle(color: Color(0xFF34C759), fontSize: 13, fontWeight: FontWeight.w500),
                        textAlign: TextAlign.center,
                      ),
                    ],
                    if (_errorMessage != null) ...[
                      const SizedBox(height: 10),
                      Text(
                        _errorMessage!,
                        style: const TextStyle(color: appleRed, fontSize: 13),
                        textAlign: TextAlign.center,
                      ),
                    ],
                    const SizedBox(height: 18),
                    CupertinoButton(
                      color: appleRed,
                      borderRadius: BorderRadius.circular(12),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      onPressed: _isSubmitting ? null : _sumbmitAuth,
                      child: _isSubmitting
                          ? const CupertinoActivityIndicator(color: Colors.white)
                          : Text(
                              _isRegisterMode
                                  ? (_isJapanese ? 'アカウント作成' : 'Create Account')
                                  : (_isJapanese ? 'ログイン' : 'Sign In'),
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
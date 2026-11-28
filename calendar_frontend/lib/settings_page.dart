import 'dart:convert';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:calendar_frontend/initialSetupPage.dart';
import 'package:calendar_frontend/notification_service.dart';

class SettingsPage extends StatefulWidget {
  final String backendBaseUrl;
  final String authToken;
  final String username;
  final UserAppSettings initialSettings;
  final void Function(UserAppSettings updated) onSettingsUpdated;
  final VoidCallback onLogout;

  const SettingsPage({
    super.key,
    required this.backendBaseUrl,
    required this.authToken,
    required this.username,
    required this.initialSettings,
    required this.onSettingsUpdated,
    required this.onLogout,
  });

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late String _timezone;
  late String _language;
  late String _currency;
  late bool _enableTodoList;
  late bool _enablePayroll;
  late bool _enableNotification;
  late String _savedUsername;
  late String _savedEmail;
  DateTime? _birthday;

  static const Color appleRed = Color(0xFFFF3B30);
  static const Color appleGroupedBg = Color(0xFFF2F2F7);
  static const Color appleHairline = Color(0xFFE5E5EA);
  static const Color appleSecondaryLabel = Color(0xFF8E8E93);

  bool get _isJa => _language == 'ja';

  @override
  void initState() {
    super.initState();
    _timezone = widget.initialSettings.timezone;
    _language = widget.initialSettings.language;
    _currency = widget.initialSettings.currency == 'JPY' ? 'JPY' : 'USD';
    _enableTodoList = widget.initialSettings.enableTodoList;
    _enablePayroll = widget.initialSettings.enablePayroll;
    _enableNotification = widget.initialSettings.enableNotifications;
    _savedUsername = widget.username;
    _savedEmail = widget.initialSettings.email;
    if (widget.initialSettings.birthday.isNotEmpty) {
      _birthday = DateTime.tryParse(widget.initialSettings.birthday);
    }
  }

  String _formatBirthday(DateTime? dt) {
    if (dt == null) return _isJa ? '未設定' : 'Not set';
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  String _extractFriendlyError(http.Response response, String fallback) {
    if (response.statusCode == 404) {
      return _isJa
          ? 'APIが見つかりません (404)。ローカルでテストする場合は --dart-define=BACKEND_BASE_URL=http://localhost:8080 を指定するか、mainへマージしてRenderにデプロイしてください。'
          : 'API endpoint not found (404). Run Flutter with --dart-define=BACKEND_BASE_URL=http://localhost:8080 for local testing, or deploy the updated backend.';
    }
    if (response.statusCode == 401) {
      return _isJa
          ? '認証の有効期限が切れました (401)。一度ログアウトして再ログインしてください。'
          : 'Session expired (401). Please log out and log in again.';
    }
    try {
      if (response.body.isNotEmpty) {
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic>) {
          final msg = decoded['message']?.toString();
          if (msg != null && msg.isNotEmpty && msg != 'Not Found' && msg != 'No message available') {
            return msg;
          }
          final err = decoded['error']?.toString();
          if (err != null && err.isNotEmpty && err != 'Not Found') {
            return err;
          }
        }
      }
    } catch (_) {}
    return '$fallback (HTTP ${response.statusCode})';
  }

  Future<bool> _autoSaveSettings({
    String? usernameOverride,
    String? emailOverride,
    DateTime? birthdayOverride,
    bool clearBirthday = false,
    String? currencyOverride,
    String? languageOverride,
    bool? enableTodoListOverride,
    bool? enableNotificationsOverride,
    bool showSuccessToast = false,
  }) async {
    final nextUsername = (usernameOverride ?? _savedUsername).trim();
    final nextEmail = (emailOverride ?? _savedEmail).trim();

    if (nextUsername.length < 3) {
      _showSnack(
        _isJa ? 'ユーザー名は3文字以上で入力してください。' : 'Username must be at least 3 characters.',
        isError: true,
      );
      return false;
    }

    if (nextEmail.isNotEmpty && !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(nextEmail)) {
      _showSnack(
        _isJa ? '有効なメールアドレスを入力してください。' : 'Please enter a valid email address.',
        isError: true,
      );
      return false;
    }

    final effectiveBday = clearBirthday ? null : (birthdayOverride ?? _birthday);
    final bdayStr = effectiveBday == null ? '' : _formatBirthday(effectiveBday);
    final nextCurrency = currencyOverride ?? _currency;
    final nextLanguage = languageOverride ?? _language;
    final nextTodo = enableTodoListOverride ?? _enableTodoList;
    final nextNotification = enableNotificationsOverride ?? _enableNotification;

    try {
      final response = await http.put(
        Uri.parse('${widget.backendBaseUrl}/api/auth/settings'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${widget.authToken}',
        },
        body: jsonEncode({
          'username': nextUsername,
          'email': nextEmail,
          'birthday': bdayStr,
          'currency': nextCurrency,
          'timezone': _timezone,
          'language': nextLanguage,
          'enableTodoList': nextTodo,
          'enablePayroll': false,
          'enableNotifications': nextNotification,
          'setupComplete': true,
        }),
      );

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = response.body.isNotEmpty
            ? jsonDecode(response.body) as Map<String, dynamic>
            : <String, dynamic>{};
        final updated = UserAppSettings.fromJson(data);
        await updated.saveToCache();
        final prefs = await SharedPreferences.getInstance();
        final updatedUser = data['username']?.toString() ?? nextUsername;
        await prefs.setString('auth_username', updatedUser);
        if (mounted) {
          setState(() {
            _savedUsername = updatedUser;
            _savedEmail = updated.email;
            _language = updated.language;
            _currency = updated.currency;
            _enableTodoList = updated.enableTodoList;
            _enablePayroll = updated.enablePayroll;
            _enableNotification = updated.enableNotifications;
            _birthday = updated.birthday.isNotEmpty ? DateTime.tryParse(updated.birthday) : null;
          });
        }
        widget.onSettingsUpdated(updated);
        if (showSuccessToast && mounted) {
          _showSnack(_isJa ? 'アカウント情報を更新しました。' : 'Account info updated.');
        }
        return true;
      } else {
        _showSnack(
          _extractFriendlyError(
            response,
            _isJa ? '設定の更新に失敗しました' : 'Failed to update settings',
          ),
          isError: true,
        );
        return false;
      }
    } catch (e) {
      _showSnack(
        _isJa ? 'サーバーに接続できませんでした: $e' : 'Could not reach server: $e',
        isError: true,
      );
      return false;
    }
  }

  Future<void> _showEditAccountDialog() async {
    final result = await showDialog(
      context: context,
      builder: (_) => _EditAccountDialog(
        backendBaseUrl: widget.backendBaseUrl,
        authToken: widget.authToken,
        initialUsername: _savedUsername,
        initialEmail: _savedEmail,
        currentSettings: UserAppSettings(
          timezone: _timezone,
          language: _language,
          email: _savedEmail,
          birthday: _birthday == null ? '' : _formatBirthday(_birthday),
          currency: _currency,
          enableTodoList: _enableTodoList,
          enablePayroll: _enablePayroll,
          enableNotifications: _enableNotification,
          setupComplete: true,
        ),
        isJa: _isJa,
      ),
    );
    if (result != null && mounted) {
      final updated = result['settings'] as UserAppSettings;
      final updatedUsername = result['username'] as String;
      setState(() {
        _savedUsername = updatedUsername;
        _savedEmail = updated.email;
      });
      widget.onSettingsUpdated(updated);
      _showSnack(_isJa ? 'アカウント情報を更新しました。' : 'Account info updated.');
    }
  }

  Future<void> _pickBirthday() async {
    final now = DateTime.now();
    final prev = _birthday;
    final picked = await showDatePicker(
      context: context,
      initialDate: _birthday ?? DateTime(2000, 1, 1),
      firstDate: DateTime(1920, 1, 1),
      lastDate: now,
    );
    if (picked != null) {
      setState(() => _birthday = picked);
      final ok = await _autoSaveSettings(birthdayOverride: picked);
      if (!ok && mounted) {
        setState(() => _birthday = prev);
      }
    }
  }

  Future<void> _showChangePasswordDialog() async {
    final changed = await showDialog<bool>(
      context: context,
      builder: (_) => _ChangePasswordDialog(
        backendBaseUrl: widget.backendBaseUrl,
        authToken: widget.authToken,
        isJa: _isJa,
      ),
    );
    if (changed == true && mounted) {
      _showSnack(_isJa ? 'パスワードを変更しました。' : 'Password changed successfully.');
    }
  }

  Future<void> _showDeleteAccountDialog() async {
    final deleted = await showDialog<bool>(
      context: context,
      builder: (_) => _DeleteAccountDialog(
        backendBaseUrl: widget.backendBaseUrl,
        authToken: widget.authToken,
        isJa: _isJa,
      ),
    );
    if (deleted == true && mounted) {
      widget.onLogout();
    }
  }

  Future<void> _showLogoutConfirmDialog() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(_isJa ? 'ログアウト' : 'Log Out'),
        content: Text(
          _isJa
              ? '本当にログアウトしますか？'
              : 'Are you sure you want to log out?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(_isJa ? 'キャンセル' : 'Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: appleRed),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(_isJa ? 'ログアウト' : 'Log Out'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      widget.onLogout();
    }
  }

  void _showSnack(String msg, {bool isError = false}) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.clearSnackBars();
    messenger?.showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError ? appleRed : const Color(0xFF34C759),
      ),
    );
  }

  Widget _sectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 6),
      child: Text(
        title.toUpperCase(),
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: appleSecondaryLabel,
          letterSpacing: 0.4,
        ),
      ),
    );
  }

  Widget _buildComingSoonBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.amber.shade100,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        _isJa ? '順次追加予定' : 'Coming Soon',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: Colors.amber.shade900,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: appleGroupedBg,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: ListView(
            padding: const EdgeInsets.only(bottom: 40),
            children: [
              // ACCOUNT & PROFILE (Single shared Edit button for Username & Email)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      (_isJa ? 'アカウント・プロフィール' : 'Account & Profile').toUpperCase(),
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: appleSecondaryLabel,
                        letterSpacing: 0.4,
                      ),
                    ),
                    TextButton.icon(
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      onPressed: _showEditAccountDialog,
                      icon: const Icon(CupertinoIcons.pencil, size: 14, color: appleRed),
                      label: Text(
                        _isJa ? '編集' : 'Edit',
                        style: const TextStyle(color: appleRed, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
                child: Column(
                  children: [
                    ListTile(
                      title: Text(_isJa ? 'ユーザー名' : 'Username'),
                      subtitle: Text(_savedUsername, style: const TextStyle(color: appleSecondaryLabel)),
                    ),
                    const Divider(height: 1, indent: 54, color: appleHairline),
                    ListTile(
                      leading: const Icon(CupertinoIcons.mail, color: appleRed),
                      title: Text(_isJa ? 'メールアドレス' : 'Email Address'),
                      subtitle: Text(
                        _savedEmail.isEmpty ? (_isJa ? '未設定' : 'Not set') : _savedEmail,
                        style: const TextStyle(color: appleSecondaryLabel),
                      ),
                    ),
                    const Divider(height: 1, indent: 54, color: appleHairline),
                    ListTile(
                      leading: const Icon(CupertinoIcons.gift, color: appleRed),
                      title: Text(_isJa ? '誕生日' : 'Birthday'),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _formatBirthday(_birthday),
                            style: const TextStyle(color: appleSecondaryLabel, fontSize: 14),
                          ),
                          if (_birthday != null)
                            IconButton(
                              icon: const Icon(CupertinoIcons.clear_circled_solid, size: 18, color: appleSecondaryLabel),
                              onPressed: () async {
                                final prev = _birthday;
                                setState(() => _birthday = null);
                                final ok = await _autoSaveSettings(clearBirthday: true);
                                if (!ok && mounted) {
                                  setState(() => _birthday = prev);
                                }
                              },
                            ),
                          const Icon(CupertinoIcons.chevron_forward, size: 16, color: appleSecondaryLabel),
                        ],
                      ),
                      onTap: _pickBirthday,
                    ),
                  ],
                ),
              ),

              // PREFERENCES
              _sectionHeader(_isJa ? '一般設定' : 'Preferences'),
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
                child: Column(
                  children: [
                    // 1. Language Seetings
                    ListTile(
                      leading: const Icon(CupertinoIcons.globe, color: appleRed),
                      title: Text(_isJa ? '言語' : 'Language'),
                      trailing: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _language,
                          items: const [
                            DropdownMenuItem(value: 'en', child: Text('English')),
                            DropdownMenuItem(value: 'ja', child: Text('日本語 (Japanese)')),
                          ],
                          onChanged: (v) async {
                            if (v != null && v != _language) {
                              final prev = _language;
                              setState(() => _language = v);
                              final ok = await _autoSaveSettings(languageOverride: v);
                              if (!ok && mounted) {
                                setState(() => _language = prev);
                              }
                            }
                          },
                        ),
                      ),
                    ),
                    
                    // 2. Todo List Page Settings
                    const Divider(height: 1, indent: 54, color: appleHairline),
                    SwitchListTile.adaptive(
                      secondary: const Icon(CupertinoIcons.checkmark_circle, color: appleRed),
                      title: Text(_isJa ? 'Todoリスト' : 'Todo List'),
                      activeThumbColor: appleRed,
                      value: _enableTodoList,
                      onChanged: (v) async {
                        final prev = _enableTodoList;
                        setState(() => _enableTodoList = v);
                        final ok = await _autoSaveSettings(enableTodoListOverride: v);
                        if (!ok && mounted) {
                          setState(() => _enableTodoList = prev);
                        }
                      },
                    ),

                    // 3. Payroll Page Setting
                    const Divider(height: 1, indent: 54, color: appleHairline),
                    ListTile(
                      leading: const Icon(CupertinoIcons.money_dollar_circle, color: appleSecondaryLabel),
                      title: Wrap(
                        spacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            _isJa ? '給与計算' : 'Payroll',
                            style: const TextStyle(color: appleSecondaryLabel),
                          ),
                          _buildComingSoonBadge(),
                        ],
                      ),
                      trailing: const CupertinoSwitch(value: false, onChanged: null),
                    ),
                    
                    // 4. Currency(通貨) Setting
                    if(_enablePayroll) ...[
                      const Divider(height: 1, indent: 54, color: appleHairline),
                      ListTile(
                        leading: const Icon(CupertinoIcons.money_dollar_circle, color: appleRed),
                        title: Text(_isJa ? '通貨' : 'Currency'),
                        trailing: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: _currency,
                            items: const [
                              DropdownMenuItem(value: 'USD', child: Text('\$ (USD)')),
                              DropdownMenuItem(value: 'JPY', child: Text('¥ (JPY)')),
                            ],
                            onChanged: (v) async {
                              if (v != null && v != _currency) {
                                final prev = _currency;
                                setState(() => _currency = v);
                                final ok = await _autoSaveSettings(currencyOverride: v);
                                if (!ok && mounted) {
                                  setState(() => _currency = prev);
                                }
                              }
                            },
                          ),
                        ),
                      ),
                    ],

                    // 5. Notification Setting
                    const Divider(height: 1, indent: 54, color: appleHairline),
                    SwitchListTile.adaptive(
                      secondary: const Icon(CupertinoIcons.bell_fill, color: appleRed),
                      title: Text(_isJa ? '通知' : 'Notifications'),
                      subtitle: Text(
                        _isJa
                            ? '通知が有効な予定を事前にお知らせします'
                            : 'Receive reminders for events with alerts enabled',
                        style: const TextStyle(fontSize: 12, color: appleSecondaryLabel),
                      ),
                      activeThumbColor: appleRed,
                      value: _enableNotification,
                      onChanged: (v) async {
                        final prev = _enableNotification;
                        setState(() => _enableNotification = v);
                        if (v) {
                          await requestBrowserNotificationPermission();
                        }
                        final ok = await _autoSaveSettings(enableNotificationsOverride: v);
                        if (!ok && mounted) {
                          setState(() => _enableNotification = prev);
                        }
                      },
                    ),
                  ],
                ),
              ),

              // SECURITY & ACCOUNT MANAGEMENT
              _sectionHeader(_isJa ? 'セキュリティ・アカウント管理' : 'Security & Account Manage'),
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
                child: Column(
                  children: [
                    // Change Password
                    ListTile(
                      leading: const Icon(CupertinoIcons.lock_rotation, color: appleRed),
                      title: Text(_isJa ? 'パスワードを変更' : 'Change Password'),
                      trailing: const Icon(CupertinoIcons.chevron_forward, size: 16, color: appleSecondaryLabel),
                      onTap: _showChangePasswordDialog,
                    ),
                    
                    //Log Out
                    const Divider(height: 1, indent: 54, color: appleHairline),
                    ListTile(
                      leading: const Icon(CupertinoIcons.square_arrow_right, color: appleRed),
                      title: Text(_isJa ? 'ログアウト' : 'Log Out'),
                      trailing: const Icon(CupertinoIcons.chevron_forward, size: 16, color: appleSecondaryLabel),
                      onTap: _showLogoutConfirmDialog,
                    ),

                    //Delete Account
                    const Divider(height: 1, indent: 54, color: appleHairline),
                    ListTile(
                      leading: const Icon(CupertinoIcons.trash, color: appleRed),
                      title: Text(
                        _isJa ? 'アカウントを削除' : 'Delete Account',
                        style: const TextStyle(color: appleRed, fontWeight: FontWeight.w600),
                      ),
                      trailing: const Icon(CupertinoIcons.chevron_forward, size: 16, color: appleRed),
                      onTap: _showDeleteAccountDialog,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChangePasswordDialog extends StatefulWidget {
  final String backendBaseUrl;
  final String authToken;
  final bool isJa;

  const _ChangePasswordDialog({
    required this.backendBaseUrl,
    required this.authToken,
    required this.isJa,
  });

  @override
  State<_ChangePasswordDialog> createState() => _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends State<_ChangePasswordDialog> {
  final TextEditingController _currentCtrl = TextEditingController();
  final TextEditingController _newCtrl = TextEditingController();
  final TextEditingController _confirmCtrl = TextEditingController();
  bool _obscure1 = true;
  bool _obscure2 = true;
  bool _obscure3 = true;
  bool _submitting = false;
  String? _errText;

  @override
  void dispose() {
    _currentCtrl.dispose();
    _newCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting) return;
    if (_newCtrl.text.length < 6) {
      setState(() => _errText = widget.isJa ? '6文字以上で入力してください。' : 'Minimum 6 characters required.');
      return;
    }
    if (_newCtrl.text != _confirmCtrl.text) {
      setState(() => _errText = widget.isJa ? '新しいパスワードが一致しません。' : 'New passwords do not match.');
      return;
    }

    setState(() {
      _submitting = true;
      _errText = null;
    });

    try {
      final res = await http.post(
        Uri.parse('${widget.backendBaseUrl}/api/auth/change-password'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${widget.authToken}',
        },
        body: jsonEncode({
          'currentPassword': _currentCtrl.text,
          'newPassword': _newCtrl.text,
        }),
      );

      if (!mounted) return;
      if (res.statusCode == 200) {
        Navigator.of(context).pop(true);
        return;
      }

      if (res.statusCode == 404) {
        setState(() {
          _errText = widget.isJa
              ? 'APIが見つかりません (404)。ローカルバックエンドに接続するか、Renderへデプロイしてください。'
              : 'Password endpoint not found (404). Connect to local backend or deploy updated backend.';
          _submitting = false;
        });
        return;
      }

      String message = widget.isJa ? 'パスワードの変更に失敗しました。' : 'Failed to change password.';
      if (res.body.isNotEmpty) {
        final body = jsonDecode(res.body);
        if (body is Map<String, dynamic>) {
          final err = body['error']?.toString();
          if (err != null && err.isNotEmpty && err != 'Not Found') {
            message = err;
          }
        }
      }
      setState(() {
        _errText = message;
        _submitting = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _errText = widget.isJa ? 'サーバーに接続できませんでした: $e' : 'Network error: $e';
          _submitting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.isJa ? 'パスワードを変更' : 'Change Password'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _currentCtrl,
            obscureText: _obscure1,
            decoration: InputDecoration(
              labelText: widget.isJa ? '現在のパスワード' : 'Current Password',
              suffixIcon: IconButton(
                icon: Icon(_obscure1 ? CupertinoIcons.eye : CupertinoIcons.eye_slash, size: 18),
                onPressed: () => setState(() => _obscure1 = !_obscure1),
              ),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _newCtrl,
            obscureText: _obscure2,
            decoration: InputDecoration(
              labelText: widget.isJa ? '新しいパスワード(6文字以上)' : 'New Password (min 6 chars)',
              suffixIcon: IconButton(
                icon: Icon(_obscure2 ? CupertinoIcons.eye : CupertinoIcons.eye_slash, size: 18),
                onPressed: () => setState(() => _obscure2 = !_obscure2),
              ),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _confirmCtrl,
            obscureText: _obscure3,
            decoration: InputDecoration(
              labelText: widget.isJa ? '新しいパスワード（確認）' : 'Confirm New Password',
              suffixIcon: IconButton(
                icon: Icon(_obscure3 ? CupertinoIcons.eye : CupertinoIcons.eye_slash, size: 18),
                onPressed: () => setState(() => _obscure3 = !_obscure3),
              ),
            ),
          ),
          if (_errText != null) ...[
            const SizedBox(height: 10),
            Text(_errText!, style: const TextStyle(color: Color(0xFFFF3B30), fontSize: 13)),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.of(context).pop(false),
          child: Text(widget.isJa ? 'キャンセル' : 'Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: const Color(0xFFFF3B30)),
          onPressed: _submitting ? null : _submit,
          child: Text(widget.isJa ? '変更する' : 'Update'),
        ),
      ],
    );
  }
}

class _DeleteAccountDialog extends StatefulWidget {
  final String backendBaseUrl;
  final String authToken;
  final bool isJa;

  const _DeleteAccountDialog({
    required this.backendBaseUrl,
    required this.authToken,
    required this.isJa,
  });

  @override
  State<_DeleteAccountDialog> createState() => _DeleteAccountDialogState();
}

class _DeleteAccountDialogState extends State<_DeleteAccountDialog> {
  final TextEditingController _passwordCtrl = TextEditingController();
  bool _obscure = true;
  bool _deleting = false;
  String? _errText;

  @override
  void dispose() {
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_deleting) return;
    if (_passwordCtrl.text.isEmpty) {
      setState(() => _errText = widget.isJa ? 'パスワードを入力してください。' : 'Please enter your password.');
      return;
    }

    setState(() {
      _deleting = true;
      _errText = null;
    });

    try {
      final res = await http.delete(
        Uri.parse('${widget.backendBaseUrl}/api/auth/account'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${widget.authToken}',
        },
        body: jsonEncode({'password': _passwordCtrl.text}),
      );

      if (!mounted) return;
      if (res.statusCode == 200) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.clear();
        if (mounted) Navigator.of(context).pop(true);
        return;
      }

      if (res.statusCode == 404) {
        setState(() {
          _errText = widget.isJa
              ? 'APIが見つかりません (404)。ローカルバックエンドに接続するか、Renderへデプロイしてください。'
              : 'Account deletion endpoint not found (404). Connect to local backend or deploy updated backend.';
          _deleting = false;
        });
        return;
      }

      String message = widget.isJa ? 'アカウントの削除に失敗しました。' : 'Failed to delete account.';
      if (res.body.isNotEmpty) {
        final body = jsonDecode(res.body);
        if (body is Map<String, dynamic>) {
          final err = body['error']?.toString();
          if (err != null && err.isNotEmpty && err != 'Not Found') {
            message = err;
          }
        }
      }
      setState(() {
        _errText = message;
        _deleting = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _errText = widget.isJa ? 'サーバーに接続できませんでした: $e' : 'Network error: $e';
          _deleting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        widget.isJa ? 'アカウントを削除' : 'Delete Account',
        style: const TextStyle(color: Color(0xFFFF3B30), fontWeight: FontWeight.w700),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.isJa
                ? 'アカウントとすべての予定データが完全に削除され、元に戻せません。確認のためパスワードを入力してください。'
                : 'Your account and all calendar events will be permanently deleted. Enter your password to confirm.',
            style: const TextStyle(fontSize: 13),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _passwordCtrl,
            obscureText: _obscure,
            decoration: InputDecoration(
              labelText: widget.isJa ? 'パスワード' : 'Password',
              suffixIcon: IconButton(
                icon: Icon(_obscure ? CupertinoIcons.eye : CupertinoIcons.eye_slash, size: 18),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
          ),
          if (_errText != null) ...[
            const SizedBox(height: 10),
            Text(_errText!, style: const TextStyle(color: Color(0xFFFF3B30), fontSize: 13)),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _deleting ? null : () => Navigator.of(context).pop(false),
          child: Text(widget.isJa ? 'キャンセル' : 'Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: const Color(0xFFFF3B30)),
          onPressed: _deleting ? null : _submit,
          child: Text(widget.isJa ? '完全に削除' : 'Delete Forever'),
        ),
      ],
    );
  }
}

class _EditAccountDialog extends StatefulWidget {
  final String backendBaseUrl;
  final String authToken;
  final String initialUsername;
  final String initialEmail;
  final UserAppSettings currentSettings;
  final bool isJa;

  const _EditAccountDialog({
    required this.backendBaseUrl,
    required this.authToken,
    required this.initialUsername,
    required this.initialEmail,
    required this.currentSettings,
    required this.isJa,
  });

  @override
  State<_EditAccountDialog> createState() => _EditAccountDialogState();
}

class _EditAccountDialogState extends State<_EditAccountDialog> {
  late final TextEditingController _usernameCtrl;
  late final TextEditingController _emailCtrl;
  bool _submitting = false;
  String? _errText;

  @override
  void initState() {
    super.initState();
    _usernameCtrl = TextEditingController(text: widget.initialUsername);
    _emailCtrl = TextEditingController(text: widget.initialEmail);
  }

  @override
  void dispose() {
    _usernameCtrl.dispose();
    _emailCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting) return;
    final nextUsername = _usernameCtrl.text.trim();
    final nextEmail = _emailCtrl.text.trim();

    if (nextUsername.length < 3) {
      setState(() => _errText = widget.isJa
          ? 'ユーザー名は3文字以上で入力してください。'
          : 'Username must be at least 3 characters.');
      return;
    }
    if (nextEmail.isNotEmpty &&
        !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(nextEmail)) {
      setState(() => _errText = widget.isJa
          ? '有効なメールアドレスを入力してください。'
          : 'Please enter a valid email address.');
      return;
    }

    setState(() {
      _submitting = true;
      _errText = null;
    });

    try {
      final res = await http.put(
        Uri.parse('${widget.backendBaseUrl}/api/auth/settings'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${widget.authToken}',
        },
        body: jsonEncode({
          'username': nextUsername,
          'email': nextEmail,
          'birthday': widget.currentSettings.birthday,
          'currency': widget.currentSettings.currency,
          'timezone': widget.currentSettings.timezone,
          'language': widget.currentSettings.language,
          'enableTodoList': widget.currentSettings.enableTodoList,
          'enablePayroll': widget.currentSettings.enablePayroll,
          'enableNotifications': widget.currentSettings.enableNotifications,
          'setupComplete': true,
        }),
      );

      if (!mounted) return;
      if (res.statusCode == 200) {
        final Map<String, dynamic> data = res.body.isNotEmpty
            ? jsonDecode(res.body) as Map<String, dynamic>
            : <String, dynamic>{};
        final updated = UserAppSettings.fromJson(data);
        await updated.saveToCache();
        final prefs = await SharedPreferences.getInstance();
        final updatedUser = data['username']?.toString() ?? nextUsername;
        await prefs.setString('auth_username', updatedUser);
        if (!mounted) return;
        Navigator.of(context).pop({
          'settings': updated,
          'username': updatedUser,
        });
        return;
      }

      String message = widget.isJa
          ? 'アカウント情報の更新に失敗しました。'
          : 'Failed to update account info.';
      if (res.body.isNotEmpty) {
        final body = jsonDecode(res.body);
        if (body is Map<String, dynamic>) {
          final err = body['error']?.toString();
          if (err != null && err.isNotEmpty && err != 'Not Found') {
            message = err;
          }
        }
      }
      setState(() {
        _errText = message;
        _submitting = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _errText = widget.isJa ? 'サーバーに接続できませんでした: $e' : 'Network error: $e';
          _submitting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.isJa ? 'アカウント情報を編集' : 'Edit Account'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _usernameCtrl,
            autofocus: true,
            decoration: InputDecoration(
              labelText: widget.isJa ? 'ユーザー名' : 'Username',
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _emailCtrl,
            keyboardType: TextInputType.emailAddress,
            decoration: InputDecoration(
              labelText: widget.isJa ? 'メールアドレス' : 'Email Address',
              hintText: 'name@example.com',
            ),
          ),
          if (_errText != null) ...[
            const SizedBox(height: 10),
            Text(_errText!, style: const TextStyle(color: Color(0xFFFF3B30), fontSize: 13)),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.of(context).pop(null),
          child: Text(widget.isJa ? 'キャンセル' : 'Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: const Color(0xFFFF3B30)),
          onPressed: _submitting ? null : _submit,
          child: Text(widget.isJa ? '保存' : 'Save'),
        ),
      ],
    );
  }
}
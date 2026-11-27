import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:calendar_frontend/initialSetupPage.dart';

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
  late bool _enableNotifications;
  late TextEditingController _emailController;
  DateTime? _birthday;
  bool _isSaving = false;

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
    _enableNotifications = widget.initialSettings.enableNotifications;
    _emailController = TextEditingController(text: widget.initialSettings.email);
    if (widget.initialSettings.birthday.isNotEmpty) {
      _birthday = DateTime.tryParse(widget.initialSettings.birthday);
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  String _formatBirthday(DateTime? dt) {
    if (dt == null) return _isJa ? '未設定' : 'Not set';
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  Future<void> _pickBirthday() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _birthday ?? DateTime(2000, 1, 1),
      firstDate: DateTime(1920, 1, 1),
      lastDate: now,
    );
    if (picked != null) {
      setState(() => _birthday = picked);
    }
  }

  Future<void> _saveSettings() async {
    if (_isSaving) return;
    final emailText = _emailController.text.trim();
    if (emailText.isNotEmpty && !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(emailText)) {
      _showSnack(_isJa ? '有効なメールアドレスを入力してください。' : 'Please enter a valid email address.', isError: true);
      return;
    }

    setState(() => _isSaving = true);
    try {
      final bdayStr = _birthday == null ? '' : _formatBirthday(_birthday);
      final response = await http.put(
        Uri.parse('${widget.backendBaseUrl}/api/auth/settings'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${widget.authToken}',
        },
        body: jsonEncode({
          'email': emailText,
          'birthday': bdayStr,
          'currency': _currency,
          'timezone': _timezone,
          'language': _language,
          'enableTodoList': _enableTodoList,
          'enablePayroll': _enablePayroll,
          'enableNotifications': _enableNotifications,
          'setupComplete': true,
        }),
      );

      final Map<String, dynamic> data = response.body.isNotEmpty
          ? jsonDecode(response.body) as Map<String, dynamic>
          : {};

      if (response.statusCode == 200) {
        final updated = UserAppSettings.fromJson(data);
        await updated.saveToCache();
        widget.onSettingsUpdated(updated);
        if (mounted) {
          _showSnack(_isJa ? '設定を保存しました。' : 'Settings saved.');
        }
      } else {
        _showSnack(
          data['error']?.toString() ?? (_isJa ? '保存に失敗しました。' : 'Failed to save settings.'),
          isError: true,
        );
      }
    } catch (_) {
      _showSnack(_isJa ? '通信エラーが発生しました。' : 'Network error.', isError: true);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _showChangePasswordDialog() async {
    final currentCtrl = TextEditingController();
    final newCtrl = TextEditingController();
    final confirmCtrl = TextEditingController();
    bool obscure1 = true;
    bool obscure2 = true;
    bool submitting = false;
    String? errText;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(_isJa ? 'パスワードを変更' : 'Change Password'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: currentCtrl,
                obscureText: obscure1,
                decoration: InputDecoration(
                  labelText: _isJa ? '現在のパスワード' : 'Current Password',
                  suffixIcon: IconButton(
                    icon: Icon(obscure1 ? CupertinoIcons.eye : CupertinoIcons.eye_slash, size: 18),
                    onPressed: () => setDialogState(() => obscure1 = !obscure1),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: newCtrl,
                obscureText: obscure2,
                decoration: InputDecoration(
                  labelText: _isJa ? '新しいパスワード（6文字以上）' : 'New Password (min 6 chars)',
                  suffixIcon: IconButton(
                    icon: Icon(obscure2 ? CupertinoIcons.eye : CupertinoIcons.eye_slash, size: 18),
                    onPressed: () => setDialogState(() => obscure2 = !obscure2),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: confirmCtrl,
                obscureText: obscure2,
                decoration: InputDecoration(
                  labelText: _isJa ? '新しいパスワード（確認）' : 'Confirm New Password',
                ),
              ),
              if (errText != null) ...[
                const SizedBox(height: 10),
                Text(errText!, style: const TextStyle(color: appleRed, fontSize: 13)),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: submitting ? null : () => Navigator.pop(ctx),
              child: Text(_isJa ? 'キャンセル' : 'Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: appleRed),
              onPressed: submitting
                  ? null
                  : () async {
                      if (newCtrl.text.length < 6) {
                        setDialogState(() => errText = _isJa ? '6文字以上で入力してください。' : 'Minimum 6 characters required.');
                        return;
                      }
                      if (newCtrl.text != confirmCtrl.text) {
                        setDialogState(() => errText = _isJa ? '新しいパスワードが一致しません。' : 'New passwords do not match.');
                        return;
                      }
                      setDialogState(() {
                        submitting = true;
                        errText = null;
                      });
                      try {
                        final res = await http.post(
                          Uri.parse('${widget.backendBaseUrl}/api/auth/change-password'),
                          headers: {
                            'Content-Type': 'application/json',
                            'Authorization': 'Bearer ${widget.authToken}',
                          },
                          body: jsonEncode({
                            'currentPassword': currentCtrl.text,
                            'newPassword': newCtrl.text,
                          }),
                        );
                        final body = res.body.isNotEmpty ? jsonDecode(res.body) as Map<String, dynamic> : <String, dynamic>{};
                        if (res.statusCode == 200) {
                          if (ctx.mounted) Navigator.pop(ctx);
                          if (mounted) {
                            _showSnack(_isJa ? 'パスワードを変更しました。' : 'Password changed successfully.');
                          }
                        } else {
                          setDialogState(() => errText = body['error']?.toString() ?? 'Failed to change password');
                        }
                      } catch (_) {
                        setDialogState(() => errText = _isJa ? '通信エラーが発生しました。' : 'Network error.');
                      } finally {
                        setDialogState(() => submitting = false);
                      }
                    },
              child: Text(_isJa ? '変更する' : 'Update'),
            ),
          ],
        ),
      ),
    );
    currentCtrl.dispose();
    newCtrl.dispose();
    confirmCtrl.dispose();
  }

  Future<void> _showDeleteAccountDialog() async {
    final passwordCtrl = TextEditingController();
    bool obscure = true;
    bool deleting = false;
    String? errText;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(
            _isJa ? 'アカウントを削除' : 'Delete Account',
            style: const TextStyle(color: appleRed, fontWeight: FontWeight.w700),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _isJa
                    ? 'アカウントとすべての予定データが完全に削除され、元に戻せません。確認のためパスワードを入力してください。'
                    : 'Your account and all calendar events will be permanently deleted. Enter your password to confirm.',
                style: const TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: passwordCtrl,
                obscureText: obscure,
                decoration: InputDecoration(
                  labelText: _isJa ? 'パスワード' : 'Password',
                  suffixIcon: IconButton(
                    icon: Icon(obscure ? CupertinoIcons.eye : CupertinoIcons.eye_slash, size: 18),
                    onPressed: () => setDialogState(() => obscure = !obscure),
                  ),
                ),
              ),
              if (errText != null) ...[
                const SizedBox(height: 10),
                Text(errText!, style: const TextStyle(color: appleRed, fontSize: 13)),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: deleting ? null : () => Navigator.pop(ctx),
              child: Text(_isJa ? 'キャンセル' : 'Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: appleRed),
              onPressed: deleting
                  ? null
                  : () async {
                      if (passwordCtrl.text.isEmpty) {
                        setDialogState(() => errText = _isJa ? 'パスワードを入力してください。' : 'Please enter your password.');
                        return;
                      }
                      setDialogState(() {
                        deleting = true;
                        errText = null;
                      });
                      try {
                        final res = await http.delete(
                          Uri.parse('${widget.backendBaseUrl}/api/auth/account'),
                          headers: {
                            'Content-Type': 'application/json',
                            'Authorization': 'Bearer ${widget.authToken}',
                          },
                          body: jsonEncode({'password': passwordCtrl.text}),
                        );
                        final body = res.body.isNotEmpty ? jsonDecode(res.body) as Map<String, dynamic> : <String, dynamic>{};
                        if (res.statusCode == 200) {
                          final prefs = await SharedPreferences.getInstance();
                          await prefs.clear();
                          if (ctx.mounted) Navigator.pop(ctx);
                          if (mounted) {
                            Navigator.of(context).popUntil((route) => route.isFirst);
                            widget.onLogout();
                          }
                        } else {
                          setDialogState(() => errText = body['error']?.toString() ?? 'Failed to delete account');
                        }
                      } catch (_) {
                        setDialogState(() => errText = _isJa ? '通信エラーが発生しました。' : 'Network error.');
                      } finally {
                        setDialogState(() => deleting = false);
                      }
                    },
              child: Text(_isJa ? '完全に削除' : 'Delete Forever'),
            ),
          ],
        ),
      ),
    );
    passwordCtrl.dispose();
  }

  void _showSnack(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: appleGroupedBg,
      appBar: AppBar(
        backgroundColor: appleGroupedBg,
        elevation: 0,
        title: Text(
          _isJa ? '設定' : 'Settings',
          style: const TextStyle(color: Colors.black, fontWeight: FontWeight.w700),
        ),
        iconTheme: const IconThemeData(color: appleRed),
        actions: [
          TextButton(
            onPressed: _isSaving ? null : _saveSettings,
            child: _isSaving
                ? const CupertinoActivityIndicator()
                : Text(
                    _isJa ? '保存' : 'Save',
                    style: const TextStyle(color: appleRed, fontSize: 16, fontWeight: FontWeight.w600),
                  ),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: ListView(
            padding: const EdgeInsets.only(bottom: 40),
            children: [
              // ACCOUNT & PROFILE
              _sectionHeader(_isJa ? 'アカウント・プロフィール' : 'Account & Profile'),
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(CupertinoIcons.person_circle, color: appleRed),
                      title: Text(_isJa ? 'ユーザー名' : 'Username'),
                      trailing: Text(widget.username, style: const TextStyle(color: appleSecondaryLabel)),
                    ),
                    const Divider(height: 1, indent: 54, color: appleHairline),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      child: Row(
                        children: [
                          const Icon(CupertinoIcons.mail, color: appleRed, size: 22),
                          const SizedBox(width: 16),
                          Expanded(
                            child: TextField(
                              controller: _emailController,
                              keyboardType: TextInputType.emailAddress,
                              decoration: InputDecoration(
                                labelText: _isJa ? 'メールアドレス' : 'Email Address',
                                border: InputBorder.none,
                              ),
                            ),
                          ),
                        ],
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
                              onPressed: () => setState(() => _birthday = null),
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
                    ListTile(
                      leading: const Icon(CupertinoIcons.globe, color: appleRed),
                      title: Text(_isJa ? '言語' : 'Language'),
                      trailing: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _language,
                          items: const [
                            DropdownMenuItem(value: 'en', child: Text('English')),
                            DropdownMenuItem(value: 'ja', child: Text('日本語')),
                          ],
                          onChanged: (v) {
                            if (v != null) setState(() => _language = v);
                          },
                        ),
                      ),
                    ),
                    const Divider(height: 1, indent: 54, color: appleHairline),
                    ListTile(
                      leading: const Icon(CupertinoIcons.money_dollar_circle, color: appleRed),
                      title: Text(_isJa ? '通貨' : 'Currency'),
                      trailing: CupertinoSlidingSegmentedControl<String>(
                        groupValue: _currency,
                        children: const {
                          'USD': Padding(
                            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                            child: Text('\$ (USD)', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                          ),
                          'JPY': Padding(
                            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                            child: Text('¥ (JPY)', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                          ),
                        },
                        onValueChanged: (v) {
                          if (v != null) setState(() => _currency = v);
                        },
                      ),
                    ),
                    const Divider(height: 1, indent: 54, color: appleHairline),
                    SwitchListTile.adaptive(
                      secondary: const Icon(CupertinoIcons.bell, color: appleRed),
                      title: Text(_isJa ? '通知' : 'Notifications'),
                      subtitle: Text(
                        _isJa ? '予定のリマインダー通知を有効にする' : 'Enable event reminder notifications',
                        style: const TextStyle(fontSize: 12),
                      ),
                      activeColor: appleRed,
                      value: _enableNotifications,
                      onChanged: (v) => setState(() => _enableNotifications = v),
                    ),
                    const Divider(height: 1, indent: 54, color: appleHairline),
                    SwitchListTile.adaptive(
                      secondary: const Icon(CupertinoIcons.checkmark_circle, color: appleRed),
                      title: Text(_isJa ? 'To-Doリスト' : 'To-Do List'),
                      activeColor: appleRed,
                      value: _enableTodoList,
                      onChanged: (v) => setState(() => _enableTodoList = v),
                    ),
                  ],
                ),
              ),

              // SECURITY & ACCOUNT MANAGEMENT
              _sectionHeader(_isJa ? 'セキュリティ・アカウント管理' : 'Security & Account'),
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(CupertinoIcons.lock_rotation, color: appleRed),
                      title: Text(_isJa ? 'パスワードを変更' : 'Change Password'),
                      trailing: const Icon(CupertinoIcons.chevron_forward, size: 16, color: appleSecondaryLabel),
                      onTap: _showChangePasswordDialog,
                    ),
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
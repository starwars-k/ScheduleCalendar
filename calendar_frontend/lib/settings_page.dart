import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:calendar_frontend/initialSetupPage.dart';

class SettingsPage extends StatefulWidget {
  final String backendBaseUrl;
  final String authToken;
  final UserAppSettings currentSettings;
  final Future<void> Function(UserAppSettings updatedSettings) onSettingsChanged;
  final Future<void> Function() onLogout;

  const SettingsPage({
    super.key,
    required this.backendBaseUrl,
    required this.authToken,
    required this.currentSettings,
    required this.onSettingsChanged,
    required this.onLogout,
  });

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  static const Map<String, String> _languageOptions = {
    'en' : 'English',
    'ja' : '日本語 (Japanese)',
  };
  late bool _todoEnabled;
  late bool _payrollEnabled;
  late String _selectedLanguage;
  bool _isSaving = false;

  bool get _isJapanese => _selectedLanguage == 'ja';

  @override
  void initState() {
    super.initState();
    _todoEnabled = widget.currentSettings.enableTodoList;
    _payrollEnabled = widget.currentSettings.enablePayroll;
    _selectedLanguage = _languageOptions.containsKey(widget.currentSettings.language)
      ? widget.currentSettings.language
      : 'en';
  }

  Future<void> _updateSettings({
    bool? nextTodo,
    bool? nextPayroll,
    String? nextLanguage,
  }) async {
    final resolvedTodo = nextTodo ?? _todoEnabled;
    final resolvedPayroll = nextPayroll ?? _payrollEnabled;
    final resolvedLanguage = nextLanguage ?? _selectedLanguage;
    setState(() {
      _todoEnabled = resolvedTodo;
      _payrollEnabled = resolvedPayroll;
      _selectedLanguage = resolvedLanguage;
      _isSaving = true;
    });

    final updated = widget.currentSettings.copyWith(
      language: resolvedLanguage,
      enableTodoList: resolvedTodo,
      enablePayroll: resolvedPayroll,
    );

    await updated.saveToCache();

    try {
      final response = await http.put(
        Uri.parse('${widget.backendBaseUrl}/api/user/settings'),
        headers: {
          'Authorization': 'Bearer ${widget.authToken}',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'timezone': updated.timezone,
          'language': resolvedLanguage,
          'enableTodoList': resolvedTodo,
          'enablePayroll': resolvedPayroll,
          'convertExistingEvents': false,
        }),
      );
      if(response.statusCode == 200 && response.body.isNotEmpty){
        final serverSettings = UserAppSettings.fromJson(
          jsonDecode(response.body) as Map<String, dynamic>,
        );
        await serverSettings.saveToCache();
        await widget.onSettingsChanged(serverSettings);
        if (mounted) setState(() => _isSaving = false);
        return;
      }
    } catch (e) {
      debugPrint('Settings sync warning: $e');
    }

    await widget.onSettingsChanged(updated);

    if (mounted) {
      setState(() => _isSaving = false);
    }
  }

  Widget _buildComingSoonBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.amber.shade100,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        _isJapanese ? '順次追加予定' : 'Coming Soon',
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
    return ListView(
      padding: const EdgeInsets.fromLTRB(16,16,16,110),
      children: [
        Text(
          _isJapanese ? '言語 (Language)' : 'Language',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: DropdownButtonFormField<String>(
              initialValue: _selectedLanguage,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.language),
                border: OutlineInputBorder(),
              ),
              items: _languageOptions.entries.map((entry) {
                return DropdownMenuItem<String>(
                  value: entry.key,
                  child: Text(entry.value),
                );
              }).toList(),
              onChanged: _isSaving
                  ? null
                  : (String? newValue) {
                      if (newValue != null && newValue != _selectedLanguage) {
                        _updateSettings(nextLanguage: newValue);
                      }
                    },
            ),
          ),
        ),
        const SizedBox(height: 24),
        Text(
          _isJapanese ? 'モジュール' : 'Modules',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Card(
          child: Column(
            children: [
              SwitchListTile(
                secondary: const Icon(Icons.check_circle_outline),
                title: Text(_isJapanese ? 'To-Do リスト' : 'To-Do List'),
                subtitle: Text(_isJapanese 
                  ? 'To-Do タブを表示し、期限タスクをカレンダーと同期します'
                  : 'Show To-Do List tab & sync due tasks with calendar'),
                value: _todoEnabled,
                onChanged: _isSaving
                    ? null
                    : (val) => _updateSettings(
                          nextTodo: val,
                          nextPayroll: _payrollEnabled,
                        ),
              ),
              const Divider(height: 1),
              SwitchListTile(
                secondary: const Icon(Icons.payments_outlined),
                title: Wrap(
                  spacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(_isJapanese ? '給与計算(Payroll)' : 'Payroll'),
                    _buildComingSoonBadge(),
                  ],
                ),
                subtitle: Text(
                  _isJapanese
                    ? 'シフト・収入管理用の給与タブを表示します'
                    : 'Show Payroll tab for shift & income tracking'),
                value: false,
                onChanged: null,
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        Text(
          _isJapanese ? 'アカウント' : 'Account',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Card(
          child: ListTile(
            leading: const Icon(Icons.logout, color: Colors.redAccent),
            title: Text(_isJapanese ? 'ログアウト' : 'Log Out'),
            onTap: () => widget.onLogout(),
          ),
        ),
      ],
    );
  }
}
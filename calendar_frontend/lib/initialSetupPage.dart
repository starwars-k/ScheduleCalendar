import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

const List<String> kSupportedTimezones = [
  'America/Chicago',
  'America/New_York',
  'America/Los_Angeles',
  'America/Denver',
  'Asia/Tokyo',
  'Europe/London',
  'Europe/Paris',
  'UTC',
];

class UserAppSettings {
  final String timezone;
  final String language; // 'en' or 'ja'
  final bool enableTodoList;
  final bool enablePayroll;
  final bool setupCompleted;

  const UserAppSettings({
    this.timezone = 'America/Chicago',
    this.language = 'en',
    this.enableTodoList = false,
    this.enablePayroll = false,
    this.setupCompleted = false,
  });

  factory UserAppSettings.fromJson(Map<String, dynamic> json) {
    return UserAppSettings(
      timezone: json['timezone']?.toString() ?? 'America/Chicago',
      language: json['language']?.toString() ?? 'en',
      enableTodoList: json['enableTodoList'] is bool
          ? json['enableTodoList'] as bool
          : false,
      enablePayroll: json['enablePayroll'] is bool
          ? json['enablePayroll'] as bool
          : false,
      setupCompleted: json['setupCompleted'] is bool
          ? json['setupCompleted'] as bool
          : false,
    );
  }

  Map<String, dynamic> toJson() => {
        'timezone': timezone,
        'language': language,
        'enableTodoList': enableTodoList,
        'enablePayroll': enablePayroll,
        'setupCompleted': setupCompleted,
      };

  Future<void> saveToCache() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('auth_user_settings', jsonEncode(toJson()));
  }

  static Future<UserAppSettings> loadFromCache() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('auth_user_settings');
    if (raw == null || raw.isEmpty) {
      return const UserAppSettings();
    }
    try {
      return UserAppSettings.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return const UserAppSettings();
    }
  }
}

class InitialSetupPage extends StatefulWidget {
  final String backendBaseUrl;
  final String authToken;
  final String username;
  final UserAppSettings initialSettings;
  final void Function(UserAppSettings updatedSettings) onSetupComplete;

  const InitialSetupPage({
    super.key,
    required this.backendBaseUrl,
    required this.authToken,
    required this.username,
    required this.initialSettings,
    required this.onSetupComplete,
  });

  @override
  State<InitialSetupPage> createState() => _InitialSetupPageState();
}

class _InitialSetupPageState extends State<InitialSetupPage> {
  static const Map<String, String> _languageOptions = {
    'en': 'English',
    'ja': '日本語 (Japanese)',
  };

  late String _selectedTimezone;
  late String _selectedLanguage;
  late bool _enableTodoList;
  late bool _enablePayroll;
  bool _isSaving = false;
  String? _errorMessage;

  bool get _isJapanese => _selectedLanguage == 'ja';

  @override
  void initState() {
    super.initState();
    _selectedTimezone =
        kSupportedTimezones.contains(widget.initialSettings.timezone)
            ? widget.initialSettings.timezone
            : 'America/Chicago';
    _selectedLanguage =
        _languageOptions.containsKey(widget.initialSettings.language)
            ? widget.initialSettings.language
            : 'en';
    _enableTodoList = widget.initialSettings.enableTodoList;
    _enablePayroll = widget.initialSettings.enablePayroll;
  }

  Future<void> _saveAndContinue() async {
    if (_isSaving) return;
    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    try {
      final response = await http.put(
        Uri.parse('${widget.backendBaseUrl}/api/user/settings'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${widget.authToken}',
        },
        body: jsonEncode({
          'timezone': _selectedTimezone,
          'language': _selectedLanguage,
          'enableTodoList': _enableTodoList,
          'enablePayroll': _enablePayroll,
          'convertExistingEvents': true,
        }),
      );

      final Map<String, dynamic> data = response.body.isNotEmpty
          ? jsonDecode(response.body) as Map<String, dynamic>
          : <String, dynamic>{};

      if (response.statusCode == 200) {
        final updatedSettings = UserAppSettings.fromJson(data);
        await updatedSettings.saveToCache();

        if (!mounted) return;
        widget.onSetupComplete(updatedSettings);
      } else {
        setState(() {
          _errorMessage = data['error']?.toString() ??
              'Failed to save settings (${response.statusCode})';
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Network error: $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
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
    return Scaffold(
      appBar: AppBar(
        title: Text(_isJapanese ? '初期設定' : 'Initial Setup'),
        automaticallyImplyLeading: false,
      ),
      body: AbsorbPointer(
        absorbing: _isSaving,
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    _isJapanese
                        ? 'ようこそ、${widget.username} さん！'
                        : 'Welcome, ${widget.username}!',
                    style: Theme.of(context).textTheme.headlineSmall,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8.0),
                  Text(
                    _isJapanese
                        ? 'カレンダーを始める前に基本設定を行ってください。'
                        : 'Configure your preferences before opening your calendar.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Colors.grey[700],
                        ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 28.0),

                  // 1. 言語設定
                  Text(
                    _isJapanese ? '言語 (Language)' : 'Language',
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8.0),
                  DropdownButtonFormField<String>(
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
                    onChanged: (String? newValue) {
                      if (newValue != null) {
                        setState(() => _selectedLanguage = newValue);
                      }
                    },
                  ),
                  const SizedBox(height: 20.0),

                  // 2. タイムゾーン設定
                  Text(
                    _isJapanese ? 'デフォルトのタイムゾーン' : 'Default Timezone',
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8.0),
                  DropdownButtonFormField<String>(
                    initialValue: _selectedTimezone,
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.public),
                      border: OutlineInputBorder(),
                    ),
                    items: kSupportedTimezones.map((String tzName) {
                      return DropdownMenuItem<String>(
                        value: tzName,
                        child: Text(tzName),
                      );
                    }).toList(),
                    onChanged: (String? newValue) {
                      if (newValue != null) {
                        setState(() => _selectedTimezone = newValue);
                      }
                    },
                  ),
                  const SizedBox(height: 24.0),

                  // 3. 追加予定機能のオンオフ
                  Text(
                    _isJapanese ? '追加機能の有効化' : 'Optional Modules',
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4.0),
                  Text(
                    _isJapanese
                        ? '実装された際に利用したい機能を選択できます（後から変更可能）。'
                        : 'Choose which upcoming modules you want enabled once released.',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                  const SizedBox(height: 8.0),
                  Card(
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(color: Colors.grey.shade300),
                    ),
                    child: Column(
                      children: [
                        SwitchListTile(
                          secondary: const Icon(Icons.check_box_outlined),
                          title: Wrap(
                            spacing: 8,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Text(_isJapanese ? 'To-Do リスト' : 'To-Do List'),
                              _buildComingSoonBadge(),
                            ],
                          ),
                          subtitle: Text(
                            _isJapanese
                                ? 'タスクやチェックリストの管理機能'
                                : 'Manage daily tasks and checklists',
                          ),
                          value: _enableTodoList,
                          onChanged: (val) => setState(() => _enableTodoList = val),
                        ),
                        const Divider(height: 1),
                        SwitchListTile(
                          secondary: const Icon(Icons.payments_outlined),
                          title: Wrap(
                            spacing: 8,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Text(_isJapanese ? '給与計算' : 'Payroll / Salary Calculator'),
                              _buildComingSoonBadge(),
                            ],
                          ),
                          subtitle: Text(
                            _isJapanese
                                ? 'シフトや勤務時間からの給料自動計算'
                                : 'Calculate earnings from work shifts and hours',
                          ),
                          value: _enablePayroll,
                          onChanged: (val) => setState(() => _enablePayroll = val),
                        ),
                      ],
                    ),
                  ),
                  if (_errorMessage != null) ...[
                    const SizedBox(height: 12.0),
                    Text(_errorMessage!, style: const TextStyle(color: Colors.red)),
                  ],
                  const SizedBox(height: 28.0),

                  ElevatedButton(
                    onPressed: _isSaving ? null : _saveAndContinue,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14.0),
                    ),
                    child: _isSaving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2.0),
                          )
                        : Text(
                            _isJapanese ? '保存してカレンダーへ進む' : 'Save & Go to Calendar',
                            style: const TextStyle(fontSize: 16),
                          ),
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
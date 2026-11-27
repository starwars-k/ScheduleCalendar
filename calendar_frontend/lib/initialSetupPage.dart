import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
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
  final bool setupComplete;

  const UserAppSettings({
    this.timezone = 'America/Chicago',
    this.language = 'en',
    this.enableTodoList = false,
    this.enablePayroll = false,
    this.setupComplete = false,
  });

  factory UserAppSettings.fromJson(Map<String, dynamic> json) {
    return UserAppSettings(
      timezone: json['timezone']?.toString() ?? 'America/Chicago',
      language: json['language']?.toString() ?? 'en',
      enableTodoList: json['enableTodoList'] is bool
          ? json['enableTodoList'] as bool
          : false,
      enablePayroll: false,
      setupComplete: json['setupComplete'] is bool
        ? json['setupComplete'] as bool
        : false,
    );
  }

  Map<String, dynamic> toJson() => {
    'timezone': timezone,
    'language': language,
    'enableTodoList': enableTodoList,
    'enablePayroll': enablePayroll,
    'setupComplete': setupComplete,
  };
  
  UserAppSettings copyWith({
    String? timezone,
    String? language,
    bool? enableTodoList,
    bool? enablePayroll,
    bool? setupComplete,
  }) {
    return UserAppSettings(
      timezone: timezone ?? this.timezone,
      language: language ?? this.language,
      enableTodoList: enableTodoList ?? this.enableTodoList,
      enablePayroll: enablePayroll ?? this.enablePayroll,
      setupComplete: setupComplete ?? this.setupComplete,
    );
  }

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
          'enablePayroll': false,
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
    const Color appleRed = Color(0xFFFF3B30);
    const Color appleGroupedBg = Color(0xFFF2F2F7);
    const Color appleHairline = Color(0xFFE5E5EA);
    const Color appleSecondaryLabel = Color(0xFF8E8E93);

    Widget buildSectionHeader(String title) {
      return Padding(
        padding: const EdgeInsets.only(left: 16, bottom: 6),
        child: Text(
          title,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.4,
            color: appleSecondaryLabel,
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: appleGroupedBg,
      body: AbsorbPointer(
        absorbing: _isSaving,
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 36),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      _isJapanese
                          ? 'ようこそ、${widget.username} さん'
                          : 'Welcome, ${widget.username}',
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
                      _isJapanese
                          ? 'カレンダーを始める前に基本設定を行ってください'
                          : 'Configure your preferences before opening your calendar',
                      style: const TextStyle(fontSize: 14, color: appleSecondaryLabel),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 26),

                    buildSectionHeader(_isJapanese ? '一般設定' : 'PREFERENCES'),
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                            child: Row(
                              children: [
                                const Icon(CupertinoIcons.globe, color: appleRed, size: 22),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    _isJapanese ? '表示言語' : 'Language',
                                    style: const TextStyle(fontSize: 15, color: Colors.black),
                                  ),
                                ),
                                DropdownButtonHideUnderline(
                                  child: DropdownButton<String>(
                                    value: _selectedLanguage,
                                    icon: const Icon(
                                      CupertinoIcons.chevron_up_chevron_down,
                                      size: 16,
                                      color: appleSecondaryLabel,
                                    ),
                                    style: const TextStyle(fontSize: 15, color: appleSecondaryLabel),
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
                                ),
                              ],
                            ),
                          ),
                          const Divider(height: 1, thickness: 0.5, indent: 50, color: appleHairline),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                            child: Row(
                              children: [
                                const Icon(CupertinoIcons.clock, color: appleRed, size: 22),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    _isJapanese ? 'タイムゾーン' : 'Timezone',
                                    style: const TextStyle(fontSize: 15, color: Colors.black),
                                  ),
                                ),
                                DropdownButtonHideUnderline(
                                  child: DropdownButton<String>(
                                    value: _selectedTimezone,
                                    icon: const Icon(
                                      CupertinoIcons.chevron_up_chevron_down,
                                      size: 16,
                                      color: appleSecondaryLabel,
                                    ),
                                    style: const TextStyle(fontSize: 14, color: appleSecondaryLabel),
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
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 22),

                    buildSectionHeader(_isJapanese ? 'モジュール' : 'OPTIONAL MODULES'),
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                            child: Row(
                              children: [
                                const Icon(CupertinoIcons.checkmark_circle, color: appleRed, size: 22),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        _isJapanese ? 'To-Do リスト' : 'To-Do List',
                                        style: const TextStyle(fontSize: 15, color: Colors.black),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        _isJapanese
                                            ? 'タスクやチェックリストの管理機能'
                                            : 'Manage daily tasks and checklists',
                                        style: const TextStyle(fontSize: 12, color: appleSecondaryLabel),
                                      ),
                                    ],
                                  ),
                                ),
                                CupertinoSwitch(
                                  value: _enableTodoList,
                                  activeTrackColor: appleRed,
                                  onChanged: (val) => setState(() => _enableTodoList = val),
                                ),
                              ],
                            ),
                          ),
                          const Divider(height: 1, thickness: 0.5, indent: 50, color: appleHairline),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                            child: Row(
                              children: [
                                const Icon(
                                  CupertinoIcons.money_dollar_circle,
                                  color: appleSecondaryLabel,
                                  size: 22,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Wrap(
                                        spacing: 8,
                                        crossAxisAlignment: WrapCrossAlignment.center,
                                        children: [
                                          Text(
                                            _isJapanese ? '給与計算' : 'Payroll',
                                            style: const TextStyle(fontSize: 15, color: Colors.black),
                                          ),
                                          _buildComingSoonBadge(),
                                        ],
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        _isJapanese
                                            ? 'シフトや勤務時間からの給料自動計算'
                                            : 'Calculate earnings from work shifts and hours',
                                        style: const TextStyle(fontSize: 12, color: appleSecondaryLabel),
                                      ),
                                    ],
                                  ),
                                ),
                                const CupertinoSwitch(value: false, onChanged: null),
                              ],
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
                    const SizedBox(height: 26),
                    CupertinoButton(
                      color: appleRed,
                      borderRadius: BorderRadius.circular(12),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      onPressed: _isSaving ? null : _saveAndContinue,
                      child: _isSaving
                          ? const CupertinoActivityIndicator(color: Colors.white)
                          : Text(
                              _isJapanese ? '保存してカレンダーへ進む' : 'Save & Continue',
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
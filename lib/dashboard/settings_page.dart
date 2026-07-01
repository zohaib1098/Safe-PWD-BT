import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vibration/vibration.dart';
import 'package:flutter_tts/flutter_tts.dart';
import '../ble/ble_status_card.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final FlutterTts _tts = FlutterTts();

  bool _enableTTS = true;
  bool _enableVibration = true;
  bool _autoSiren = false;

  @override
  void initState() {
    super.initState();
    _initTTS();
    _loadSettings();
  }

  @override
  void dispose() {
    _tts.stop();
    super.dispose();
  }

  Future<void> _initTTS() async {
    await _tts.setLanguage("en-US");
    await _tts.setSpeechRate(0.5);
    await _tts.setVolume(1.0);
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _enableTTS = prefs.getBool('enableTTS') ?? true;
      _enableVibration = prefs.getBool('enableVibration') ?? true;
      _autoSiren = prefs.getBool('autoSiren') ?? false;
    });
  }

  Future<void> _updateSetting(String key, dynamic value) async {
    final prefs = await SharedPreferences.getInstance();
    if (value is bool) await prefs.setBool(key, value);
    if (value is String) await prefs.setString(key, value);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Setting Saved"),
          duration: Duration(milliseconds: 500),
        ),
      );
      _loadSettings();
    }
  }

  void _runDiagnosticTest() async {
    if (_enableTTS) {
      await _tts.speak("Diagnostic test successful. Voice guidance is active.");
    }
    if (_enableVibration) {
      bool? hasVib = await Vibration.hasVibrator();
      if (hasVib == true) Vibration.vibrate(duration: 500);
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Test complete. Check device feedback.")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── 🆕 ESP32 Wearable BLE Section ──────────────────────────
          _buildHeader("ESP32 Wearable"),
          const BleStatusCard(),

          // ── Alert Preferences ──────────────────────────────────────
          _buildHeader("Alert Preferences"),
          _buildSwitchTile(
            "Voice Guidance",
            "Announce hazards",
            Icons.record_voice_over,
            _enableTTS,
            (val) => _updateSetting('enableTTS', val),
          ),
          _buildSwitchTile(
            "Haptic Feedback",
            "Vibration for alerts",
            Icons.vibration,
            _enableVibration,
            (val) => _updateSetting('enableVibration', val),
          ),
          _buildSwitchTile(
            "Automatic Siren",
            "Trigger alarm on risk",
            Icons.volume_up,
            _autoSiren,
            (val) => _updateSetting('autoSiren', val),
          ),

          // ── System Diagnostics ─────────────────────────────────────
          const SizedBox(height: 24),
          _buildHeader("System Diagnostics"),
          Card(
            margin: EdgeInsets.zero,
            child: ListTile(
              leading:
                  const Icon(Icons.security_update_good, color: Colors.green),
              title: const Text("Run Safety System Test"),
              onTap: _runDiagnosticTest,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(String title) => Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 8, top: 16),
        child: Text(
          title.toUpperCase(),
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: Colors.grey,
          ),
        ),
      );

  Widget _buildSwitchTile(
    String title,
    String subtitle,
    IconData icon,
    bool value,
    Function(bool) onChanged,
  ) =>
      Card(
        margin: const EdgeInsets.symmetric(vertical: 4),
        child: SwitchListTile(
          secondary: Icon(icon),
          title: Text(title),
          subtitle: Text(subtitle),
          value: value,
          onChanged: onChanged,
        ),
      );
}

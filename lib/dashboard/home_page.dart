import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:vibration/vibration.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:safe_pwd/services/notification_service.dart';
import 'package:safe_pwd/services/ble_service.dart'; // 🆕 For battery monitoring
import 'dart:async';
import 'package:rxdart/rxdart.dart';
import 'package:intl/intl.dart';

// Page Imports
import '../core/constants/app_colors.dart';
import 'alerts_page.dart';
import 'dashboard_home_content.dart';
import 'settings_page.dart';
import 'profile_page.dart';
import 'emergency_page.dart';

class HomePage extends StatefulWidget {
  final bool startWithAlert; // Passed from main.dart if initialMessage != null
  const HomePage({super.key, this.startWithAlert = false});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _currentIndex = 0;
  String userName = "Loading...";
  String userEmail = "";
  String _userMode = "both";
  // String? _lastAlertId;

  final FlutterTts _tts = FlutterTts();
  StreamSubscription? _alertSubscription;
  Timer? _batteryCheckTimer; // 🆕 Battery monitoring timer

  // Navigation Logic
  List<Widget> get _pages => [
    const DashboardHomeContent(),
    const AlertsPage(),
    const SettingsPage(),
    ProfilePage(userEmail: userEmail),
    const EmergencyContactPage(),
  ];

  @override
  void initState() {
    super.initState();
    _initialSetup();

    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      _triggerAccessibilityAlert(
        message.data['body'] ?? "Emergency Alert",
        "fcm_open",
      );
    });

    // If we were woken up by a notification, trigger immediate feedback
    if (widget.startWithAlert) {
      _triggerAccessibilityAlert("Emergency Alert Received", "system_init");
    }
  }

  @override
  void dispose() {
    _alertSubscription?.cancel();
    _batteryCheckTimer?.cancel(); // 🆕 Cancel battery monitoring
    _tts.stop();
    super.dispose();
  }

  Future<void> _initialSetup() async {
    await _loadUserPreferences();
    _startAlertListener();
    _startBatteryMonitoring(); // 🆕 Monitor wearable battery level
  }

  Future<void> _loadUserPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _userMode = prefs.getString('userMode') ?? "both";
      userName = prefs.getString('userName') ?? "User";
      userEmail = prefs.getString('userEmail') ?? "";
    });
  }

  void _startAlertListener() {
    final now = DateTime.now();

    // Format for the 'advisories' table (e.g., "26-04-2026")
    final String todayStr = DateFormat('dd-MM-yyyy').format(now);

    // Start of today for 'alerts' (Timestamp comparison)
    final DateTime startOfToday = DateTime(now.year, now.month, now.day);

    // 1. Stream for 'alerts' collection (Filters by Timestamp)
    Stream<List<Map<String, dynamic>>> alertsStream = FirebaseFirestore.instance
        .collection('alerts')
        .where('isActive', isEqualTo: true)
        .where('severity', whereIn: ['Critical', 'High'])
        .where(
          'createdAt',
          isGreaterThanOrEqualTo: Timestamp.fromDate(startOfToday),
        )
        .snapshots()
        .map(
          (snap) => snap.docs.map((doc) {
            final data = doc.data();
            return {
              ...data,
              'id': doc.id,
              'source_table': 'alerts',
              'displayDate': (data['createdAt'] as Timestamp).toDate(),
            };
          }).toList(),
        );

    // 2. Stream for 'advisories' collection (Filters by Date String)
    Stream<List<Map<String, dynamic>>> advisoriesStream = FirebaseFirestore
        .instance
        .collection('advisories')
        .where('date', isEqualTo: todayStr)
        .snapshots()
        .map(
          (snap) => snap.docs.map((doc) {
            final data = doc.data();
            return {
              ...data,
              'id': doc.id,
              'source_table': 'advisories',
              // Parse string date back to DateTime for sorting
              'displayDate': DateFormat('dd-MM-yyyy').parse(data['date']),
            };
          }).toList(),
        );

    // 3. Combine both streams into one
    _alertSubscription =
        Rx.combineLatest2(
          alertsStream,
          advisoriesStream,
          (a, b) => [...a, ...b],
        ).listen((combinedList) async {
          if (combinedList.isEmpty) return;

          final prefs = await SharedPreferences.getInstance();
          final String? userEmail = prefs.getString(
            'userEmail',
          ); // Get email from prefs since no Auth
          if (userEmail == null) return;

          for (var alert in combinedList) {
            final String alertId = alert['id'];

            // Check if this specific user has already acknowledged this alert
            bool localSeen =
                prefs.getBool("${userEmail}_seen_$alertId") ?? false;
            List seenByList = alert['seenBy'] ?? [];
            bool cloudSeen = seenByList.contains(userEmail);

            if (!localSeen && !cloudSeen) {
              // THIS IS THE TRIGGER
              _triggerAccessibilityAlert(alert['title'], alertId);

              // Auto-mark as seen so it doesn't pop up again every time the stream updates
              await _markAsSeenInDB(alertId, alert['source_table']);
            }
          }
        });
  }

  Future<void> _markAsSeenInDB(String alertId, String collectionName) async {
    if (userEmail.isEmpty) return;

    try {
      // 1. Update the specific collection (alerts or advisories)
      await FirebaseFirestore.instance
          .collection(collectionName)
          .doc(alertId)
          .update({
            'seenBy': FieldValue.arrayUnion([userEmail]),
          });

      // 2. Update Local Prefs (SharedPref key stays unique to the alertId)
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool("${userEmail}_seen_$alertId", true);

      debugPrint(
        "Item $alertId in $collectionName marked as seen for $userEmail",
      );
    } catch (e) {
      // If a table (like advisories) doesn't have the 'seenBy' field yet,
      // Firestore might throw an error. You can use set with merge:true to be safe.
      debugPrint("Auto-save to DB failed for $collectionName: $e");

      // Alternative: Use set with merge if you want to create the field if it's missing
      /*
    await FirebaseFirestore.instance.collection(collectionName).doc(alertId).set(
      {'seenBy': FieldValue.arrayUnion([userEmail])}, 
      SetOptions(merge: true)
    );
    */
    }
  }

  // 🆕 BATTERY MONITORING - Check ESP32 battery level every 5 minutes
  void _startBatteryMonitoring() {
    _batteryCheckTimer = Timer.periodic(const Duration(minutes: 5), (_) async {
      final ble = BleService();
      if (ble.isConnected) {
        debugPrint('[BATTERY] 🔋 Checking wearable battery level...');
        await ble.requestBatteryStatus();
      } else {
        debugPrint('[BATTERY] ⚠️ ESP32 not connected, skipping battery check');
      }
    });
    
    // Also check immediately on app start
    Future.delayed(const Duration(seconds: 2), () {
      final ble = BleService();
      if (ble.isConnected) {
        debugPrint('[BATTERY] 🔋 Initial battery check on app start...');
        ble.requestBatteryStatus();
      }
    });
  }

  // ✅ VISUAL HELPER
  Widget _getAlertVisual(String title, {double size = 150}) {
    final t = title.toLowerCase();
    String imagePath = 'assets/images/warning.png';
    if (t.contains('fire'))
      imagePath = 'assets/images/fire.png';
    else if (t.contains('flood') || t.contains('rain'))
      imagePath = 'assets/images/flood.png';
    else if (t.contains('storm') || t.contains('cyclone'))
      imagePath = 'assets/images/storm.png';
    else if (t.contains('earthquake'))
      imagePath = 'assets/images/earthquake.png';
    else if (t.contains('medical'))
      imagePath = 'assets/images/medical.png';

    return Image.asset(
      imagePath,
      width: size,
      height: size,
      fit: BoxFit.contain,
      errorBuilder: (context, error, stackTrace) =>
          Icon(Icons.warning, color: Colors.white, size: size),
    );
  }

  // ✅ ACCESSIBILITY ALERT TRIGGER
  void _triggerAccessibilityAlert(String title, String alertId) async {
    NotificationService.showHighRiskNotification(
      title: "⚠️ EMERGENCY",
      body: title,
    );

    if (_userMode == "blind") {
      await _tts.setLanguage("en-US");
      await _tts.setSpeechRate(0.5);
      await _tts.speak("Emergency Alert: $title. Please check the dashboard.");
    }

    // 3. Vibration Logic
    if (_userMode == "deaf") {
      if (await Vibration.hasVibrator()) {
        Vibration.vibrate(
          pattern: [0, 1000, 500, 1000, 500, 1000],
          repeat: 0, // loops from index 0
        );

        // Stop after 5 minutes
        Future.delayed(Duration(minutes: 5), () {
          Vibration.cancel();
        });
      }
    }

    if (_userMode == "both") {
      if (await Vibration.hasVibrator()) {
        Vibration.vibrate(pattern: [0, 1000, 500, 1000]);
      }
    }

    if (_userMode == "deaf") {
      if (!mounted) return;
      showGeneralDialog(
        context: context,
        barrierDismissible: false,
        pageBuilder: (context, anim1, anim2) {
          return WillPopScope(
            onWillPop: () async => false,
            child: Scaffold(
              backgroundColor: const Color(0xFFB71C1C),
              body: Center(
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _getAlertVisual(title, size: 220),
                      const SizedBox(height: 40),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Text(
                          title.toUpperCase(),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 26,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      const SizedBox(height: 60),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 40),
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white,
                            minimumSize: const Size(double.infinity, 70),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20),
                            ),
                          ),
                          onPressed: () {
                            Vibration.cancel();
                            Navigator.of(context).pop();
                          },
                          child: const Text(
                            "DISMISS / I AM SAFE",
                            style: TextStyle(
                              color: Colors.red,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    IconData modeIcon = _userMode == 'blind'
        ? Icons.record_voice_over
        : _userMode == 'deaf'
        ? Icons.vibration
        : Icons.all_inclusive;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: const Color.fromARGB(255, 220, 33, 33),
        title: Row(
          children: [
            CircleAvatar(
              backgroundColor: Colors.white24,
              child: Text(
                userName.isNotEmpty ? userName[0] : "U",
                style: const TextStyle(color: Colors.white),
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Welcome, $userName',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const Text(
                  'Safety Dashboard',
                  style: TextStyle(fontSize: 11, color: Colors.white70),
                ),
              ],
            ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Icon(modeIcon, color: Colors.white),
          ),
        ],
      ),
      body: _pages[_currentIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        selectedItemColor: AppColors.primary,
        unselectedItemColor: Colors.grey,
        type: BottomNavigationBarType.fixed,
        onTap: (index) => setState(() => _currentIndex = index),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home_filled), label: 'Home'),
          BottomNavigationBarItem(
            icon: Icon(Icons.warning_rounded),
            label: 'Alerts',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.settings_suggest),
            label: 'Settings',
          ),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Profile'),
          BottomNavigationBarItem(
            icon: Icon(Icons.emergency_share),
            label: 'SOS',
          ),
        ],
      ),
    );
  }
}

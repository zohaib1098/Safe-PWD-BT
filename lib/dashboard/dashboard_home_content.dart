import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;

class _C {
  static const pageBg = Color(0xFFF5F6F8);
  static const surface = Color(0xFFFFFFFF);
  static const border = Color(0xFFE2E5EC);

  static const text = Color(0xFF1A1D23);
  static const text2 = Color(0xFF6B7280);
  static const textMuted = Color(0xFF9EA5B5);

  // Green (safe / clear)
  static const greenBg = Color(0xFFEAF3DE);
  static const greenBorder = Color(0xFFC0DD97);
  static const green = Color(0xFF3B6D11);
  static const greenDark = Color(0xFF27500A);
  static const greenMid = Color(0xFF639922);

  // Blue (info / location)
  static const blueBg = Color(0xFFEEF4FF);
  static const blueBorder = Color(0xFFBDD1F8);
  static const blue = Color(0xFF378ADD);
  static const blueDark = Color(0xFF185FA5);

  // Amber (weather)
  static const amberBg = Color(0xFFFEF3C7);
  static const amberBorder = Color(0xFFFDE68A);
  static const amber = Color(0xFFD97706);

  // Red (siren)
  static const redBg = Color(0xFFFFF5F5);
  static const redBorder = Color(0xFFFECACA);
  static const redBorder2 = Color(0xFFFCA5A5);
  static const red = Color(0xFFE24B4A);
  static const redDark = Color(0xFFA32D2D);
  static const redChip = Color(0xFFFECACA);
}

class DashboardHomeContent extends StatefulWidget {
  const DashboardHomeContent({super.key});

  @override
  State<DashboardHomeContent> createState() => _DashboardHomeContentState();
}

class _DashboardHomeContentState extends State<DashboardHomeContent>
    with SingleTickerProviderStateMixin {
  String _temp = '—';
  String _weatherStatus = 'Fetching...';
  String _city = '—';
  String _area = 'Detecting...';
  IconData _weatherIcon = Icons.wb_sunny_rounded;

  late AnimationController _pulseCtrl;
  late Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
    _pulseAnim = Tween<double>(
      begin: 1.0,
      end: 1.75,
    ).animate(CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeOut));
    _fetchLiveStatus();
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  Future<void> _fetchLiveStatus() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() => _city = 'Enable GPS');
        await Geolocator.openLocationSettings();
        return;
      }

      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
        if (perm == LocationPermission.denied) {
          setState(() => _city = 'Permission Denied');
          return;
        }
      }
      if (perm == LocationPermission.deniedForever) {
        setState(() => _city = 'Settings Required');
        await Geolocator.openAppSettings();
        return;
      }

      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.low,
      );
      final marks = await placemarkFromCoordinates(pos.latitude, pos.longitude);
      final p = marks[0];

      final url = Uri.parse(
        'https://api.open-meteo.com/v1/forecast'
        '?latitude=${pos.latitude}&longitude=${pos.longitude}'
        '&current_weather=true',
      );
      final res = await http.get(url);

      if (res.statusCode == 200) {
        final data = json.decode(res.body)['current_weather'];
        final code = data['weathercode'] as int;
        setState(() {
          _temp = '${data['temperature']}°C';
          _city = p.locality ?? 'Unknown';
          _area = p.subLocality ?? p.name ?? '';
          _weatherStatus = code == 0 ? 'Clear Sky' : 'Overcast';
          _weatherIcon = code == 0
              ? Icons.wb_sunny_rounded
              : Icons.cloud_rounded;
        });
      }
    } catch (e) {
      debugPrint('Location Error: $e');
      setState(() {
        _temp = 'N/A';
        _city = 'Retry';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _C.pageBg,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _StatusBanner(pulseAnim: _pulseAnim),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _StatCard(
                    label: 'WEATHER',
                    value: _temp,
                    sub: _weatherStatus,
                    icon: _weatherIcon,
                    chipBg: _C.amberBg,
                    chipBorder: _C.amberBorder,
                    iconColor: _C.amber,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _StatCard(
                    label: 'LOCATION',
                    value: _city,
                    valueFontSize: 15,
                    sub: _area.isEmpty ? 'Detecting...' : _area,
                    icon: Icons.location_on_rounded,
                    chipBg: _C.blueBg,
                    chipBorder: _C.blueBorder,
                    iconColor: _C.blue,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            _HazardCard(),
            const SizedBox(height: 10),
            _TipCard(),
            const SizedBox(height: 10),
            _SirenButton(),
          ],
        ),
      ),
    );
  }
}

class _StatusBanner extends StatelessWidget {
  final Animation<double> pulseAnim;
  const _StatusBanner({required this.pulseAnim});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: _C.greenBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _C.greenBorder),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 34,
            height: 34,
            child: Stack(
              alignment: Alignment.center,
              children: [
                AnimatedBuilder(
                  animation: pulseAnim,
                  builder: (_, __) => Transform.scale(
                    scale: pulseAnim.value,
                    child: Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: _C.green.withOpacity(
                            1.0 - (pulseAnim.value - 1.0) / 0.75,
                          ),
                          width: 1.5,
                        ),
                      ),
                    ),
                  ),
                ),
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _C.greenBg,
                    border: Border.all(color: _C.green, width: 1.5),
                  ),
                  child: Center(
                    child: CircleAvatar(radius: 4.5, backgroundColor: _C.green),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'ALL CLEAR',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: _C.greenDark,
                    letterSpacing: 0.07,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  'No active threats detected',
                  style: TextStyle(fontSize: 12, color: _C.greenMid),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
            decoration: BoxDecoration(
              color: _C.greenBg,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: _C.greenBorder),
            ),
            child: Text(
              'Live',
              style: TextStyle(
                fontSize: 11,
                color: _C.green,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final double valueFontSize;
  final String sub;
  final IconData icon;
  final Color chipBg;
  final Color chipBorder;
  final Color iconColor;

  const _StatCard({
    required this.label,
    required this.value,
    this.valueFontSize = 19,
    required this.sub,
    required this.icon,
    required this.chipBg,
    required this.chipBorder,
    required this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _C.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _C.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: chipBg,
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: chipBorder),
            ),
            child: Icon(icon, color: iconColor, size: 18),
          ),
          const SizedBox(height: 10),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: _C.textMuted,
              letterSpacing: 0.07,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            value,
            style: TextStyle(
              fontSize: valueFontSize,
              fontWeight: FontWeight.w600,
              color: _C.text,
              height: 1.1,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            sub,
            style: TextStyle(fontSize: 11, color: _C.text2),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

class _HazardCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
      decoration: BoxDecoration(
        color: _C.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _C.border),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: _C.greenBg,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _C.greenBorder),
            ),
            child: Icon(Icons.warning_amber_rounded, color: _C.green, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Nearby hazards',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: _C.text,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'No active hazards in your area',
                  style: TextStyle(fontSize: 11, color: _C.text2),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
            decoration: BoxDecoration(
              color: _C.greenBg,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: _C.greenBorder),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircleAvatar(radius: 3, backgroundColor: _C.green),
                const SizedBox(width: 5),
                Text(
                  'Clear',
                  style: TextStyle(
                    fontSize: 11,
                    color: _C.greenDark,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TipCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _C.blueBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _C.blueBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: const Color(0xFFDBEAFE),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: _C.blueBorder),
            ),
            child: Icon(Icons.info_outline_rounded, color: _C.blue, size: 16),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'PREPAREDNESS TIP',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: _C.blueDark,
                    letterSpacing: 0.07,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Ensure your emergency kit is easily accessible and reviewed regularly.',
                  style: TextStyle(fontSize: 12, color: _C.blue, height: 1.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SirenButton extends StatefulWidget {
  @override
  State<_SirenButton> createState() => _SirenButtonState();
}

class _SirenButtonState extends State<_SirenButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: () {
        // TODO: implement siren activation
      },
      child: AnimatedScale(
        scale: _pressed ? 0.97 : 1.0,
        duration: const Duration(milliseconds: 100),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 13),
          decoration: BoxDecoration(
            color: _pressed ? const Color(0xFFFEE2E2) : _C.redBg,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _pressed ? _C.redBorder2 : _C.redBorder),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: _C.redChip,
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Icon(Icons.volume_up_rounded, color: _C.red, size: 16),
              ),
              const SizedBox(width: 10),
              Text(
                'Activate hardware siren',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: _C.redDark,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

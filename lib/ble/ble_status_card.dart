import 'package:flutter/material.dart';
import '../services/ble_service.dart';
import 'ble_pairing_page.dart';

/// A card widget showing ESP32 BLE connection status, battery, and test button.
/// Drop this into any page.
class BleStatusCard extends StatelessWidget {
  const BleStatusCard({super.key});

  @override
  Widget build(BuildContext context) {
    final ble = BleService();
    return ListenableBuilder(
      listenable: ble,
      builder: (ctx, _) {
        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // --- Header ---
                Row(
                  children: [
                    const Icon(Icons.watch, color: Color(0xFF2196F3)),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'ESP32 Wearable',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ),
                    _ConnectionBadge(isConnected: ble.isConnected),
                  ],
                ),

                const SizedBox(height: 12),

                if (ble.pairedDeviceId == null)
                  // -- Not paired --
                  _InfoRow(
                    icon: Icons.bluetooth_disabled,
                    color: Colors.grey,
                    text: 'No wearable paired',
                  )
                else ...[
                  // -- Device name --
                  _InfoRow(
                    icon: Icons.bluetooth,
                    color: const Color(0xFF2196F3),
                    text: ble.pairedDeviceName ?? 'ESP32 Wearable',
                  ),

                  const SizedBox(height: 6),

                  // -- Connection status text --
                  _InfoRow(
                    icon: ble.isConnected
                        ? Icons.link
                        : ble.isReconnecting
                            ? Icons.sync
                            : Icons.link_off,
                    color: ble.isConnected
                        ? Colors.green
                        : ble.isReconnecting
                            ? Colors.orange
                            : Colors.red,
                    text: ble.isConnected
                        ? 'Connected'
                        : ble.isReconnecting
                            ? 'Reconnecting...'
                            : 'Disconnected',
                  ),

                  const SizedBox(height: 6),

                  // -- Battery --
                  _BatteryRow(level: ble.batteryLevel),
                ],

                const Divider(height: 24),

                // --- Action buttons ---
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const BleDevicePairingPage(),
                          ),
                        ),
                        icon: const Icon(Icons.bluetooth_searching, size: 18),
                        label: Text(
                          ble.pairedDeviceId == null ? 'Pair Device' : 'Change Device',
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: ble.isConnected
                            ? () => _testVibration(context, ble)
                            : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF2196F3),
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: Colors.grey.shade300,
                        ),
                        icon: const Icon(Icons.vibration, size: 18),
                        label: const Text(
                          'Test Vibration',
                          style: TextStyle(fontSize: 13),
                        ),
                      ),
                    ),
                  ],
                ),

                if (ble.isConnected) ...[
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: TextButton.icon(
                      onPressed: () => ble.requestBatteryStatus(),
                      icon: const Icon(Icons.battery_3_bar, size: 16),
                      label: const Text('Refresh Battery', style: TextStyle(fontSize: 12)),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _testVibration(BuildContext context, BleService ble) async {
    final ok = await ble.sendVibrate();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok ? '📳 Vibration sent to wearable!' : '❌ Failed to send vibration',
        ),
        backgroundColor: ok ? Colors.green : Colors.red,
        duration: const Duration(seconds: 2),
      ),
    );
  }
}

// -----------------------------------------------------------------------
// Helper widgets
// -----------------------------------------------------------------------

class _ConnectionBadge extends StatelessWidget {
  final bool isConnected;
  const _ConnectionBadge({required this.isConnected});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: isConnected ? Colors.green.shade50 : Colors.red.shade50,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isConnected ? Colors.green : Colors.red,
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: isConnected ? Colors.green : Colors.red,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 5),
          Text(
            isConnected ? 'Connected' : 'Disconnected',
            style: TextStyle(
              color: isConnected ? Colors.green.shade700 : Colors.red.shade700,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String text;
  const _InfoRow({required this.icon, required this.color, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: color, size: 16),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: TextStyle(color: color, fontWeight: FontWeight.w500),
          ),
        ),
      ],
    );
  }
}

class _BatteryRow extends StatelessWidget {
  final int level; // -1 = unknown
  const _BatteryRow({required this.level});

  @override
  Widget build(BuildContext context) {
    if (level < 0) {
      return const _InfoRow(
        icon: Icons.battery_unknown,
        color: Colors.grey,
        text: 'Battery unknown — tap Refresh',
      );
    }

    final color = level > 50
        ? Colors.green
        : level > 20
            ? Colors.orange
            : Colors.red;

    IconData icon;
    if (level > 80) icon = Icons.battery_full;
    else if (level > 60) icon = Icons.battery_5_bar;
    else if (level > 40) icon = Icons.battery_3_bar;
    else if (level > 20) icon = Icons.battery_2_bar;
    else                  icon = Icons.battery_1_bar;

    return Row(
      children: [
        Icon(icon, color: color, size: 16),
        const SizedBox(width: 8),
        Text(
          'Battery: $level%',
          style: TextStyle(color: color, fontWeight: FontWeight.w500),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: level / 100.0,
              backgroundColor: Colors.grey.shade200,
              valueColor: AlwaysStoppedAnimation<Color>(color),
              minHeight: 8,
            ),
          ),
        ),
      ],
    );
  }
}

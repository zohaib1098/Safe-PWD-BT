import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import '../services/ble_service.dart';

class BleDevicePairingPage extends StatefulWidget {
  const BleDevicePairingPage({super.key});

  @override
  State<BleDevicePairingPage> createState() => _BleDevicePairingPageState();
}

class _BleDevicePairingPageState extends State<BleDevicePairingPage> {
  final BleService _ble = BleService();
  List<ScanResult> _scanResults = [];
  bool _scanning = false;
  String? _connectingId;
  String? _errorMsg;

  @override
  void initState() {
    super.initState();
    _requestPermissionsAndScan();
  }

  Future<void> _requestPermissionsAndScan() async {
    // Request BLE + location permissions
    final statuses = await [
      Permission.bluetooth,
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.locationWhenInUse,
    ].request();

    final denied = statuses.values.any(
      (s) => s == PermissionStatus.denied || s == PermissionStatus.permanentlyDenied,
    );

    if (denied) {
      setState(() => _errorMsg = 'Bluetooth & Location permissions are required.');
      return;
    }

    _startScan();
  }

  Future<void> _startScan() async {
    setState(() {
      _scanning = true;
      _scanResults = [];
      _errorMsg = null;
    });

    try {
      final results = await _ble.scanForDevices(durationSeconds: 8);
      if (mounted) {
        setState(() {
          // Show all devices; user picks the ESP32
          _scanResults = results
            ..sort((a, b) => b.rssi.compareTo(a.rssi));
          _scanning = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _scanning = false;
          _errorMsg = 'Scan failed: $e';
        });
      }
    }
  }

  Future<void> _pairDevice(BluetoothDevice device) async {
    setState(() {
      _connectingId = device.remoteId.toString();
      _errorMsg = null;
    });

    final ok = await _ble.pairDevice(device);
    if (!mounted) return;

    if (ok) {
      Navigator.of(context).pop(true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✅ Paired with ${device.platformName.isNotEmpty ? device.platformName : 'ESP32 Wearable'}'),
          backgroundColor: Colors.green,
        ),
      );
    } else {
      setState(() {
        _connectingId = null;
        _errorMsg = 'Could not connect. Make sure ESP32 is powered and nearby.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        title: const Text('Pair ESP32 Wearable'),
        backgroundColor: const Color(0xFF2196F3),
        foregroundColor: Colors.white,
        actions: [
          if (!_scanning)
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _startScan,
              tooltip: 'Scan again',
            ),
        ],
      ),
      body: Column(
        children: [
          // -- Status banner --
          _StatusBanner(ble: _ble),

          // -- Info card --
          Padding(
            padding: const EdgeInsets.all(16),
            child: Card(
              color: const Color(0xFFE3F2FD),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: const [
                    Icon(Icons.info_outline, color: Color(0xFF1976D2)),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Make sure your ESP32 wearable is powered ON. '
                        'Look for a device named "SafePWD" or "ESP32".',
                        style: TextStyle(fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          if (_errorMsg != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Card(
                color: Colors.red.shade50,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline, color: Colors.red),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(_errorMsg!, style: const TextStyle(color: Colors.red)),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // -- Scanning indicator --
          if (_scanning)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Column(
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 12),
                  Text('Scanning for BLE devices...'),
                ],
              ),
            ),

          // -- Results list --
          Expanded(
            child: _scanResults.isEmpty && !_scanning
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.bluetooth_searching,
                            size: 64, color: Colors.grey.shade400),
                        const SizedBox(height: 16),
                        Text('No devices found',
                            style: TextStyle(color: Colors.grey.shade600)),
                        const SizedBox(height: 8),
                        ElevatedButton.icon(
                          onPressed: _startScan,
                          icon: const Icon(Icons.search),
                          label: const Text('Scan Again'),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: _scanResults.length,
                    itemBuilder: (ctx, i) {
                      final sr = _scanResults[i];
                      final device = sr.device;
                      final name = device.platformName.isNotEmpty
                          ? device.platformName
                          : 'Unknown Device';
                      final id = device.remoteId.toString();
                      final isConnecting = _connectingId == id;
                      final isPaired = _ble.pairedDeviceId == id;

                      return Card(
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: isPaired
                                ? Colors.green
                                : const Color(0xFF2196F3),
                            child: Icon(
                              isPaired ? Icons.check : Icons.bluetooth,
                              color: Colors.white,
                            ),
                          ),
                          title: Text(
                            name,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          subtitle: Text(
                            '$id  •  RSSI: ${sr.rssi} dBm',
                            style: const TextStyle(fontSize: 11),
                          ),
                          trailing: isConnecting
                              ? const SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : isPaired
                                  ? const Chip(
                                      label: Text('Paired'),
                                      backgroundColor: Color(0xFFE8F5E9),
                                    )
                                  : ElevatedButton(
                                      onPressed: () => _pairDevice(device),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: const Color(0xFF2196F3),
                                        foregroundColor: Colors.white,
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12, vertical: 6),
                                      ),
                                      child: const Text('Pair'),
                                    ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

/// Small banner showing current BLE connection status
class _StatusBanner extends StatelessWidget {
  final BleService ble;
  const _StatusBanner({required this.ble});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ble,
      builder: (ctx, _) {
        if (ble.pairedDeviceId == null) return const SizedBox.shrink();
        return Container(
          width: double.infinity,
          color: ble.isConnected ? Colors.green : Colors.orange,
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 16),
          child: Row(
            children: [
              Icon(
                ble.isConnected ? Icons.bluetooth_connected : Icons.bluetooth_disabled,
                color: Colors.white,
                size: 18,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  ble.isConnected
                      ? '${ble.pairedDeviceName ?? "ESP32"} — Connected'
                      : '${ble.pairedDeviceName ?? "ESP32"} — Reconnecting...',
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                ),
              ),
              if (!ble.isConnected)
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

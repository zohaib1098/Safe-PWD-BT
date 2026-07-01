import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// BLE Service for ESP32 Wearable Communication
/// Fixed version — all 4 bugs resolved
class BleService extends ChangeNotifier {
  static final BleService _instance = BleService._internal();
  factory BleService() => _instance;
  BleService._internal();

  // ----------------------------------------------------------------
  // BLE UUIDs — Nordic UART Service
  // BUG FIX #1: TX (write to ESP32) = 6e400002, RX (notify from ESP32) = 6e400003
  // Previous code had these SWAPPED which is why commands never reached ESP32
  // ----------------------------------------------------------------
  static const String _uartServiceUuid = '6e400001-b5a3-f393-e0a9-e50e24dcca9e';
  static const String _txCharUuid      = '6e400002-b5a3-f393-e0a9-e50e24dcca9e'; // Write → ESP32
  static const String _rxCharUuid      = '6e400003-b5a3-f393-e0a9-e50e24dcca9e'; // Notify ← ESP32

  static const String _prefDeviceId   = 'ble_paired_device_id';
  static const String _prefDeviceName = 'ble_paired_device_name';

  // State
  BluetoothDevice? _connectedDevice;
  BluetoothCharacteristic? _txChar;
  BluetoothCharacteristic? _rxChar;
  StreamSubscription<BluetoothConnectionState>? _connStateSub;
  StreamSubscription<List<int>>? _rxSub;
  Timer? _reconnectTimer;

  String? _pairedDeviceId;
  String? _pairedDeviceName;
  bool _isConnected    = false;
  bool _isScanning     = false;
  bool _isReconnecting = false;
  int  _batteryLevel   = -1;

  String?          get pairedDeviceId   => _pairedDeviceId;
  String?          get pairedDeviceName => _pairedDeviceName;
  bool             get isConnected      => _isConnected;
  bool             get isScanning       => _isScanning;
  bool             get isReconnecting   => _isReconnecting;
  int              get batteryLevel     => _batteryLevel;
  BluetoothDevice? get connectedDevice  => _connectedDevice;

  final StreamController<String> _rxController =
      StreamController<String>.broadcast();
  Stream<String> get rxStream => _rxController.stream;

  final Queue<String> _commandQueue = Queue<String>();

  // ----------------------------------------------------------------
  // Init
  // ----------------------------------------------------------------
  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _pairedDeviceId   = prefs.getString(_prefDeviceId);
    _pairedDeviceName = prefs.getString(_prefDeviceName);

    if (_pairedDeviceId != null) _startAutoReconnect();
    notifyListeners();
  }

  // ----------------------------------------------------------------
  // Scan
  // BUG FIX #2: Previous code used `await for` on scanResults stream
  // which NEVER terminates — scan ran forever and blocked the UI.
  // Fixed: use a Completer + listen(), cancel after timeout.
  // ----------------------------------------------------------------
  Future<List<ScanResult>> scanForDevices({int durationSeconds = 8}) async {
    if (_isScanning) return [];

    _isScanning = true;
    notifyListeners();

    final results    = <ScanResult>[];
    final completer  = Completer<List<ScanResult>>();
    StreamSubscription<List<ScanResult>>? sub;

    try {
      await FlutterBluePlus.startScan(
        timeout: Duration(seconds: durationSeconds),
      );

      sub = FlutterBluePlus.scanResults.listen((list) {
        for (final sr in list) {
          if (!results.any((e) => e.device.remoteId == sr.device.remoteId)) {
            results.add(sr);
          }
        }
      });

      // Wait for scan to finish (timeout fires automatically)
      await FlutterBluePlus.isScanning
          .where((scanning) => scanning == false)
          .first
          .timeout(
            Duration(seconds: durationSeconds + 2),
            onTimeout: () => false,
          );

      completer.complete(results);
    } catch (e) {
      debugPrint('[BLE] Scan error: $e');
      if (!completer.isCompleted) completer.complete(results);
    } finally {
      await sub?.cancel();
      _isScanning = false;
      notifyListeners();
    }

    return completer.isCompleted ? await completer.future : results;
  }

  Future<void> stopScan() async {
    await FlutterBluePlus.stopScan();
    _isScanning = false;
    notifyListeners();
  }

  // ----------------------------------------------------------------
  // Connect
  // ----------------------------------------------------------------
  Future<bool> connectToDevice(BluetoothDevice device) async {
    _cancelReconnect();

    try {
      await device.connect(
        timeout: const Duration(seconds: 12),
        autoConnect: false,
      );
    } catch (e) {
      debugPrint('[BLE] Connect error: $e');
      return false;
    }

    _connectedDevice = device;

    _connStateSub = device.connectionState.listen((state) {
      final connected = state == BluetoothConnectionState.connected;
      if (_isConnected != connected) {
        _isConnected = connected;
        notifyListeners();
        if (!connected) {
          debugPrint('[BLE] Disconnected — starting auto-reconnect...');
          _txChar       = null;
          _rxChar       = null;
          _batteryLevel = -1;
          _startAutoReconnect();
        }
      }
    });

    final ok = await _discoverUartService(device);
    if (!ok) {
      await device.disconnect();
      return false;
    }

    _isConnected    = true;
    _isReconnecting = false;
    notifyListeners();

    await _processCommandQueue();
    return true;
  }

  // ----------------------------------------------------------------
  // Pair
  // ----------------------------------------------------------------
  Future<bool> pairDevice(BluetoothDevice device) async {
    final ok = await connectToDevice(device);
    if (!ok) return false;

    _pairedDeviceId   = device.remoteId.toString();
    _pairedDeviceName = device.platformName.isNotEmpty
        ? device.platformName
        : 'ESP32 Wearable';

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefDeviceId,   _pairedDeviceId!);
    await prefs.setString(_prefDeviceName, _pairedDeviceName!);
    notifyListeners();
    return true;
  }

  // ----------------------------------------------------------------
  // Unpair
  // ----------------------------------------------------------------
  Future<void> unpairDevice() async {
    _cancelReconnect();
    await _connectedDevice?.disconnect();
    _connectedDevice = null;
    _txChar          = null;
    _rxChar          = null;
    _isConnected     = false;
    _pairedDeviceId  = null;
    _pairedDeviceName= null;
    _batteryLevel    = -1;

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefDeviceId);
    await prefs.remove(_prefDeviceName);
    notifyListeners();
  }

  // ----------------------------------------------------------------
  // Send vibrate "V"
  // ----------------------------------------------------------------
  Future<bool> sendVibrate() => _sendCommand('V');

  // ----------------------------------------------------------------
  // Send command
  // BUG FIX #3: withoutResponse was false — ESP32 NimBLE firmware
  // uses WRITE_NR (no response). Setting withoutResponse: true fixes
  // commands silently failing on some Android versions.
  // ----------------------------------------------------------------
  Future<bool> _sendCommand(String cmd) async {
    if (_txChar == null || !_isConnected) {
      debugPrint('[BLE] Cannot send — not connected');
      return false;
    }
    try {
      await _txChar!.write(
        utf8.encode(cmd),
        withoutResponse: true,   // ← FIX: matches ESP32 WRITE_NR property
      );
      debugPrint('[BLE] Sent: $cmd');
      return true;
    } catch (e) {
      debugPrint('[BLE] Write error: $e');
      return false;
    }
  }

  Future<void> requestBatteryStatus() => _sendCommand('B?');

  void queueVibrationCommand() {
    if (!_commandQueue.contains('V')) {
      _commandQueue.add('V');
      debugPrint('[BLE-QUEUE] Vibration queued for retry');
    }
  }

  Future<void> _processCommandQueue() async {
    if (_commandQueue.isEmpty) return;
    debugPrint('[BLE-QUEUE] Processing ${_commandQueue.length} queued command(s)...');
    while (_commandQueue.isNotEmpty && _isConnected) {
      final cmd = _commandQueue.removeFirst();
      await Future.delayed(const Duration(milliseconds: 300));
      await _sendCommand(cmd);
    }
  }

  // ----------------------------------------------------------------
  // Discover UART service
  // ----------------------------------------------------------------
  Future<bool> _discoverUartService(BluetoothDevice device) async {
    try {
      final services = await device.discoverServices();
      for (final svc in services) {
        if (svc.uuid.toString().toLowerCase() == _uartServiceUuid) {
          for (final char in svc.characteristics) {
            final uuid = char.uuid.toString().toLowerCase();
            if (uuid == _txCharUuid) _txChar = char;
            if (uuid == _rxCharUuid) _rxChar = char;
          }
          break;
        }
      }

      if (_txChar == null) {
        debugPrint('[BLE] TX characteristic not found. Is ESP32 running SafePWD firmware?');
        return false;
      }

      if (_rxChar != null) {
        await _rxChar!.setNotifyValue(true);
        _rxSub = _rxChar!.lastValueStream.listen(_onRxData);
      }

      return true;
    } catch (e) {
      debugPrint('[BLE] Service discovery error: $e');
      return false;
    }
  }

  // ----------------------------------------------------------------
  // Handle data from ESP32
  // ----------------------------------------------------------------
  void _onRxData(List<int> data) {
    if (data.isEmpty) return;
    final msg = utf8.decode(data).trim();
    if (msg.isEmpty) return;

    debugPrint('[BLE] Received: $msg');
    _rxController.add(msg);

    if (msg == 'OK:V') {
      debugPrint('[BLE] ✅ ESP32 confirmed vibration');
      return;
    }

    if (msg.startsWith('B:')) {
      final lvl = int.tryParse(msg.substring(2));
      if (lvl != null) {
        _batteryLevel = lvl;
        notifyListeners();
      }
    }
  }

  // ----------------------------------------------------------------
  // Auto-reconnect
  // BUG FIX #4: FlutterBluePlus.systemDevices([Guid(...)]) signature
  // changed in v1.x — it now takes withServices as named param.
  // Using BluetoothDevice(remoteId:) directly is more reliable.
  // ----------------------------------------------------------------
  void _startAutoReconnect() {
    if (_pairedDeviceId == null) return;
    _isReconnecting = true;
    notifyListeners();

    _reconnectTimer = Timer.periodic(const Duration(seconds: 3), (_) async {
      if (_isConnected) {
        _cancelReconnect();
        return;
      }
      debugPrint('[BLE] Reconnect attempt → $_pairedDeviceId');
      try {
        // FIX: skip systemDevices (unreliable), go straight to device by ID
        final target = BluetoothDevice(
          remoteId: DeviceIdentifier(_pairedDeviceId!),
        );
        await connectToDevice(target);
      } catch (e) {
        debugPrint('[BLE] Reconnect failed: $e');
      }
    });
  }

  void _cancelReconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _isReconnecting = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _connStateSub?.cancel();
    _rxSub?.cancel();
    _reconnectTimer?.cancel();
    _rxController.close();
    super.dispose();
  }
}

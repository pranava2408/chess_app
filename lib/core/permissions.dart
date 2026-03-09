import 'package:permission_handler/permission_handler.dart';

class PermissionService {
  static Future<bool> requestBluetoothPermissions() async {
    // Bluetooth on Android requires Location + Bluetooth Scan/Connect
    Map<Permission, PermissionStatus> statuses = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.bluetoothAdvertise,
      Permission.location,
    ].request();

    // Check if all were granted
    return statuses.values.every((status) => status.isGranted);
  }
}
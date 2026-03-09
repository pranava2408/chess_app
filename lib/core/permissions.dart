import 'package:permission_handler/permission_handler.dart';
import 'dart:io';

class PermissionService {
  static Future<bool> requestBluetoothPermissions() async {
    // We request EVERYTHING. Android will automatically skip 
    // permissions that don't apply to the specific version.
    Map<Permission, PermissionStatus> statuses = await [
      // Fixes Error 8034 (Android 12 requirement)
      Permission.location,
      Permission.locationWhenInUse,

      // Fixes Error 8029 (Android 13/14 requirement)
      Permission.nearbyWifiDevices,

      // Required for Bluetooth hardware access on all modern Androids
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.bluetoothAdvertise,
    ].request();

    // Check if the critical ones are granted
    bool locationGranted = statuses[Permission.location]?.isGranted ?? false;
    bool bluetoothGranted = (statuses[Permission.bluetoothScan]?.isGranted ?? false) && 
                            (statuses[Permission.bluetoothConnect]?.isGranted ?? false);

    // On Android 13+, NearbyWifi is mandatory
    bool nearbyWifiGranted = true;
    if (Platform.isAndroid && statuses.containsKey(Permission.nearbyWifiDevices)) {
      nearbyWifiGranted = statuses[Permission.nearbyWifiDevices]?.isGranted ?? false;
    }

    return (locationGranted || nearbyWifiGranted) && bluetoothGranted;
  }
}
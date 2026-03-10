import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:nearby_connections/nearby_connections.dart';
import 'network_services.dart';

class DiscoveredDevice {
  final String id;
  final String name;
  DiscoveredDevice(this.id, this.name);
}

class ConnectionRequest {
  final String id;
  final String name;
  ConnectionRequest(this.id, this.name);
}

class BluetoothNetworkService extends ChangeNotifier implements NetworkService {
  // --- CONSTANTS: The "Secret Key" that connects your phones ---
  static const String CHESS_SERVICE_ID = "com.balla.chess_app.p2p_v1";
  static const Strategy CHESS_STRATEGY = Strategy.P2P_STAR;

  final _moveController = StreamController<String>.broadcast();
  final _stateController = StreamController<ConnectionState>.broadcast();
  final _devicesController = StreamController<List<DiscoveredDevice>>.broadcast();
  final _requestController = StreamController<ConnectionRequest>.broadcast();

  String? _connectedDeviceId;
  final List<DiscoveredDevice> _foundDevices = [];

  Stream<List<DiscoveredDevice>> get discoveredDevices => _devicesController.stream;
  Stream<ConnectionRequest> get incomingRequests => _requestController.stream;

  BluetoothNetworkService() {
    _stateController.add(ConnectionState.disconnected);
  }

  @override
  Stream<String> get onMoveReceived => _moveController.stream;

  @override
  Stream<ConnectionState> get connectionState => _stateController.stream;

  // --- HOSTING LOGIC ---
  Future<void> hostGameWithCustomName(String playerName) async {
    _stateController.add(ConnectionState.hosting);
    try {
      // 1. Kill any old background tasks to free the Bluetooth radio
      await Nearby().stopAdvertising();
      await Nearby().stopDiscovery();

      // 2. Start broadcasting
      bool success = await Nearby().startAdvertising(
        playerName,
        CHESS_STRATEGY,
        serviceId: CHESS_SERVICE_ID, // CRITICAL: Must match scanner
        onConnectionInitiated: _onConnectionInit,
        onConnectionResult: _onConnectionResult,
        onDisconnected: (id) => disconnect(),
      );

      if (!success) throw "Hardware refused to Advertise. Check Bluetooth/Location.";
    } catch (e) {
      _stateController.add(ConnectionState.disconnected);
      debugPrint("HOST ERROR: $e");
      rethrow; 
    }
  }

  // --- SCANNING LOGIC ---
  Future<void> startScanning(String playerName) async {
    _stateController.add(ConnectionState.scanning);
    _foundDevices.clear();
    _devicesController.add(List.from(_foundDevices));

    try {
      // 1. Kill old scans to prevent "Radio Lock"
      await Nearby().stopDiscovery();
      await Nearby().stopAdvertising();

      // 2. Start searching
      bool success = await Nearby().startDiscovery(
        playerName,
        CHESS_STRATEGY,
        serviceId: CHESS_SERVICE_ID, // CRITICAL: Must match host
        onEndpointFound: (id, name, serviceId) {
          debugPrint("Device Found: $name ($id)");
          
          // Add to list if not a duplicate
          if (!_foundDevices.any((d) => d.id == id)) {
            _foundDevices.add(DiscoveredDevice(id, name));
            // Force UI update by sending a NEW list instance
            _devicesController.add(List.from(_foundDevices));
          }
        },
        onEndpointLost: (id) {
          _foundDevices.removeWhere((device) => device.id == id);
          _devicesController.add(List.from(_foundDevices));
        },
      );

      if (!success) throw "Hardware refused to Scan. Check Bluetooth/Location.";
    } catch (e) {
      debugPrint("SCAN ERROR: $e");
      _stateController.add(ConnectionState.disconnected);
      rethrow;
    }
  }

  // --- CONNECTION HANDSHAKE ---
  Future<void> requestConnection(String playerName, String targetId) async {
    await Nearby().requestConnection(
      playerName,
      targetId,
      onConnectionInitiated: _onConnectionInit,
      onConnectionResult: _onConnectionResult,
      onDisconnected: (id) => disconnect(),
    );
  }

  void _onConnectionInit(String id, ConnectionInfo info) {
    // This triggers the Accept/Reject Dialog in your LobbyScreen
    _requestController.add(ConnectionRequest(id, info.endpointName));
  }

  void acceptConnection(String id) {
    Nearby().acceptConnection(
      id,
      onPayLoadRecieved: (endpointId, payload) {
        if (payload.type == PayloadType.BYTES && payload.bytes != null) {
          // Decode the Move string from bytes
          String move = String.fromCharCodes(payload.bytes!);
          _moveController.add(move);
        }
      },
      onPayloadTransferUpdate: (id, update) {
        // Essential for internal handshake completion
      },
    );
  }

  void rejectConnection(String id) {
    Nearby().rejectConnection(id);
  }

  void _onConnectionResult(String id, Status status) {
    if (status == Status.CONNECTED) {
      _connectedDeviceId = id;
      _stateController.add(ConnectionState.connected);
      
      // OPTIMIZATION: Stop scanning/hosting once connected to save battery and reduce lag
      Nearby().stopAdvertising();
      Nearby().stopDiscovery();
    } else {
      _stateController.add(ConnectionState.disconnected);
    }
  }

  // --- MOVE SENDING ---
  @override
  void sendMove(String moveNotation) {
    if (_connectedDeviceId != null) {
      Uint8List bytes = Uint8List.fromList(moveNotation.codeUnits);
      Nearby().sendBytesPayload(_connectedDeviceId!, bytes);
    }
  }

  @override
  Future<void> disconnect() async {
    await Nearby().stopAllEndpoints();
    await Nearby().stopAdvertising();
    await Nearby().stopDiscovery();
    _connectedDeviceId = null;
    _foundDevices.clear();
    _stateController.add(ConnectionState.disconnected);
  }

  // Mandatory overrides for your NetworkService interface
  @override
  Future<void> hostGame() async {}
  @override
  Future<void> joinGame(String targetId) async {}
}
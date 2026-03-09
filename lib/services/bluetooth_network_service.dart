import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:nearby_connections/nearby_connections.dart';
import 'network_services.dart'; // Imports YOUR ConnectionState

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
  final _moveController = StreamController<String>.broadcast();
  
  // Using YOUR exact enum
  final _stateController = StreamController<ConnectionState>.broadcast();
  final _devicesController = StreamController<List<DiscoveredDevice>>.broadcast();
  final _requestController = StreamController<ConnectionRequest>.broadcast();

  String? _connectedDeviceId;
  List<DiscoveredDevice> _foundDevices = [];
  
  Stream<List<DiscoveredDevice>> get discoveredDevices => _devicesController.stream;
  Stream<ConnectionRequest> get incomingRequests => _requestController.stream;

  BluetoothNetworkService() {
    _stateController.add(ConnectionState.disconnected);
  }

  @override
  Stream<String> get onMoveReceived => _moveController.stream;

  @override
  Stream<ConnectionState> get connectionState => _stateController.stream;

  Future<void> hostGameWithCustomName(String playerName) async {
    _stateController.add(ConnectionState.hosting);
    try {
      await Nearby().startAdvertising(
        playerName,
        Strategy.P2P_STAR,
        onConnectionInitiated: _onConnectionInit,
        onConnectionResult: _onConnectionResult,
        onDisconnected: (id) => disconnect(),
      );
    } catch (e) {
      _stateController.add(ConnectionState.disconnected);
    }
  }

  Future<void> startScanning(String playerName) async {
    _stateController.add(ConnectionState.scanning);
    _foundDevices.clear();
    _devicesController.add(_foundDevices);

    try {
      await Nearby().startDiscovery(
        playerName,
        Strategy.P2P_STAR,
        onEndpointFound: (id, name, serviceId) {
          _foundDevices.add(DiscoveredDevice(id, name));
          _devicesController.add(_foundDevices);
        },
        onEndpointLost: (id) {
          _foundDevices.removeWhere((device) => device.id == id);
          _devicesController.add(_foundDevices);
        },
      );
    } catch (e) {
      _stateController.add(ConnectionState.disconnected);
    }
  }

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
    _requestController.add(ConnectionRequest(id, info.endpointName));
  }

  void acceptConnection(String id) {
    Nearby().acceptConnection(
      id,
      onPayLoadRecieved: (String endpointId, Payload payload) {
        if (payload.type == PayloadType.BYTES && payload.bytes != null) {
          String move = String.fromCharCodes(payload.bytes!);
          _moveController.add(move);
        }
      },
      onPayloadTransferUpdate: (endpointId, payloadTransferUpdate) {},
    );
  }

  void rejectConnection(String id) {
    Nearby().rejectConnection(id);
  }

  void _onConnectionResult(String id, Status status) {
    if (status == Status.CONNECTED) {
      _connectedDeviceId = id;
      _stateController.add(ConnectionState.connected);
      Nearby().stopAdvertising();
      Nearby().stopDiscovery();
    } else {
      _stateController.add(ConnectionState.disconnected);
    }
  }

  @override Future<void> hostGame() async {} 
  @override Future<void> joinGame(String targetId) async {}

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
}
import 'dart:async';
import 'package:chess_app/services/network_services.dart';

class MockNetworkService implements NetworkService {
  final _moveController = StreamController<String>.broadcast();
  final _stateController = StreamController<ConnectionState>.broadcast();

  MockNetworkService() {
    // Start disconnected
    _stateController.add(ConnectionState.disconnected);
  }

  @override
  Stream<String> get onMoveReceived => _moveController.stream;

  @override
  Stream<ConnectionState> get connectionState => _stateController.stream;

  @override
  Future<void> hostGame() async {
    _stateController.add(ConnectionState.hosting);
    await Future.delayed(const Duration(seconds: 2)); // Simulate waiting
    _stateController.add(ConnectionState.connected);
  }

  @override
  Future<void> joinGame(String targetId) async {
    _stateController.add(ConnectionState.scanning);
    await Future.delayed(const Duration(seconds: 2));
    _stateController.add(ConnectionState.connected);
  }

  @override
  Future<void> disconnect() async {
    _stateController.add(ConnectionState.disconnected);
  }

  @override
  void sendMove(String moveNotation) {
    print("Mock Network: Sent move $moveNotation to opponent.");
    
    // Simulate the opponent thinking and making a move 2 seconds later
    Future.delayed(const Duration(seconds: 2), () {
      print("Mock Network: Opponent sent a reply.");
      _moveController.add("e7e5"); // Fake reply
    });
  }
}
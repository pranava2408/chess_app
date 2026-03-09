import 'dart:async';

// The different states our connection can be in
enum ConnectionState { disconnected, scanning, hosting, connected }

abstract class NetworkService {
  // A stream that the UI will listen to for incoming moves (e.g., "e2e4")
  Stream<String> get onMoveReceived;

  // A stream that broadcasts the current connection status
  Stream<ConnectionState> get connectionState;

  // Methods to implement later
  Future<void> hostGame();
  Future<void> joinGame(String targetId);
  Future<void> disconnect();
  
  // The method to send a move to the opponent
  void sendMove(String moveNotation);
}
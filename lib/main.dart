import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// 1. Import our custom files
import 'services/network_services.dart';
import 'services/mock_network_service.dart';
import 'features/board/board_screen.dart';

// 2. Set up the Riverpod provider globally so the UI can access the network
final networkProvider = Provider<NetworkService>((ref) {
  return MockNetworkService(); 
});

void main() {
  runApp(
    // 3. Wrap the entire app in ProviderScope (required for Riverpod)
    const ProviderScope(
      child: MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'P2P Chess Sandbox',
      theme: ThemeData.dark(),
      // 4. Point the home screen directly to our new BoardScreen
      home: const BoardScreen(), 
    );
  }
}
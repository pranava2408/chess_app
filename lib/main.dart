import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'services/network_services.dart';
import 'services/bluetooth_network_service.dart';
import 'features/board/lobby_screen.dart';

final networkProvider = Provider<NetworkService>((ref) {
  return BluetoothNetworkService(); 
});

void main() {
  runApp(
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
      debugShowCheckedModeBanner: false,
      title: 'Complete P2P Chess',
      theme: ThemeData.dark(useMaterial3: true),
      home: const LobbyScreen(),
    );
  }
}
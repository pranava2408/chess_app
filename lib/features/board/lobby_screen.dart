import 'dart:async';
// Hides Flutter's built-in state to let yours work perfectly
import 'package:flutter/material.dart' hide ConnectionState;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/permissions.dart';
import '../../main.dart';
import '../board/board_screen.dart';
import '../../services/network_services.dart';
import '../../services/bluetooth_network_service.dart';

class LobbyScreen extends ConsumerStatefulWidget {
  const LobbyScreen({super.key});

  @override
  ConsumerState<LobbyScreen> createState() => _LobbyScreenState();
}

class _LobbyScreenState extends ConsumerState<LobbyScreen> {
  final TextEditingController _nameController = TextEditingController();
  StreamSubscription? _connectionSub;
  StreamSubscription? _requestSub;

  ConnectionState _currentState = ConnectionState.disconnected;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final network = ref.read(networkProvider) as BluetoothNetworkService;

      _connectionSub = network.connectionState.listen((state) {
        if (!mounted) return;

        if (state == ConnectionState.connected) {
          // CRITICAL: Decide who is White (Host) before switching screens
          bool amIWhite = (_currentState == ConnectionState.hosting);

          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => BoardScreen(isHost: amIWhite),
            ),
          );
        }
        
        setState(() => _currentState = state);
      });

      _requestSub = network.incomingRequests.listen((request) {
        if (!mounted) return;
        _showAcceptDialog(request.id, request.name, network);
      });
    });
  }

  void _showAcceptDialog(String id, String opponentName, BluetoothNetworkService network) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text("Match Request"),
        content: Text("$opponentName wants to play a game!"),
        actions: [
          TextButton(
            onPressed: () {
              network.rejectConnection(id);
              Navigator.pop(context);
            },
            child: const Text("Reject", style: TextStyle(color: Colors.red)),
          ),
          ElevatedButton(
            onPressed: () {
              network.acceptConnection(id);
              Navigator.pop(context);
            },
            child: const Text("Accept"),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _connectionSub?.cancel();
    _requestSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final network = ref.read(networkProvider) as BluetoothNetworkService;

    return Scaffold(
      appBar: AppBar(title: const Text("Multiplayer Lobby")),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // --- STATE: DISCONNECTED ---
            if (_currentState == ConnectionState.disconnected) ...[
              TextField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: "Enter Your Name",
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.person),
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(padding: const EdgeInsets.all(16)),
                      icon: const Icon(Icons.wifi_tethering),
                      label: const Text("Host Game"),
                      onPressed: () async {
                        if (_nameController.text.isEmpty) return;
                        
                        // Ask for permissions, then try to host
                        await PermissionService.requestBluetoothPermissions();
                        try {
                          await network.hostGameWithCustomName(_nameController.text);
                        } catch (e) {
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text("Host Error: $e"), backgroundColor: Colors.red),
                            );
                          }
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(padding: const EdgeInsets.all(16)),
                      icon: const Icon(Icons.search),
                      label: const Text("Find Games"),
                      onPressed: () async {
                        if (_nameController.text.isEmpty) return;
                        
                        // Ask for permissions, then try to scan
                        await PermissionService.requestBluetoothPermissions();
                        try {
                          await network.startScanning(_nameController.text);
                        } catch (e) {
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text("Scan Error: $e"), backgroundColor: Colors.red),
                            );
                          }
                        }
                      },
                    ),
                  ),
                ],
              ),
            ] 
            // --- STATE: HOSTING ---
            else if (_currentState == ConnectionState.hosting) ...[
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const CircularProgressIndicator(),
                      const SizedBox(height: 24),
                      const Text(
                        "Game Hosted Successfully!",
                        style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        "Broadcasting as '${_nameController.text}'\nWaiting for an opponent...",
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 16, color: Colors.grey),
                      ),
                      const SizedBox(height: 32),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade900),
                        icon: const Icon(Icons.cancel, color: Colors.white),
                        label: const Text("Cancel Hosting", style: TextStyle(color: Colors.white)),
                        onPressed: () => network.disconnect(),
                      ),
                    ],
                  ),
                ),
              ),
            ]
            // --- STATE: SCANNING ---
            else if (_currentState == ConnectionState.scanning) ...[
              const Center(
                child: Column(
                  children: [
                    LinearProgressIndicator(),
                    SizedBox(height: 16),
                    Text(
                      "Radar Active: Looking for nearby games...",
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Expanded(
                child: StreamBuilder<List<DiscoveredDevice>>(
                  stream: network.discoveredDevices,
                  initialData: const [],
                  builder: (context, snapshot) {
                    final devices = snapshot.data!;
                    
                    if (devices.isEmpty) {
                      return const Center(
                        child: Text(
                          "No games found yet.\nKeep waiting or ask your opponent to host.",
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey, fontSize: 16),
                        ),
                      );
                    }
                    
                    return ListView.builder(
                      itemCount: devices.length,
                      itemBuilder: (context, index) {
                        final device = devices[index];
                        return Card(
                          elevation: 4,
                          margin: const EdgeInsets.symmetric(vertical: 8),
                          child: ListTile(
                            contentPadding: const EdgeInsets.all(16),
                            leading: const CircleAvatar(child: Icon(Icons.person)),
                            title: Text(device.name, style: const TextStyle(fontSize: 18)),
                            subtitle: const Text("Tap connect to send a match request"),
                            trailing: ElevatedButton(
                              style: ElevatedButton.styleFrom(backgroundColor: Colors.green.shade700),
                              onPressed: () => network.requestConnection(_nameController.text, device.id),
                              child: const Text("Connect", style: TextStyle(color: Colors.white)),
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 16.0),
                child: TextButton(
                  onPressed: () => network.disconnect(),
                  child: const Text("Stop Scanning", style: TextStyle(color: Colors.red, fontSize: 16)),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
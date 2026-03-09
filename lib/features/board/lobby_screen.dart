import 'dart:async';
// THE MAGIC FIX: Hides Flutter's built-in state to let yours work perfectly
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

  // Using YOUR exact state enum without errors
  ConnectionState _currentState = ConnectionState.disconnected;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final network = ref.read(networkProvider) as BluetoothNetworkService;

      _connectionSub = network.connectionState.listen((state) {
        if (!mounted) return;
        setState(() => _currentState = state);

        if (state == ConnectionState.connected) {
          // If we were hosting, we are White. If scanning, we are Black.
          bool isHost = _currentState == ConnectionState.hosting;

          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => BoardScreen(isHost: isHost)),
          );
        }
      });

      _requestSub = network.incomingRequests.listen((request) {
        if (!mounted) return;
        _showAcceptDialog(request.id, request.name, network);
      });
    });
  }

  void _showAcceptDialog(
    String id,
    String opponentName,
    BluetoothNetworkService network,
  ) {
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
            // --- STATE: DISCONNECTED (Main Menu) ---
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
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(padding: const EdgeInsets.all(16)),
                      icon: const Icon(Icons.wifi_tethering),
                      label: const Text("Host Game"),
                      onPressed: () async {
                        if (_nameController.text.isEmpty) return;
                        if (await PermissionService.requestBluetoothPermissions()) {
                          try {
                            await network.hostGameWithCustomName(_nameController.text);
                          } catch (e) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text("Failed to Host. Are Bluetooth & Location ON? (Emulators will fail here)")),
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
                        if (await PermissionService.requestBluetoothPermissions()) {
                          try {
                            await network.startScanning(_nameController.text);
                          } catch (e) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text("Failed to Scan. Are Bluetooth & Location ON? (Emulators will fail here)")),
                            );
                          }
                        }
                      },
                    ),
                  ),
                ],
              ),
            ] 
            
            // --- STATE: HOSTING (Waiting for players) ---
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
                        "Broadcasting as '${_nameController.text}'\nWaiting for an opponent to connect...",
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
            
            // --- STATE: SCANNING (Looking for games) ---
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
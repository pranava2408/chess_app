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
            if (_currentState == ConnectionState.disconnected) ...[
              TextField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: "Enter Your Name",
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  ElevatedButton.icon(
                    icon: const Icon(Icons.wifi_tethering),
                    label: const Text("Host Game"),
                    onPressed: () async {
                      if (_nameController.text.isEmpty) return;
                      if (await PermissionService.requestBluetoothPermissions()) {
                        network.hostGameWithCustomName(_nameController.text);
                      }
                    },
                  ),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.search),
                    label: const Text("Scan"),
                    onPressed: () async {
                      if (_nameController.text.isEmpty) return;
                      if (await PermissionService.requestBluetoothPermissions()) {
                        network.startScanning(_nameController.text);
                      }
                    },
                  ),
                ],
              ),
            ] else ...[
              Center(
                child: Column(
                  children: [
                    const CircularProgressIndicator(),
                    const SizedBox(height: 16),
                    Text(
                      _currentState == ConnectionState.hosting
                          ? "Hosting as '${_nameController.text}'..."
                          : "Scanning...",
                      style: const TextStyle(fontSize: 18),
                    ),
                    TextButton(
                      onPressed: () => network.disconnect(),
                      child: const Text(
                        "Cancel",
                        style: TextStyle(color: Colors.red),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              if (_currentState == ConnectionState.scanning)
                Expanded(
                  child: StreamBuilder<List<DiscoveredDevice>>(
                    stream: network.discoveredDevices,
                    initialData: const [],
                    builder: (context, snapshot) {
                      // Using !hasData safely since we hid Flutter's ConnectionState
                      if (!snapshot.hasData || snapshot.data!.isEmpty) {
                        return const Center(child: Text("No games found."));
                      }
                      final devices = snapshot.data!;
                      return ListView.builder(
                        itemCount: devices.length,
                        itemBuilder: (context, index) {
                          final device = devices[index];
                          return Card(
                            child: ListTile(
                              leading: const Icon(Icons.person),
                              title: Text(device.name),
                              trailing: ElevatedButton(
                                onPressed: () => network.requestConnection(
                                  _nameController.text,
                                  device.id,
                                ),
                                child: const Text("Connect"),
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

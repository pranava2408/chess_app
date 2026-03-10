import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_chess_board/flutter_chess_board.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../main.dart';
import 'lobby_screen.dart';

class BoardScreen extends ConsumerStatefulWidget {
  final bool isHost;
  // NEW: Accept time settings from the Lobby
  final int initialTimeSeconds;
  final int incrementSeconds;

  const BoardScreen({
    super.key,
    required this.isHost,
    // Defaulting to 10 min + 5 sec until we build the Lobby UI
    this.initialTimeSeconds = 600,
    this.incrementSeconds = 5,
  });

  @override
  ConsumerState<BoardScreen> createState() => _BoardScreenState();
}

class _BoardScreenState extends ConsumerState<BoardScreen> {
  final ChessBoardController controller = ChessBoardController();
  StreamSubscription? _networkSubscription;
  bool _gameOverProcessed = false;

  // --- NEW: CLOCK STATE ---
  Timer? _gameClock;
  late int whiteTime;
  late int blackTime;

  @override
  void initState() {
    super.initState();

    // Initialize times from the constructor
    whiteTime = widget.initialTimeSeconds;
    blackTime = widget.initialTimeSeconds;

    _startClock(); // Start ticking immediately

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final network = ref.read(networkProvider);

      _networkSubscription = network.onMoveReceived.listen((packet) {
        if (!mounted) return;

        // --- NEW: THE PACKET ROUTER ---
        List<String> parts = packet.split('|');
        String header = parts[0];

        if (header == "RESIGN") {
          _showGameOverDialog("Opponent Resigned", "You win!");
          return;
        }

        // Host sends time to the Joiner to prevent 'Time Drift'
        if (header == "SYNC" && !widget.isHost) {
          whiteTime = int.parse(parts[1]);
          blackTime = int.parse(parts[2]);
          setState(() {});
          return;
        }

        if (header == "MOVE" && parts.length >= 4) {
          String from = parts[1];
          String to = parts[2];
          String promotion = parts[3].isEmpty ? 'q' : parts[3];

          controller.makeMoveWithPromotion(
            from: from,
            to: to,
            pieceToPromoteTo: promotion,
          );

          // Add increment to the player who just moved
          if (controller.game.turn == Color.WHITE) {
            blackTime += widget.incrementSeconds;
          } else {
            whiteTime += widget.incrementSeconds;
          }

          _checkGameOver();
          setState(() {});
        }
      });
    });

    controller.addListener(() {
      if (mounted) {
        _checkGameOver();
        setState(() {});
      }
    });

    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) setState(() {});
    });
    if (widget.isHost) {
      Future.delayed(const Duration(milliseconds: 600), () {
        if (mounted) {
          ref.read(networkProvider).sendMove("SYNC|$whiteTime|$blackTime");
        }
      });
    }
  }

  // --- NEW: TIMER ENGINE ---
  void _startClock() {
    _gameClock = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_gameOverProcessed) {
        timer.cancel();
        return;
      }

      setState(() {
        if (controller.game.turn == Color.WHITE) {
          whiteTime--;
          if (whiteTime <= 0) _handleFlagFall(Color.WHITE);
        } else {
          blackTime--;
          if (blackTime <= 0) _handleFlagFall(Color.BLACK);
        }
      });
    });
  }

  void _handleFlagFall(Color losingColor) {
    _gameClock?.cancel();
    String winner = losingColor == Color.WHITE ? "Black" : "White";
    _showGameOverDialog("Time's Up!", "$winner wins on time.");
  }

  String _formatTime(int seconds) {
    if (seconds <= 0) return "00:00";
    int m = seconds ~/ 60;
    int s = seconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  void _checkGameOver() {
    if (_gameOverProcessed) return;

    final game = controller.game;
    String? title;
    String? message;

    if (game.in_checkmate) {
      title = "Checkmate!";
      message = game.turn == Color.WHITE ? "Black wins!" : "White wins!";
    } else if (game.in_draw) {
      title = "Draw";
      message = "The game ended in a draw.";
    }

    if (title != null) {
      _gameOverProcessed = true;
      _gameClock?.cancel();
      _showGameOverDialog(title, message!);
    }
  }

  void _showGameOverDialog(String title, String message) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          ElevatedButton(
            onPressed: () {
              ref.read(networkProvider).disconnect();
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(builder: (_) => const LobbyScreen()),
                (route) => false,
              );
            },
            child: const Text("Exit to Lobby"),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _networkSubscription?.cancel();
    _gameClock?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final network = ref.read(networkProvider);
    final currentTurn = controller.game.turn;

    bool isMyTurn =
        (currentTurn == Color.WHITE && widget.isHost) ||
        (currentTurn == Color.BLACK && !widget.isHost);

    // Identify which time belongs to who
    int myTime = widget.isHost ? whiteTime : blackTime;
    int opponentTime = widget.isHost ? blackTime : whiteTime;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          children: [
            Text(
              isMyTurn ? "Your Turn" : "Opponent's Turn",
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
            Text(
              widget.isHost ? "Playing as White" : "Playing as Black",
              style: const TextStyle(fontSize: 12, color: Colors.white70),
            ),
          ],
        ),
        centerTitle: true,
        backgroundColor: isMyTurn
            ? Colors.green.shade900
            : Colors.blueGrey.shade900,
        actions: [
          IconButton(
            icon: const Icon(Icons.flag),
            tooltip: "Resign",
            onPressed: () {
              // Updated to use the packet router syntax
              network.sendMove("RESIGN|");
              network.disconnect();
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (_) => const LobbyScreen()),
              );
            },
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // OPPONENT'S TIME
            _buildTimerCard(opponentTime, !isMyTurn),

            const SizedBox(height: 16),

            IgnorePointer(
              ignoring: !isMyTurn,
              child: ChessBoard(
                controller: controller,
                boardColor: BoardColor.brown,
                boardOrientation: widget.isHost
                    ? PlayerColor.white
                    : PlayerColor.black,
                onMove: () {
                  if (isMyTurn && controller.game.history.isNotEmpty) {
                    var lastMove = controller.game.history.last.move;

                    String from = lastMove.fromAlgebraic;
                    String to = lastMove.toAlgebraic;
                    String promotion = lastMove.promotion != null ? 'q' : '';

                    // 1. Send the MOVE packet
                    network.sendMove("MOVE|$from|$to|$promotion");

                    // 2. Add increment to your time
                    if (widget.isHost) {
                      whiteTime += widget.incrementSeconds;
                      // 3. Host broadcasts the Master Time to keep both phones synced
                      network.sendMove("SYNC|$whiteTime|$blackTime");
                    } else {
                      blackTime += widget.incrementSeconds;
                    }

                    setState(() {});
                  }
                },
              ),
            ),

            const SizedBox(height: 16),

            // YOUR TIME
            _buildTimerCard(myTime, isMyTurn),
          ],
        ),
      ),
    );
  }

  // Helper widget for clean UI
  Widget _buildTimerCard(int seconds, bool isActive) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 16),
      decoration: BoxDecoration(
        color: isActive ? Colors.green.shade100 : Colors.grey.shade800,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isActive ? Colors.green.shade700 : Colors.transparent,
          width: 3,
        ),
      ),
      child: Text(
        _formatTime(seconds),
        style: TextStyle(
          fontSize: 36,
          fontWeight: FontWeight.bold,
          color: isActive ? Colors.green.shade900 : Colors.white,
        ),
      ),
    );
  }
}

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_chess_board/flutter_chess_board.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../main.dart';
import 'lobby_screen.dart';

class BoardScreen extends ConsumerStatefulWidget {
  final bool isHost; // TRUE = White (Host), FALSE = Black (Joiner)
  const BoardScreen({super.key, required this.isHost});

  @override
  ConsumerState<BoardScreen> createState() => _BoardScreenState();
}

class _BoardScreenState extends ConsumerState<BoardScreen> {
  final ChessBoardController controller = ChessBoardController();
  StreamSubscription? _networkSubscription;
  bool _gameOverProcessed = false;

  @override
  void initState() {
    super.initState();
    
    // Listen for moves from the opponent
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final network = ref.read(networkProvider);
      
      _networkSubscription = network.onMoveReceived.listen((moveNotation) {
        if (!mounted) return;

        // Check if the opponent resigned
        if (moveNotation == "RESIGN") {
          _showGameOverDialog("Opponent Resigned", "You win!");
          return;
        }

        // Apply remote move to our board
        if (moveNotation.length >= 4) {
          String from = moveNotation.substring(0, 2);
          String to = moveNotation.substring(2, 4);
          String? promotion = moveNotation.length == 5 ? moveNotation[4] : 'q';

          controller.makeMoveWithPromotion(
            from: from, 
            to: to, 
            pieceToPromoteTo: promotion
          );
          
          _checkGameOver();
          setState(() {}); // Updates the UI turn indicator
        }
      });
    });

    // Listen to our own local moves
    controller.addListener(() {
      if (mounted) {
        _checkGameOver();
        setState(() {});
      }
    });

    // Safety refresh to clear any ghost UI states
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) setState(() {});
    });
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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final network = ref.read(networkProvider);
    
    // 1. Get the current turn from the chess engine (Color.WHITE or Color.BLACK)
    final currentTurn = controller.game.turn;

    // 2. Logic: It's your turn if (Engine says White AND you are Host) 
    // OR (Engine says Black AND you are NOT Host)
    bool isMyTurn = (currentTurn == Color.WHITE && widget.isHost) || 
                    (currentTurn == Color.BLACK && !widget.isHost);

    return Scaffold(
      appBar: AppBar(
        title: Column(
          children: [
            Text(isMyTurn ? "Your Turn" : "Opponent's Turn", 
                 style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            Text(widget.isHost ? "Playing as White" : "Playing as Black", 
                 style: const TextStyle(fontSize: 12, color: Colors.white70)),
          ],
        ),
        centerTitle: true,
        backgroundColor: isMyTurn ? Colors.green.shade900 : Colors.blueGrey.shade900,
        actions: [
          IconButton(
            icon: const Icon(Icons.flag),
            tooltip: "Resign",
            onPressed: () {
              network.sendMove("RESIGN");
              network.disconnect();
              Navigator.pushReplacement(
                context, 
                MaterialPageRoute(builder: (_) => const LobbyScreen())
              );
            },
          )
        ],
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          // IgnorePointer prevents you from dragging pieces when it is NOT your turn
          child: IgnorePointer(
            ignoring: !isMyTurn,
            child: ChessBoard(
              controller: controller,
              boardColor: BoardColor.brown,
              boardOrientation: widget.isHost ? PlayerColor.white : PlayerColor.black,
              onMove: () {
                // Only send the move over Bluetooth if YOU actually made it
                if (isMyTurn && controller.game.history.isNotEmpty) {
                  var lastMove = controller.game.history.last.move;
                  
                  String from = lastMove.fromAlgebraic;
                  String to = lastMove.toAlgebraic;
                  String promotion = lastMove.promotion != null ? 'q' : '';
                  
                  // Send to opponent
                  network.sendMove("$from$to$promotion");
                  
                  // Instantly switch UI
                  setState(() {}); 
                }
              },
            ),
          ),
        ),
      ),
    );
  }
}
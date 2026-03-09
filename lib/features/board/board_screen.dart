import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_chess_board/flutter_chess_board.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../main.dart';
import 'lobby_screen.dart';

class BoardScreen extends ConsumerStatefulWidget {
  final bool isHost; // TRUE = White, FALSE = Black
  const BoardScreen({super.key, required this.isHost});

  @override
  ConsumerState<BoardScreen> createState() => _BoardScreenState();
}

class _BoardScreenState extends ConsumerState<BoardScreen> {
  final ChessBoardController controller = ChessBoardController();
  StreamSubscription? _networkSubscription;

  // Track if the game is over so we don't spam pop-ups
  bool _gameOverProcessed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final network = ref.read(networkProvider);
      
      _networkSubscription = network.onMoveReceived.listen((moveNotation) {
        if (moveNotation.length >= 4) {
          String from = moveNotation.substring(0, 2);
          String to = moveNotation.substring(2, 4);
          
          // Handle pawn promotions (e.g., "e7e8q")
          String? promotion;
          if (moveNotation.length == 5) {
            promotion = moveNotation[4];
          }

          controller.makeMoveWithPromotion(from: from, to: to, pieceToPromoteTo: promotion ?? 'q');
          _checkGameOver();
          setState(() {}); // Refresh UI for the turn indicator
        }
      });
    });

    // Listen to local moves to check for game over and refresh UI
    controller.addListener(() {
      if (mounted) {
        _checkGameOver();
        setState(() {});
      }
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
      message = game.in_stalemate ? "Stalemate." : "Draw by repetition or insufficient material.";
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
            child: const Text("Return to Lobby"),
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
    
    // Determine if it's currently this device's turn
    bool isMyTurn = (controller.game.turn == Color.WHITE && widget.isHost) || 
                    (controller.game.turn == Color.BLACK && !widget.isHost);

    return Scaffold(
      appBar: AppBar(
        title: Text(isMyTurn ? "Your Turn" : "Waiting for Opponent..."),
        centerTitle: true,
        backgroundColor: isMyTurn ? Colors.green.shade800 : Colors.grey.shade800,
        actions: [
          IconButton(
            icon: const Icon(Icons.flag), // Resign button
            tooltip: "Resign",
            onPressed: () {
              // In a full build, you'd send a "RESIGN" network packet here
              network.disconnect();
              Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const LobbyScreen()));
            },
          )
        ],
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          // Ignore pointers blocks the user from dragging pieces when it's not their turn
          child: IgnorePointer(
            ignoring: !isMyTurn,
            child: ChessBoard(
              controller: controller,
              boardColor: BoardColor.brown,
              // Flip the board based on who hosted!
              boardOrientation: widget.isHost ? PlayerColor.white : PlayerColor.black,
              onMove: () {
              if (controller.game.history.isNotEmpty) {
                // Grab the actual move object
                var lastMove = controller.game.history.last.move;
                
                // FIXED: The Dart chess package exposes these directly as strings
                String from = lastMove.fromAlgebraic;
                String to = lastMove.toAlgebraic;
                
                // Safe promotion handling (defaults to Queen if a promotion occurred)
                String promotion = lastMove.promotion != null ? 'q' : '';
                
                String moveNotation = "$from$to$promotion";
                network.sendMove(moveNotation);
              }
            },
            ),
          ),
        ),
      ),
    );
  }
}
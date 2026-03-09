import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_chess_board/flutter_chess_board.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../main.dart'; 

class BoardScreen extends ConsumerStatefulWidget {
  const BoardScreen({super.key});

  @override
  ConsumerState<BoardScreen> createState() => _BoardScreenState();
}

class _BoardScreenState extends ConsumerState<BoardScreen> {
  final ChessBoardController controller = ChessBoardController();
  StreamSubscription? _networkSubscription;

  String? selectedSquare;
  List<String> validMoves = [];

  String _getSquareName(int index) {
    int fileIndex = index % 8;
    int rankIndex = 8 - (index ~/ 8);
    String file = String.fromCharCode(97 + fileIndex); 
    return "$file$rankIndex";
  }

  void _handleSquareTap(String squareName) {
    final game = controller.game;

    setState(() {
      if (selectedSquare == squareName) {
        _clearSelection();
        return;
      }

      var piece = game.get(squareName);

      if (piece != null && piece.color == game.turn) {
        selectedSquare = squareName;
        validMoves = game.generate_moves()
            .where((move) => move.fromAlgebraic == squareName)
            .map((move) => move.toAlgebraic as String)
            .toList();
      } 
      else if (selectedSquare != null && validMoves.contains(squareName)) {
        controller.makeMove(from: selectedSquare!, to: squareName);
        ref.read(networkProvider).sendMove("${selectedSquare!}$squareName");
        _clearSelection();
      } 
      else {
        _clearSelection();
      }
    });
  }

  void _clearSelection() {
    selectedSquare = null;
    validMoves = [];
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final network = ref.read(networkProvider);
      _networkSubscription = network.onMoveReceived.listen((incomingMove) {
        controller.makeMove(
          from: incomingMove.substring(0, 2), 
          to: incomingMove.substring(2, 4)
        );
      });
    });
  }

  @override
  void dispose() {
    _networkSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final network = ref.read(networkProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Hybrid Rules Sandbox'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              controller.resetBoard();
              setState(() => _clearSelection());
            },
          ),
        ],
      ),
      body: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: AspectRatio(
              aspectRatio: 1.0, 
              child: Stack(
                children: [

                  ChessBoard(
                    controller: controller,
                    boardColor: BoardColor.brown,
                    boardOrientation: PlayerColor.white,

                    onMove: () {
                      setState(() => _clearSelection());
                    },
                  ),

                  GridView.builder(
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 8,
                    ),
                    itemCount: 64,
                    itemBuilder: (context, index) {
                      String squareName = _getSquareName(index);
                      bool isSelected = selectedSquare == squareName;
                      bool isValidMove = validMoves.contains(squareName);

                      return GestureDetector(
                        behavior: HitTestBehavior.translucent, 
                        onTap: () => _handleSquareTap(squareName),
                        child: Container(
                          color: isSelected 
                              ? Colors.green.withOpacity(0.5) 
                              : Colors.transparent,
                          child: isValidMove 
                              ? Center(
                                  child: Container(
                                    width: 16,
                                    height: 16,
                                    decoration: BoxDecoration(
                                      color: Colors.blue.withOpacity(0.7),
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                )
                              : null,
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
          
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: () => network.hostGame(),
            child: const Text("Simulate Connecting to Opponent"),
          )
        ],
      ),
    );
  }
}
// =============================================================================
// GameScreen - Couple game with questions
// =============================================================================

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/game_state.dart';

class GameScreen extends StatefulWidget {
  const GameScreen({super.key});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  @override
  void initState() {
    super.initState();
    context.read<GameState>().init();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Gioco 🎮'),
        centerTitle: true,
      ),
      body: Consumer<GameState>(
        builder: (context, state, _) {
          // Show messages
          if (state.message != null) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(state.message!)),
              );
              state.clearMessage();
            });
          }

          if (state.isLoading && state.currentQuestion == null) {
            return const Center(child: CircularProgressIndicator());
          }

          return RefreshIndicator(
            onRefresh: () => state.fetchNewQuestion(),
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Stats card
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.emoji_events, color: Colors.amber),
                          const SizedBox(width: 8),
                          Text(
                            'Match totali: ${state.gameStats}',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Question card
                  if (state.currentQuestion != null) ...[
                    _QuestionCard(
                      question: state.currentQuestion!.question,
                      optionA: state.currentQuestion!.optionA,
                      optionB: state.currentQuestion!.optionB,
                      status: state.currentQuestion!.status,
                      statusMessage: state.currentQuestion!.message,
                      isLoading: state.isLoading,
                      onAnswerA: () => state.submitAnswer('A'),
                      onAnswerB: () => state.submitAnswer('B'),
                    ),
                  ] else ...[
                    // No question available
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Column(
                          children: [
                            const Text(
                              '🤔',
                              style: TextStyle(fontSize: 64),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'Nessuna domanda disponibile',
                              style: Theme.of(context).textTheme.titleLarge,
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 16),
                            FilledButton(
                              onPressed: () => state.fetchNewQuestion(),
                              child: const Text('Ricarica'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _QuestionCard extends StatelessWidget {
  final String question;
  final String optionA;
  final String optionB;
  final String? status;
  final String? statusMessage;
  final bool isLoading;
  final VoidCallback onAnswerA;
  final VoidCallback onAnswerB;

  const _QuestionCard({
    required this.question,
    required this.optionA,
    required this.optionB,
    this.status,
    this.statusMessage,
    required this.isLoading,
    required this.onAnswerA,
    required this.onAnswerB,
  });

  @override
  Widget build(BuildContext context) {
    final isWaiting = status == 'waiting';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Text(
              question,
              style: Theme.of(context).textTheme.headlineSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            if (isWaiting) ...[
              const Icon(Icons.hourglass_empty, size: 48, color: Colors.orange),
              const SizedBox(height: 16),
              Text(
                statusMessage ?? 'Aspetta che il partner risponda',
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: Colors.orange,
                    ),
                textAlign: TextAlign.center,
              ),
            ] else ...[
              // Option A
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: isLoading ? null : onAnswerA,
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.all(16),
                    backgroundColor: Colors.blue,
                  ),
                  child: Text(
                    optionA,
                    style: const TextStyle(fontSize: 18),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'oppure',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Colors.grey,
                    ),
              ),
              const SizedBox(height: 16),

              // Option B
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: isLoading ? null : onAnswerB,
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.all(16),
                    backgroundColor: Colors.purple,
                  ),
                  child: Text(
                    optionB,
                    style: const TextStyle(fontSize: 18),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

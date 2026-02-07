// =============================================================================
// BucketListScreen - Shared bucket list with add/toggle/delete
// =============================================================================

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/bucket_state.dart';
import '../widgets/bucket_item_tile.dart';

class BucketListScreen extends StatefulWidget {
  const BucketListScreen({super.key});

  @override
  State<BucketListScreen> createState() => _BucketListScreenState();
}

class _BucketListScreenState extends State<BucketListScreen> {
  final _textController = TextEditingController();

  @override
  void initState() {
    super.initState();
    context.read<BucketState>().init();
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  void _addItem() {
    if (_textController.text.trim().isEmpty) return;

    context.read<BucketState>().addItem(_textController.text);
    _textController.clear();
    FocusScope.of(context).unfocus();
  }

  void _showAddDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Nuovo obiettivo'),
        content: TextField(
          controller: _textController,
          decoration: const InputDecoration(
            hintText: 'Cosa volete fare insieme?',
            border: OutlineInputBorder(),
          ),
          autofocus: true,
          maxLines: 2,
          onSubmitted: (_) {
            _addItem();
            Navigator.pop(context);
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annulla'),
          ),
          FilledButton(
            onPressed: () {
              _addItem();
              Navigator.pop(context);
            },
            child: const Text('Aggiungi'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Bucket List 🎯'),
        centerTitle: true,
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddDialog,
        child: const Icon(Icons.add),
      ),
      body: Consumer<BucketState>(
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

          if (state.isLoading && state.items.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }

          if (state.items.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text(
                    '📝',
                    style: TextStyle(fontSize: 64),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Nessun obiettivo ancora',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Aggiungi qualcosa da fare insieme!',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Colors.grey,
                        ),
                  ),
                ],
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: () => state.fetchBucket(),
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: state.items.length,
              itemBuilder: (context, index) {
                final item = state.items[index];
                return BucketItemTile(
                  item: item,
                  onToggle: () => state.toggleDone(item.id),
                  onDelete: () => _confirmDelete(item.id),
                );
              },
            ),
          );
        },
      ),
    );
  }

  void _confirmDelete(int id) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Elimina'),
        content: const Text('Vuoi eliminare questo obiettivo?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annulla'),
          ),
          FilledButton(
            onPressed: () {
              this.context.read<BucketState>().deleteItem(id);
              Navigator.pop(context);
            },
            child: const Text('Elimina'),
          ),
        ],
      ),
    );
  }
}

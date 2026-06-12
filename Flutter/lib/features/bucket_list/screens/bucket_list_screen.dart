// =============================================================================
// BucketListScreen - Shared Bucket List with Violet-Punk Design
// =============================================================================

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:justus/all_imports.dart';

class BucketListScreen extends StatefulWidget {
  final bool isActive;
  const BucketListScreen({super.key, this.isActive = false});

  @override
  State<BucketListScreen> createState() => _BucketListScreenState();
}

class _BucketListScreenState extends State<BucketListScreen> {
  final TextEditingController _addController = TextEditingController();
  String _selectedCategory = BucketCategory.all;
  final Map<int, bool> _pendingChanges = {};
  final Set<int> _pendingDeletes = {};
  BucketState get _bucketState => context.read<BucketState>();
  bool _dataLoadedOnce = false;

  Future<void> _loadData({bool force = false}) async {
    if (force) {
      await CacheService.clearCheckpoints([CacheService.kBucketItems]);
    }

    await _bucketState.init();
  }

  @override
  void dispose() {
    _addController.dispose();
    if (_pendingChanges.isNotEmpty) {
      unawaited(_bucketState.flushPendingChanges(_pendingChanges));
    }
    super.dispose();
  }

  void _showAddDialog() {
    String selectedAddCategory = BucketCategory.items.first;
    unawaited(showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          backgroundColor: AppColors.cardDark,
          title: Text(context.loc.bucket_addGoalTitle,
              style: const TextStyle(color: Colors.white)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _addController,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: context.loc.bucket_goalHint,
                  hintStyle: const TextStyle(color: Colors.white54),
                  enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(
                        color: AppColors.neonPurple.withValues(alpha: 0.5)),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderSide: const BorderSide(color: AppColors.neonBlue),
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(context.loc.bucket_categoryLabel,
                  style: const TextStyle(color: Colors.white70)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: BucketCategory.items
                    .map((cat) => ChoiceChip(
                          label: Text(BucketCategory.localizedLabel(cat, context.loc)),
                          selected: selectedAddCategory == cat,
                          selectedColor: BucketCategory.colorFor(cat),
                          backgroundColor: AppColors.backgroundDark,
                          labelStyle: TextStyle(
                            color: selectedAddCategory == cat
                                ? Colors.white
                                : BucketCategory.colorFor(cat).withValues(alpha: 0.7),
                          ),
                          onSelected: (selected) {
                            if (selected) {
                              setState(() => selectedAddCategory = cat);
                            }
                          },
                        ))
                    .toList(),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(context.loc.common_cancel,
                  style: const TextStyle(color: Colors.white54)),
            ),
            TextButton(
              onPressed: () {
                final text = _addController.text.trim();
                if (text.isNotEmpty) {
                  unawaited(context
                      .read<BucketState>()
                      .addItem(text, selectedAddCategory));
                  _addController.clear();
                }
                Navigator.pop(context);
              },
              child: Text(context.loc.bucket_add,
                  style: const TextStyle(color: AppColors.neonBlue)),
            ),
          ],
        ),
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isActive && !_dataLoadedOnce) {
      _dataLoadedOnce = true;
      unawaited(_loadData(force: true));
    }
    return VPScaffold(
      showAppBar: false,
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddDialog,
        backgroundColor: AppColors.neonBlue,
        child: const Icon(Icons.add, color: AppColors.backgroundDark),
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Header
            VPHeader(
              title: context.loc.bucket_title,
            ),

            // Category Filter
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                children: BucketCategory.withAll
                    .map((cat) => Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            label: Text(BucketCategory.localizedLabel(cat, context.loc)),
                            selected: _selectedCategory == cat,
                            selectedColor: cat == BucketCategory.all
                                ? AppColors.neonBlue
                                : BucketCategory.colorFor(cat),
                            backgroundColor: AppColors.cardDark,
                            labelStyle: VpWidgets.googleFont(
                              color: _selectedCategory == cat
                                  ? AppColors.backgroundDark
                                  : cat == BucketCategory.all
                                      ? Colors.white70
                                      : BucketCategory.colorFor(cat).withValues(alpha: 0.7),
                              fontWeight: _selectedCategory == cat
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                            ),
                            onSelected: (selected) {
                              if (selected) {
                                setState(() => _selectedCategory = cat);
                              }
                            },
                          ),
                        ))
                    .toList(),
              ),
            ),

            const SizedBox(height: 12),

            // List
            Expanded(
              child: RefreshIndicator(
                onRefresh: () => _loadData(force: true),
                color: AppColors.primary,
                backgroundColor: AppColors.backgroundDark,
                child: Selector<BucketState, (List<BucketItem>, bool)>(
                  selector: (_, s) => (s.items, s.isLoading),
                  builder: (context, bucketData, child) {
                    final items = bucketData.$1
                        .where((item) => !_pendingDeletes.contains(item.id))
                        .map((item) {
                      if (_pendingChanges.containsKey(item.id)) {
                        return item.copyWith(
                            done: _pendingChanges[item.id] ?? false);
                      }

                      return item;
                    }).toList();

                    if (bucketData.$2 && items.isEmpty) {
                      return ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: const [
                          SizedBox(height: 240),
                          Center(
                            child: CircularProgressIndicator(
                                color: AppColors.neonBlue),
                          ),
                        ],
                      );
                    }

                    final filteredItems = _selectedCategory == BucketCategory.all
                        ? items
                        : items
                            .where((i) => i.category == _selectedCategory)
                            .toList();

                    if (filteredItems.isEmpty) {
                      return ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: [
                          SizedBox(
                            height: 240,
                            child: _buildEmptyState(
                                context.loc.bucket_emptyCategory),
                          ),
                        ],
                      );
                    }

                    return ListView.separated(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 24, vertical: 8),
                      itemCount: filteredItems.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 16),
                      itemBuilder: (context, index) {
                        final item = filteredItems[index];

                        return _buildBucketItem(item, context.read<BucketState>());
                      },
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBucketItem(BucketItem item, BucketState state) {
    final isDone = item.done;

    return Dismissible(
      key: Key(item.id.toString()),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: Colors.red.withValues(alpha: 0.8),
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      onDismissed: (direction) {
        // Optimistic local removal — filters the item out on the very next
        // frame so the Dismissible is no longer in the tree when Flutter checks.
        setState(() => _pendingDeletes.add(item.id));
        unawaited(state.deleteItem(item.id));
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDone
              ? Colors.white.withValues(alpha: 0.05)
              : AppColors.cardDark,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isDone
                ? Colors.transparent
                : BucketCategory.colorFor(item.category).withValues(alpha: 0.3),
          ),
          boxShadow: isDone
              ? []
              : [
                  BoxShadow(
                    color: BucketCategory.colorFor(item.category).withValues(alpha: 0.1),
                    blurRadius: 10,
                  )
                ],
        ),
        child: Row(
          children: [
            // Checkbox
            GestureDetector(
              onTap: () {
                final originalItem =
                    state.items.firstWhere((i) => i.id == item.id);
                final currentDone = _pendingChanges.containsKey(item.id)
                    ? _pendingChanges[item.id] ?? originalItem.done
                    : originalItem.done;
                final newDone = !currentDone;
                setState(() {
                  if (newDone == originalItem.done) {
                    _pendingChanges.remove(item.id);
                  } else {
                    _pendingChanges[item.id] = newDone;
                  }
                });
              },
              child: Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: isDone ? AppColors.neonBlue : Colors.transparent,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: AppColors.neonBlue,
                    width: 2,
                  ),
                ),
                child: isDone
                    ? const Icon(Icons.check,
                        size: 16, color: AppColors.backgroundDark)
                    : null,
              ),
            ),
            const SizedBox(width: 16),
            // Content
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          item.text,
                          style: VpWidgets.googleFont(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: isDone ? Colors.white38 : Colors.white,
                            decoration:
                                isDone ? TextDecoration.lineThrough : null,
                            decorationColor: Colors.white38,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: BucketCategory.colorFor(item.category)
                              .withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: BucketCategory.colorFor(item.category)
                                .withValues(alpha: 0.5),
                          ),
                        ),
                        child: Text(
                          BucketCategory.localizedLabel(item.category, context.loc),
                          style: VpWidgets.googleFont(
                            fontSize: 10,
                            color: BucketCategory.colorFor(item.category),
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    context.loc
                        .bucket_createdOn(item.createdAt.split('T').first),
                    style: VpWidgets.googleFont(
                      fontSize: 12,
                      color: Colors.white38,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(String text) {
    return Center(
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: VpWidgets.googleFont(
          color: Colors.white54,
          fontSize: 16,
        ),
      ),
    );
  }


}

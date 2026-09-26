// =============================================================================
// BucketListScreen - Shared Bucket List with Violet-Punk Design
// =============================================================================

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:justus/all_imports.dart';

class BucketListScreen extends TabScreen {
  const BucketListScreen(
      {super.key, required super.tabIndex, required super.tabNotifier});

  @override
  State<BucketListScreen> createState() => _BucketListScreenState();
}

class _BucketListScreenState extends State<BucketListScreen>
    with TabScreenMixin {
  final TextEditingController _addController = TextEditingController();
  String _selectedCategory = BucketCategory.all;
  final Map<int, bool> _pendingChanges = {};
  final Set<int> _pendingDeletes = {};
  BucketState get _bucketState => context.read<BucketState>();

  @override
  Future<void> loadData({bool force = false}) async {
    if (force) {
      await CacheService.clearCheckpoints([CacheService.kBucketItems]);
    }

    await _bucketState.init();
  }

  @override
  void dispose() {
    _addController.dispose();
    super.dispose();
  }

  void _showAddDialog() {
    String selectedAddCategory = BucketCategory.items.first;
    unawaited(showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => VPDialog(
          title: context.loc.bucket_addGoalTitle,
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              VPTextField(
                controller: _addController,
                hint: context.loc.bucket_goalHint,
              ),
              const SizedBox(height: AppSpacing.md),
              Text(context.loc.bucket_categoryLabel),
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: BucketCategory.items
                    .map((cat) => ChoiceChip(
                          label: Text(
                              BucketCategory.localizedLabel(cat, context.loc)),
                          selected: selectedAddCategory == cat,
                          selectedColor: BucketCategory.colorFor(context, cat),
                          backgroundColor: context.palette.canvas,
                          labelStyle: TextStyle(
                            color: selectedAddCategory == cat
                                ? context.palette.onAccent
                                : BucketCategory.colorFor(context, cat),
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
              child: Text(context.loc.common_cancel),
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
              child: Text(context.loc.bucket_add),
            ),
          ],
        ),
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return VPScaffold(
      showAppBar: false,
      floatingActionButton: FloatingActionButton(
        tooltip: context.loc.bucket_add,
        onPressed: _showAddDialog,
        backgroundColor: context.palette.primary,
        child: Icon(Icons.add, color: context.palette.onPrimary),
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Header
            VPHeader(
              title: context.loc.bucket_title,
              onBack: () => MainShell.shellKey.currentState?.switchToTab(0),
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
                            label: Text(BucketCategory.localizedLabel(
                                cat, context.loc)),
                            selected: _selectedCategory == cat,
                            selectedColor: cat == BucketCategory.all
                                ? context.palette.accentBlue
                                : BucketCategory.colorFor(context, cat),
                            backgroundColor: context.palette.surface,
                            labelStyle: VpWidgets.googleFont(
                              color: _selectedCategory == cat
                                  ? context.palette.onAccent
                                  : cat == BucketCategory.all
                                      ? context.palette.contentSecondary
                                      : BucketCategory.colorFor(context, cat),
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
                onRefresh: () => loadData(force: true),
                color: context.palette.primary,
                backgroundColor: context.palette.canvas,
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
                        children: [
                          const SizedBox(height: 240),
                          Center(
                            child: CircularProgressIndicator(
                                color: context.palette.accentBlue),
                          ),
                        ],
                      );
                    }

                    final filteredItems =
                        _selectedCategory == BucketCategory.all
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

                        return _buildBucketItem(
                            item, context.read<BucketState>());
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
          color: context.palette.danger.withValues(alpha: 0.8),
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child: Icon(Icons.delete, color: context.palette.contentPrimary),
      ),
      onDismissed: (direction) {
        // Optimistic local removal — filters the item out on the very next
        // frame so the Dismissible is no longer in the tree when Flutter checks.
        setState(() => _pendingDeletes.add(item.id));
        unawaited(state.deleteItem(item.id));
      },
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: isDone ? context.palette.divider : context.palette.surfaceGroup,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(
            color: isDone
                ? Colors.transparent
                : BucketCategory.colorFor(context, item.category).withValues(alpha: 0.3),
          ),
          boxShadow: isDone
              ? []
              : [
                  BoxShadow(
                    color: BucketCategory.colorFor(context, item.category)
                        .withValues(alpha: 0.1),
                    blurRadius: 10,
                  )
                ],
        ),
        child: Row(
          children: [
            // Checkbox
            Semantics(
              checked: isDone,
              label: item.text,
              child: GestureDetector(
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
                  unawaited(state.toggleDone(item.id, newDone));
                },
                child: Container(
                  width: AppDims.checkbox,
                  height: AppDims.checkbox,
                  decoration: BoxDecoration(
                    color: isDone ? context.palette.accentBlue : Colors.transparent,
                    borderRadius: BorderRadius.circular(AppRadius.xs),
                    border: Border.all(
                      color: context.palette.accentBlue,
                      width: AppDims.hairline * 2,
                    ),
                  ),
                  child: isDone
                      ? Icon(Icons.check,
                          size: 16, color: context.palette.canvas)
                      : null,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
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
                            color: isDone
                                ? context.palette.contentDisabled
                                : context.palette.contentPrimary,
                            decoration:
                                isDone ? TextDecoration.lineThrough : null,
                            decorationColor: context.palette.contentDisabled,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
                        decoration: BoxDecoration(
                          color: BucketCategory.colorFor(context, item.category)
                              .withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(AppRadius.sm),
                          border: Border.all(
                            color: BucketCategory.colorFor(context, item.category)
                                .withValues(alpha: 0.5),
                          ),
                        ),
                        child: Text(
                          BucketCategory.localizedLabel(
                              item.category, context.loc),
                          style: VpWidgets.googleFont(
                            fontSize: 10,
                            color: BucketCategory.colorFor(context, item.category),
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
                      color: context.palette.contentDisabled,
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
          color: context.palette.contentTertiary,
          fontSize: 16,
        ),
      ),
    );
  }
}

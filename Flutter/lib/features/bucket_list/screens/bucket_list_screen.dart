// =============================================================================
// BucketListScreen - Shared Bucket List with Violet-Punk Design
// =============================================================================

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:justus/all_imports.dart';

/// Bespoke category-tinted pill that replaces the Material ChoiceChip in both
/// the filter bar and the add-item dialog. Identical shape, color logic, and
/// interaction in every context — no more design drift.
class _CategoryPill extends StatelessWidget {
  const _CategoryPill({
    required this.label,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final String label;

  /// The hue that tints this pill. For "All", pass `palette.primary`.
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: selected
              ? color.withValues(alpha: 0.18)
              : context.palette.surface,
          borderRadius: BorderRadius.circular(AppRadius.pill),
          border: Border.all(
            color: selected
                ? color
                : color.withValues(alpha: 0.28),
            width: selected ? 1.5 : 1.0,
          ),
        ),
        child: Text(
          label,
          style: VpWidgets.googleFont(
            fontSize: 13,
            fontWeight: selected ? FontWeight.bold : FontWeight.w500,
            color: selected ? color : color.withValues(alpha: 0.65),
          ),
        ),
      ),
    );
  }
}

class BucketListScreen extends TabScreen {
  const BucketListScreen(
      {super.key, required super.tabIndex, required super.tabNotifier});

  @override
  State<BucketListScreen> createState() => _BucketListScreenState();
}

class _BucketListScreenState extends State<BucketListScreen>
    with TabScreenMixin, StateMessageListener<BucketState, BucketListScreen> {
  final TextEditingController _addController = TextEditingController();
  String _selectedCategory = BucketCategory.all;
  final Set<int> _pendingDeletes = {};
  BucketState get _bucketState => context.read<BucketState>();

  @override
  BucketState get messageSource => _bucketState;

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
                    .map((cat) => _CategoryPill(
                          label: BucketCategory.localizedLabel(cat, context.loc),
                          color: BucketCategory.colorFor(context, cat),
                          selected: selectedAddCategory == cat,
                          onTap: () => setState(() => selectedAddCategory = cat),
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
              onPressed: () async {
                final text = _addController.text.trim();
                final added = await context
                    .read<BucketState>()
                    .addItem(text, selectedAddCategory);
                if (!context.mounted) return;
                if (added) {
                  _addController.clear();
                  Navigator.pop(context);
                }
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
              onBack: () => MainShell.of(context)?.switchToTab(0),
            ),

            // Category Filter
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                children: BucketCategory.withAll
                    .map((cat) => Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: _CategoryPill(
                            label: BucketCategory.localizedLabel(
                                cat, context.loc),
                            color: cat == BucketCategory.all
                                ? context.palette.primary
                                : BucketCategory.colorFor(context, cat),
                            selected: _selectedCategory == cat,
                            onTap: () =>
                                setState(() => _selectedCategory = cat),
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
                child: Selector<BucketState, (List<BucketItem>, bool, bool, bool)>(
                  selector: (_, s) =>
                      (s.items, s.isLoading, s.hasMore, s.isLoadingMore),
                  builder: (context, bucketData, child) {
                    final items = bucketData.$1
                        .where((item) => !_pendingDeletes.contains(item.id))
                        .toList();
                    final isLoading = bucketData.$2;
                    final hasMore = bucketData.$3;
                    final isLoadingMore = bucketData.$4;

                    if (isLoading && items.isEmpty) {
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
                          if (hasMore)
                            _buildShowMoreButton(context, isLoadingMore),
                        ],
                      );
                    }

                    return ListView.separated(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 24, vertical: 8),
                      itemCount: filteredItems.length + (hasMore ? 1 : 0),
                      separatorBuilder: (_, __) => const SizedBox(height: 16),
                      itemBuilder: (context, index) {
                        if (index >= filteredItems.length) {
                          return _buildShowMoreButton(context, isLoadingMore);
                        }
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

  Widget _buildShowMoreButton(BuildContext context, bool isLoadingMore) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: TextButton.icon(
          onPressed: isLoadingMore
              ? null
              : () => unawaited(context.read<BucketState>().loadMore()),
          icon: isLoadingMore
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Icon(Icons.expand_more, color: context.palette.primary),
          label: Text(
            context.loc.mood_showMore,
            style: VpWidgets.googleFont(
              color: context.palette.primary,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }

  /// Awaits the dismiss-triggered delete. Success: the marker stays — Realtime
  /// drops the row from the state, which is the source of truth. Failure: the
  /// row never left [BucketState.items], so clearing the marker restores it at
  /// once; the error itself is shown by BaseState/ErrorHandler alone.
  Future<void> _confirmDelete(BucketState state, int id) async {
    if (await state.deleteItem(id)) return;
    if (!mounted) return;
    setState(() => _pendingDeletes.remove(id));
  }

  Widget _buildBucketItem(BucketItem item, BucketState state) {
    final isDone = item.done;
    final createdAt = AppDateUtils.tryParse(item.createdAt)?.toLocal();

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
        unawaited(_confirmDelete(state, item.id));
      },
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color:
              isDone ? context.palette.divider : context.palette.surfaceGroup,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(
            color: isDone
                ? Colors.transparent
                : BucketCategory.colorFor(context, item.category)
                    .withValues(alpha: 0.3),
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
                onTap: () => unawaited(state.toggleDone(item.id)),
                child: Container(
                  width: AppDims.checkbox,
                  height: AppDims.checkbox,
                  decoration: BoxDecoration(
                    color: isDone
                        ? context.palette.accentBlue
                        : Colors.transparent,
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
                            color:
                                BucketCategory.colorFor(context, item.category)
                                    .withValues(alpha: 0.5),
                          ),
                        ),
                        child: Text(
                          BucketCategory.localizedLabel(
                              item.category, context.loc),
                          style: VpWidgets.googleFont(
                            fontSize: 10,
                            color:
                                BucketCategory.colorFor(context, item.category),
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    context.loc.bucket_createdOn(
                      createdAt == null
                          ? item.createdAt.split('T').first
                          : MaterialLocalizations.of(context)
                              .formatMediumDate(createdAt),
                    ),
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

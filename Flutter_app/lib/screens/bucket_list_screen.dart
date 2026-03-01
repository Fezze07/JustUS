// =============================================================================
// BucketListScreen - Shared Bucket List with Violet-Punk Design
// =============================================================================

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../constants/app_colors.dart';

class BucketListScreen extends StatefulWidget {
  const BucketListScreen({super.key});

  @override
  State<BucketListScreen> createState() => _BucketListScreenState();
}

class _BucketListScreenState extends State<BucketListScreen> {
  String _selectedCategory = 'All';
  final List<String> _categories = ['All', 'Travel', 'Home', 'Dates', 'Adventure'];
  
  // Mock Data
  final List<Map<String, dynamic>> _items = [
    {
      'title': 'See the Northern Lights',
      'description': 'A magical trip to Iceland or Norway in the winter.',
      'category': 'Travel',
      'isDone': false,
      'isFavorite': false,
    },
    {
      'title': 'Cook a 5-course meal together',
      'description': 'Testing our culinary skills at home.',
      'category': 'Dates',
      'isDone': false,
      'isFavorite': true,
    },
    {
      'title': 'Adopt a pet',
      'description': 'Finding a furry friend to join our family.',
      'category': 'Home',
      'isDone': false,
      'isFavorite': false,
    },
    {
      'title': 'Go stargazing in the desert',
      'description': 'Completed on Oct 12, 2023',
      'category': 'Adventure',
      'isDone': true,
      'isFavorite': false,
    },
    {
      'title': 'Learn to Tango',
      'description': 'Taking a weekend workshop together.',
      'category': 'Dates',
      'isDone': false,
      'isFavorite': true,
    },
  ];

  @override
  Widget build(BuildContext context) {
    // Filter items
    final filteredItems = _selectedCategory == 'All' 
        ? _items 
        : _items.where((item) => item['category'] == _selectedCategory).toList();

    return Scaffold(
      backgroundColor: AppColors.backgroundDark,
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white70),
                    onPressed: () => Navigator.pop(context),
                  ),
                  Text(
                    'Our Bucket List',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.add_circle, color: AppColors.neonBlue, size: 28),
                    onPressed: () {
                      // Add item logic
                    },
                  ),
                ],
              ),
            ),
            
            // Categories
            SizedBox(
              height: 40,
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                scrollDirection: Axis.horizontal,
                itemCount: _categories.length,
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (context, index) {
                  final category = _categories[index];
                  final isSelected = category == _selectedCategory;
                  return GestureDetector(
                    onTap: () => setState(() => _selectedCategory = category),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                      decoration: BoxDecoration(
                        color: isSelected ? AppColors.neonBlue : Colors.transparent,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: isSelected ? AppColors.neonBlue : Colors.white24,
                        ),
                        boxShadow: isSelected ? [
                          const BoxShadow(color: AppColors.neonBlue, blurRadius: 8, spreadRadius: -2)
                        ] : [],
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        category,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: isSelected ? AppColors.backgroundDark : Colors.white70,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            
            const SizedBox(height: 24),
            
            // List
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                itemCount: filteredItems.length,
                separatorBuilder: (_, __) => const SizedBox(height: 16),
                itemBuilder: (context, index) {
                  final item = filteredItems[index];
                  return _buildBucketItem(item);
                },
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {},
        backgroundColor: AppColors.neonBlue,
        child: const Icon(Icons.add, color: AppColors.backgroundDark),
      ),
    );
  }

  Widget _buildBucketItem(Map<String, dynamic> item) {
    final isDone = item['isDone'] as bool;
    final isFavorite = item['isFavorite'] as bool;
    
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDone ? Colors.white.withOpacity(0.05) : AppColors.cardDark,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDone ? Colors.transparent : AppColors.neonPurple.withOpacity(0.3),
        ),
        boxShadow: isDone ? [] : [
          BoxShadow(
            color: AppColors.neonPurple.withOpacity(0.05),
            blurRadius: 10,
          )
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Checkbox
          GestureDetector(
            onTap: () {
              setState(() {
                item['isDone'] = !isDone;
              });
            },
            child: Container(
              width: 24,
              height: 24,
              margin: const EdgeInsets.only(top: 2),
              decoration: BoxDecoration(
                color: isDone ? AppColors.neonBlue : Colors.transparent,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: AppColors.neonBlue,
                  width: 2,
                ),
              ),
              child: isDone 
                ? const Icon(Icons.check, size: 16, color: AppColors.backgroundDark) 
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
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        item['title'],
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: isDone ? Colors.white38 : Colors.white,
                          decoration: isDone ? TextDecoration.lineThrough : null,
                          decorationColor: Colors.white38,
                        ),
                      ),
                    ),
                    Icon(
                      isFavorite ? Icons.favorite : Icons.favorite_border,
                      color: isFavorite ? AppColors.neonPink : Colors.white24,
                      size: 20,
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  item['description'],
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 14,
                    color: Colors.white54,
                  ),
                ),
                const SizedBox(height: 8),
                if (!isDone)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      item['category'],
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 10,
                        color: Colors.white70,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

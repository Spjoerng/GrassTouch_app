import 'package:flutter/material.dart';
import 'data/place_filter.dart';

class PlaceFilterSheet extends StatefulWidget {
  const PlaceFilterSheet({
    super.key,
    required this.initial,
    required this.categories,
  });
  final PlaceFilter initial;
  final Set<String> categories;
  @override
  State<PlaceFilterSheet> createState() => _PlaceFilterSheetState();
}

class _PlaceFilterSheetState extends State<PlaceFilterSheet> {
  late String? category = widget.initial.category;
  late bool? visited = widget.initial.visited;
  late bool favorites = widget.initial.favoritesOnly;
  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: EdgeInsets.fromLTRB(
        24,
        0,
        24,
        20 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Filter places',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
                  ),
                ),
                IconButton(
                  tooltip: 'Close filters',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 20),
            DropdownButtonFormField<String>(
              isExpanded: true,
              key: ValueKey('category-$category'),
              initialValue: category ?? 'All categories',
              decoration: const InputDecoration(labelText: 'Category filter'),
              items: {
                'All categories',
                ?category,
                ...widget.categories,
              }.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
              onChanged: (v) =>
                  setState(() => category = v == 'All categories' ? null : v),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              isExpanded: true,
              key: ValueKey('status-$visited'),
              initialValue: visited == null
                  ? 'All statuses'
                  : visited!
                  ? 'Visited'
                  : 'Want to visit',
              decoration: const InputDecoration(
                labelText: 'Visit-status filter',
              ),
              items: [
                'All statuses',
                'Visited',
                'Want to visit',
              ].map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
              onChanged: (v) => setState(
                () => visited = v == 'All statuses' ? null : v == 'Visited',
              ),
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Favorites only'),
              secondary: const Icon(Icons.favorite_outline),
              value: favorites,
              onChanged: (v) => setState(() => favorites = v),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: () => Navigator.pop(
                context,
                PlaceFilter(
                  query: widget.initial.query,
                  category: category,
                  visited: visited,
                  favoritesOnly: favorites,
                ),
              ),
              child: const Text('Apply filters'),
            ),
            TextButton(
              onPressed: () => setState(() {
                category = null;
                visited = null;
                favorites = false;
              }),
              child: const Text('Clear filters'),
            ),
          ],
        ),
      ),
    ),
  );
}

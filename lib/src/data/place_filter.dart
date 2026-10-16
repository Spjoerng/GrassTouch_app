const placeCategories = ['Other', 'Nature', 'Food & drink', 'Culture', 'Stay'];

class PlaceFilter {
  const PlaceFilter({
    this.query = '',
    this.category,
    this.visited,
    this.favoritesOnly = false,
  });
  final String query;
  final String? category;
  final bool? visited;
  final bool favoritesOnly;

  bool matches(Map<String, Object?> place) =>
      '${place['name']} ${place['notes']} ${place['category']}'
          .toLowerCase()
          .contains(query.trim().toLowerCase()) &&
      (category == null || place['category'] == category) &&
      (visited == null || (place['visited'] == 1) == visited) &&
      (!favoritesOnly || place['favorite'] == 1);
}

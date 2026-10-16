import 'package:flutter/foundation.dart';
import 'road_router.dart';
import 'route_models.dart';

class RouteDraft extends ChangeNotifier {
  RouteDraft({List<RouteStop> stops = const [], this.road})
    : _stops = List.of(stops);
  final List<RouteStop> _stops;
  List<RouteStop> get stops => List.unmodifiable(_stops);
  RoadRoute? road;
  bool calculating = false, dirty = false, disposed = false;
  String? error;
  int revision = 0;
  void changed() {
    revision++;
    dirty = true;
    road = null;
    error = null;
    notifyListeners();
  }

  void add(RouteStop stop) {
    if (_stops.length >= 25) {
      throw const RoutingFailure('A route can have at most 25 stops.');
    }
    if (!stop.valid) throw ArgumentError('Invalid stop');
    _stops.add(stop);
    changed();
  }

  void replace(int index, RouteStop stop) {
    if (!stop.valid) throw ArgumentError('Invalid stop');
    _stops[index] = stop;
    changed();
  }

  void remove(int index) {
    _stops.removeAt(index);
    changed();
  }

  void move(int from, int to) {
    if (from == to) return;
    final stop = _stops.removeAt(from);
    _stops.insert(to, stop);
    changed();
  }

  Future<void> calculate(RoadRouter router) async {
    if (calculating) return;
    final startedAt = revision;
    final snapshot = stops;
    calculating = true;
    error = null;
    notifyListeners();
    try {
      final result = await router.route(snapshot);
      if (!disposed && revision == startedAt) {
        road = result;
        dirty = true;
      }
    } on RoutingFailure catch (failure) {
      if (!disposed && revision == startedAt) error = failure.message;
    } catch (_) {
      if (!disposed && revision == startedAt) {
        error = 'Could not calculate this route. Try again later.';
      }
    } finally {
      if (!disposed) {
        calculating = false;
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    disposed = true;
    super.dispose();
  }
}

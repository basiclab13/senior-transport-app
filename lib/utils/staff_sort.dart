import '../models/transport.dart';

/// Compare digit runs as numbers without int-size limits; never reorder source data.
int compareNaturalNames(String a, String b) {
  final parts = RegExp(r'[0-9]+|[^0-9]+');
  final left = parts
      .allMatches(a.trim().toLowerCase())
      .map((m) => m[0]!)
      .toList();
  final right = parts
      .allMatches(b.trim().toLowerCase())
      .map((m) => m[0]!)
      .toList();
  for (var i = 0; i < left.length && i < right.length; i++) {
    final x = left[i];
    final y = right[i];
    int result;
    if (RegExp(r'^[0-9]+$').hasMatch(x) && RegExp(r'^[0-9]+$').hasMatch(y)) {
      final nx = x.replaceFirst(RegExp(r'^0+'), '');
      final ny = y.replaceFirst(RegExp(r'^0+'), '');
      result = nx.length.compareTo(ny.length);
      if (result == 0) result = nx.compareTo(ny);
    } else {
      result = x.compareTo(y);
    }
    if (result != 0) return result;
  }
  final length = left.length.compareTo(right.length);
  return length != 0 ? length : a.compareTo(b);
}

int compareStaffNames(Staff a, Staff b) {
  final result = compareNaturalNames(a.name, b.name);
  return result != 0 ? result : compareNaturalNames(a.id, b.id);
}

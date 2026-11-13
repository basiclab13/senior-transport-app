import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:math';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import '../models/attendance_record.dart';

Future<Uint8List?> pickDemoPhoto() async {
  final input = web.HTMLInputElement()
    ..type = 'file'
    ..accept = 'image/jpeg,image/png'
    ..capture = 'environment';
  final chosen = Completer<web.File?>();
  final change = ((web.Event event) {
    if (!chosen.isCompleted) chosen.complete(input.files?.item(0));
  }).toJS;
  final cancel = ((web.Event event) {
    if (!chosen.isCompleted) chosen.complete(null);
  }).toJS;
  input.addEventListener('change', change);
  input.addEventListener('cancel', cancel);
  input.click();
  final web.File? file;
  try {
    file = await chosen.future;
  } finally {
    input.removeEventListener('change', change);
    input.removeEventListener('cancel', cancel);
  }
  if (file == null) return null;
  if (file.size > 10 * 1024 * 1024) {
    throw StateError('10MB 이하의 시연용 사진을 선택해 주세요.');
  }
  final bitmap = await web.window.createImageBitmap(file).toDart;
  try {
    for (final limit in [800, 600, 400]) {
      final scale = min(1.0, limit / max(bitmap.width, bitmap.height));
      final canvas = web.HTMLCanvasElement()
        ..width = max(1, (bitmap.width * scale).round())
        ..height = max(1, (bitmap.height * scale).round());
      final context = canvas.getContext('2d') as web.CanvasRenderingContext2D;
      context.drawImage(
        bitmap,
        0,
        0,
        canvas.width.toDouble(),
        canvas.height.toDouble(),
      );
      final bytes = base64Decode(
        canvas.toDataURL('image/jpeg', 0.7.toJS).split(',').last,
      );
      if (bytes.length <= AttendanceRecord.maxPhotoBytes) return bytes;
    }
    throw StateError('사진 크기가 큽니다. 더 단순한 시연용 사진을 선택해 주세요.');
  } finally {
    bitmap.close();
  }
}

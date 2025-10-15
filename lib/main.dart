import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app.dart';
import 'core/config/app_config.dart'; // <- add this line (even if unused yet)

void main() {
  runApp(const ProviderScope(child: SweetsApp()));
}

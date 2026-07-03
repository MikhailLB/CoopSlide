import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'screens/loading_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ),
  );
  runApp(const CoopSlideApp());
}

class CoopSlideApp extends StatelessWidget {
  const CoopSlideApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Coop Slide',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFF5B301)),
        useMaterial3: true,
        fontFamily: 'Roboto',
      ),
      home: const LoadingScreen(),
    );
  }
}

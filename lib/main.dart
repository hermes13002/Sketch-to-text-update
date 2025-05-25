import 'package:flutter/material.dart';
import 'package:sketch_form_app_update/drawing_screen.dart';

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Rectangle to Text',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
        scrollbarTheme: ScrollbarThemeData(
          thumbVisibility: MaterialStateProperty.all<bool>(true),
          trackVisibility: MaterialStateProperty.all<bool>(true),
          thickness: MaterialStateProperty.all<double>(20),
          radius: Radius.circular(12),
          thumbColor: MaterialStateProperty.all(Colors.grey[600]),
          trackColor: MaterialStateProperty.all(Colors.grey[200]),
          minThumbLength: 50,
        ),
      ),
      debugShowCheckedModeBanner: false,
      home: DrawingScreen(),
    );
  }
}
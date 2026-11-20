import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'app_state.dart';
import 'camera_page.dart';
import 'settings_page.dart';
import 'calendar_page.dart';
import 'notification_service.dart';
import 'timelapse_screen.dart';

// Global key for navigation
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize notification service
  await NotificationService().initialize();

  runApp(
    ChangeNotifierProvider(
      create: (_) => AppState(),
      child: const PhysiqueTrackerApp(),
    ),
  );
}

class PhysiqueTrackerApp extends StatelessWidget {
  const PhysiqueTrackerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      title: 'Physique Tracker',
      debugShowCheckedModeBanner: false,
      themeMode: context.watch<AppState>().themeMode,
      theme: ThemeData(
        brightness: Brightness.light,
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;

  List<Widget> get _screens => [
    CameraPage(
      // No forDate: uses today with a 5am cutoff (before 5am = yesterday)
      onPhotoSaved: switchToCalendar,
    ),
    const CalendarPage(),
    const TimelapseScreen(),
    const SettingsPage(),
  ];

  @override
  void initState() {
    super.initState();
    // Listen for notification navigation events
    NotificationService.navigationStream.listen((destination) {
      if (destination == 'camera') {
        setState(() {
          _currentIndex = 0; // Switch to camera tab
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _screens[_currentIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        type: BottomNavigationBarType.fixed,
        backgroundColor: Theme.of(context).colorScheme.surface,
        selectedItemColor: Theme.of(context).colorScheme.primary,
        unselectedItemColor:
            Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.camera_alt),
            label: 'Photo',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.calendar_month),
            label: 'Calendar',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.play_circle),
            label: 'Timelapse',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }

  // Navigate to camera page when notification is tapped
  void navigateToCameraPage() {
    setState(() {
      _currentIndex = 0; // Switch to camera tab
    });
  }

  // Navigate to calendar page (called after saving a photo)
  void switchToCalendar() {
    setState(() {
      _currentIndex = 1; // Switch to calendar tab
    });
  }
}

/* -------------------- SCREENS -------------------- */

class CalendarScreen extends StatelessWidget {
  const CalendarScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Calendar')),
      body: const Center(
        child: Text(
          'Calendar view placeholder',
          style: TextStyle(fontSize: 18),
        ),
      ),
    );
  }
}


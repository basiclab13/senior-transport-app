import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import 'firebase_options.dart';
import 'screens/auth_gate.dart';
import 'services/auth_service.dart';
import 'services/schedule_repository.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    const emulator = bool.fromEnvironment('USE_FIREBASE_EMULATORS');
    const emulatorHost = String.fromEnvironment(
      'EMULATOR_HOST',
      defaultValue: '127.0.0.1',
    );
    await Firebase.initializeApp(
      options: emulator
          ? const FirebaseOptions(
              apiKey: 'demo-emulator-key',
              appId: '1:123456789:web:demo',
              messagingSenderId: '123456789',
              projectId: 'demo-senior-transport',
              authDomain: 'demo-senior-transport.firebaseapp.com',
            )
          : DefaultFirebaseOptions.currentPlatform,
    );
    final functions = FirebaseFunctions.instanceFor(region: 'asia-northeast3');
    if (emulator) {
      await FirebaseAuth.instance.useAuthEmulator(emulatorHost, 9099);
      FirebaseFirestore.instance.useFirestoreEmulator(emulatorHost, 8080);
      functions.useFunctionsEmulator(emulatorHost, 5001);
    }
    if (kIsWeb) await FirebaseAuth.instance.setPersistence(Persistence.LOCAL);
    if (kDebugMode) {
      debugPrint(
        '[firebase] project=${Firebase.app().options.projectId} environment=${emulator ? 'emulator' : 'firebase'} region=asia-northeast3 auth=${emulator ? '$emulatorHost:9099' : 'firebase-auth'} firestore=${emulator ? '$emulatorHost:8080' : 'firestore.googleapis.com'} functions=${emulator ? '$emulatorHost:5001' : 'asia-northeast3 callable'}',
      );
    }
    runApp(
      MyApp(
        schedules: FirebaseScheduleRepository(
          FirebaseFirestore.instance,
          functions,
        ),
        auth: AuthService(
          FirebaseAuthRepository(
            FirebaseAuth.instance,
            FirebaseFirestore.instance,
          ),
        ),
      ),
    );
  } catch (_) {
    runApp(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'Firebase를 초기화할 수 없습니다. 설정과 네트워크 연결을 확인한 뒤 앱을 다시 실행해 주세요.',
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key, required this.auth, required this.schedules});
  final AuthService auth;
  final ScheduleRepository schedules;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: '다정 송영 관리',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF147D73)),
      scaffoldBackgroundColor: const Color(0xFFF4F7F8),
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(),
      ),
    ),
    home: AuthGate(auth: auth, schedules: schedules),
  );
}

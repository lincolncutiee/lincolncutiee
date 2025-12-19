import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image/image.dart' as img;
import 'package:camera/camera.dart';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:just_audio/just_audio.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'firebase_options.dart';

late List<CameraDescription> cameras;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  cameras = await availableCameras();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const MyApp());
}

class BrandInfo {
  final String name;
  final String description;
  final String color;

  BrandInfo({
    required this.name,
    required this.description,
    required this.color,
  });
}

final Map<String, BrandInfo> brandInfoMap = {
  'Jollibee logo': BrandInfo(
    name: 'Jollibee',
    description: 'Jollibee is a Filipino fast food company. Known for fried chicken, spaghetti, and chicken burger.',
    color: 'Red & Gold',
  ),
  'McDonald logo': BrandInfo(
    name: "McDonald's",
    description: "McDonald's is a global fast food chain. Famous for Big Mac, fries, and golden arches.",
    color: 'Red & Yellow',
  ),
  'KFC logo': BrandInfo(
    name: 'KFC',
    description: 'KFC is famous for fried chicken. Founded by Colonel Sanders with his secret recipe.',
    color: 'Red & White',
  ),
  'Chowking logo': BrandInfo(
    name: 'Chowking',
    description: 'Chowking specializes in Chinese-influenced fast food. Known for noodles and rice meals.',
    color: 'Red & Gold',
  ),
  'Greenwich logo': BrandInfo(
    name: 'Greenwich',
    description: 'Greenwich is famous for pizza. Offers various pizza sizes and toppings.',
    color: 'Orange & Red',
  ),
  'Mang Inasal logo': BrandInfo(
    name: 'Mang Inasal',
    description: 'Mang Inasal is known for grilled chicken. Popular in the Philippines with affordable meals.',
    color: 'Yellow & Red',
  ),
  'Burger King logo': BrandInfo(
    name: 'Burger King',
    description: 'Burger King is famous for flame-grilled burgers. Global fast food chain.',
    color: 'Red & Yellow',
  ),
  'Shakeys logo': BrandInfo(
    name: "Shakey's",
    description: "Shakey's offers mojos, fried chicken, and pasta. Popular Filipino chain.",
    color: 'Red & Yellow',
  ),
  'Pizza Hut logo': BrandInfo(
    name: 'Pizza Hut',
    description: 'Pizza Hut serves pizza, pasta, and wings worldwide. Known for delivery service.',
    color: 'Red & White',
  ),
  'Goldilocks logo': BrandInfo(
    name: 'Goldilocks',
    description: 'Goldilocks is a bakery known for pastries, cakes, and pastries.',
    color: 'Yellow & Gold',
  ),
};

class ThemeProvider extends ChangeNotifier {
  bool _isDarkMode = false;
  bool get isDarkMode => _isDarkMode;

  void toggleTheme() {
    _isDarkMode = !_isDarkMode;
    notifyListeners();
  }
}

class FirestoreService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  Future<void> logClassificationResult({
    required String label,
    required double confidence,
    required String imagePath,
    required String? correctedLabel,
  }) async {
    try {
      final wasLowConfidence = confidence < 0.6;
      await _db.collection('classifications').add({
        'label': label,
        'confidence': confidence,
        'correctedLabel': correctedLabel,
        'timestamp': FieldValue.serverTimestamp(),
        'imagePath': imagePath,
        'lowConfidence': wasLowConfidence,
        'wasCorrected': correctedLabel != null,
      });
    } catch (e) {
      rethrow;
    }
  }

  Stream<QuerySnapshot> getClassificationsStream() {
    return _db
        .collection('classifications')
        .orderBy('timestamp', descending: true)
        .snapshots();
  }

  Future<List<Map<String, dynamic>>> getClassificationsHistory() async {
    try {
      final snapshot = await _db
          .collection('classifications')
          .orderBy('timestamp', descending: true)
          .get();
      return snapshot.docs
          .map((doc) => {'id': doc.id, ...doc.data()})
          .toList();
    } catch (e) {
      rethrow;
    }
  }

  Future<void> deleteClassification(String docId) async {
    try {
      await _db.collection('classifications').doc(docId).delete();
    } catch (e) {
      rethrow;
    }
  }

  Future<Map<String, dynamic>> getFeedbackAnalysis() async {
    try {
      final snapshot = await _db.collection('classifications').get();
      Map<String, int> correctionCount = {};
      int totalCorrections = 0;
      int lowConfidenceCount = 0;

      for (var doc in snapshot.docs) {
        final data = doc.data();
        if (data['wasCorrected'] == true) {
          final original = data['label'] ?? 'Unknown';
          final corrected = data['correctedLabel'] ?? 'Unknown';
          final key = '$original→$corrected';
          correctionCount[key] = (correctionCount[key] ?? 0) + 1;
          totalCorrections++;
        }
        if (data['lowConfidence'] == true) {
          lowConfidenceCount++;
        }
      }

      return {
        'totalCorrections': totalCorrections,
        'lowConfidenceCount': lowConfidenceCount,
        'correctionPatterns': correctionCount,
      };
    } catch (e) {
      return {
        'totalCorrections': 0,
        'lowConfidenceCount': 0,
        'correctionPatterns': {},
      };
    }
  }
}

class AudioManager {
  late final AudioPlayer _audioPlayer;
  bool _isInitialized = false;

  AudioManager() {
    _audioPlayer = AudioPlayer();
  }

  Future<void> playSuccessSound() async {
    try {
      if (!_isInitialized) {
        await _audioPlayer.setAsset('assets/sounds/success.mp3');
        _isInitialized = true;
      }
      await _audioPlayer.play();
    } catch (e) {
      // Silently handle error
    }
  }

  void dispose() {
    _audioPlayer.dispose();
  }
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final ThemeProvider _themeProvider = ThemeProvider();
  final AudioManager _audioManager = AudioManager();

  @override
  void dispose() {
    _audioManager.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _themeProvider,
      builder: (context, _) {
        return MaterialApp(
          title: 'Fast Food Logo Classifier',
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(
              seedColor: Colors.deepOrange,
              brightness: Brightness.light,
            ),
            useMaterial3: true,
          ),
          darkTheme: ThemeData(
            colorScheme: ColorScheme.fromSeed(
              seedColor: Colors.deepOrange,
              brightness: Brightness.dark,
            ),
            useMaterial3: true,
          ),
          themeMode: _themeProvider.isDarkMode ? ThemeMode.dark : ThemeMode.light,
          home: SplashScreen(
            themeProvider: _themeProvider,
            audioManager: _audioManager,
          ),
        );
      },
    );
  }
}

class SplashScreen extends StatefulWidget {
  final ThemeProvider themeProvider;
  final AudioManager audioManager;

  const SplashScreen({
    super.key,
    required this.themeProvider,
    required this.audioManager,
  });

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(seconds: 3),
      vsync: this,
    );

    _fadeAnimation =
        Tween<double>(begin: 0.0, end: 1.0).animate(_animationController);
    _scaleAnimation =
        Tween<double>(begin: 0.8, end: 1.0).animate(_animationController);

    _animationController.forward();

    Future.delayed(const Duration(seconds: 4), () {
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (context) => OnboardingScreen(
              themeProvider: widget.themeProvider,
              audioManager: widget.audioManager,
            ),
          ),
        );
      }
    });
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ScaleTransition(
          scale: _scaleAnimation,
          child: FadeTransition(
            opacity: _fadeAnimation,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.fastfood,
                  size: 100,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(height: 24),
                Text(
                  'Fast Food Logo',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Classifier',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        color: Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class OnboardingScreen extends StatefulWidget {
  final ThemeProvider themeProvider;
  final AudioManager audioManager;

  const OnboardingScreen({
    super.key,
    required this.themeProvider,
    required this.audioManager,
  });

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  int _currentPage = 0;
  late PageController _pageController;

  final List<OnboardingPage> _pages = [
    OnboardingPage(
      title: 'Scan Logos',
      description: 'Point your camera at fast food logos to identify them instantly.',
      icon: Icons.camera_alt,
    ),
    OnboardingPage(
      title: 'Get Accuracy',
      description: 'See detailed accuracy scores and confidence levels for each prediction.',
      icon: Icons.check_circle,
    ),
    OnboardingPage(
      title: 'Learn Brands',
      description: 'Tap results to learn more about each fast food brand and its colors.',
      icon: Icons.info,
    ),
    OnboardingPage(
      title: 'Improve AI',
      description: 'Correct predictions to help improve the classification model.',
      icon: Icons.edit,
    ),
  ];

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: PageView.builder(
        controller: _pageController,
        onPageChanged: (index) {
          setState(() {
            _currentPage = index;
          });
        },
        itemCount: _pages.length,
        itemBuilder: (context, index) {
          return _buildOnboardingPage(_pages[index]);
        },
      ),
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                _pages.length,
                (index) => Container(
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  width: _currentPage == index ? 12 : 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: _currentPage == index
                        ? Theme.of(context).colorScheme.primary
                        : Colors.grey,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                if (_currentPage > 0)
                  ElevatedButton.icon(
                    onPressed: () {
                      _pageController.previousPage(
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeInOut,
                      );
                    },
                    icon: const Icon(Icons.arrow_back),
                    label: const Text('Back'),
                  )
                else
                  const SizedBox.shrink(),
                if (_currentPage == _pages.length - 1)
                  ElevatedButton.icon(
                    onPressed: () {
                      Navigator.of(context).pushReplacement(
                        MaterialPageRoute(
                          builder: (context) => HomePage(
                            themeProvider: widget.themeProvider,
                            audioManager: widget.audioManager,
                          ),
                        ),
                      );
                    },
                    icon: const Icon(Icons.check),
                    label: const Text('Get Started'),
                  )
                else
                  ElevatedButton.icon(
                    onPressed: () {
                      _pageController.nextPage(
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeInOut,
                      );
                    },
                    icon: const Icon(Icons.arrow_forward),
                    label: const Text('Next'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOnboardingPage(OnboardingPage page) {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            page.icon,
            size: 100,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: 32),
          Text(
            page.title,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          Text(
            page.description,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: Colors.grey,
                ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class OnboardingPage {
  final String title;
  final String description;
  final IconData icon;

  OnboardingPage({
    required this.title,
    required this.description,
    required this.icon,
  });
}

class FastFoodClass {
  final int id;
  final String name;
  final IconData icon;

  FastFoodClass({
    required this.id,
    required this.name,
    required this.icon,
  });
}

class MLModel {
  static const List<String> labels = [
    'Jollibee logo',
    'McDonald logo',
    'KFC logo',
    'Chowking logo',
    'Greenwich logo',
    'Mang Inasal logo',
    'Burger King logo',
    'Shakeys logo',
    'Pizza Hut logo',
    'Goldilocks logo',
  ];

  static Future<Map<String, dynamic>> classifyImage(String imagePath) async {
    try {
      final File imageFile = File(imagePath);
      final Uint8List imageBytes = imageFile.readAsBytesSync();
      img.Image? image = img.decodeImage(imageBytes);

      if (image == null) {
        return {
          'success': false,
          'error': 'Failed to decode image',
        };
      }

      image = _preprocessImage(image);
      final Map<String, double> scores = _analyzeImageFeatures(image);

      String predictedLabel = '';
      double maxScore = 0.0;

      scores.forEach((label, score) {
        if (score > maxScore) {
          maxScore = score;
          predictedLabel = label;
        }
      });

      return {
        'success': true,
        'label': predictedLabel,
        'confidence': maxScore,
      };
    } catch (e) {
      return {
        'success': false,
        'error': e.toString(),
      };
    }
  }

  static img.Image _preprocessImage(img.Image image) {
    final int centerX = image.width ~/ 2;
    final int centerY = image.height ~/ 2;
    final int cropSize = (image.width * 0.7).toInt();
    final int x1 = (centerX - cropSize ~/ 2).clamp(0, image.width - 1);
    final int y1 = (centerY - cropSize ~/ 2).clamp(0, image.height - 1);
    final int x2 = (x1 + cropSize).clamp(x1, image.width);
    final int y2 = (y1 + cropSize).clamp(y1, image.height);

    var cropped = img.copyCrop(
      image,
      x: x1,
      y: y1,
      width: x2 - x1,
      height: y2 - y1,
    );

    cropped = img.adjustColor(
      cropped,
      contrast: 1.3,
      saturation: 1.2,
      brightness: 10,
    );

    return cropped;
  }

  static Map<String, double> _analyzeImageFeatures(img.Image image) {
    Map<String, double> scores = {};
    for (var label in labels) {
      scores[label] = 0.0;
    }

    int veryBrightRed = 0;
    int darkRed = 0;
    int brightYellow = 0;
    int orange = 0;
    int white = 0;
    int black = 0;
    int brown = 0;
    int gold = 0;

    final int width = image.width;
    final int height = image.height;
    final int totalPixels = width * height;

    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        final pixel = image.getPixelSafe(x, y);
        final int r = pixel.r.toInt();
        final int g = pixel.g.toInt();
        final int b = pixel.b.toInt();

        if (r < 40 && g < 40 && b < 40) {
          black++;
        } else if (r > 245 && g > 245 && b > 245) {
          white++;
        } else if (r > 220 && g > 160 && b < 60 && g > b + 100) {
          brightYellow++;
        } else if (r > 200 && g > 140 && b < 80 && r > g + 40) {
          orange++;
        } else if (r > 220 && g < 100 && b < 80) {
          veryBrightRed++;
        } else if (r > 160 && r < 210 && g < 90 && b < 80) {
          darkRed++;
        } else if (r > 180 && g > 140 && b < 70 && r - b > 100) {
          gold++;
        } else if (r > 130 && r < 170 && g > 90 && g < 140 && b < 70) {
          brown++;
        }
      }
    }

    final veryBrightRedRatio = veryBrightRed / totalPixels;
    final darkRedRatio = darkRed / totalPixels;
    final brightYellowRatio = brightYellow / totalPixels;
    final orangeRatio = orange / totalPixels;
    final whiteRatio = white / totalPixels;
    final blackRatio = black / totalPixels;
    final brownRatio = brown / totalPixels;
    final goldRatio = gold / totalPixels;

    scores['Jollibee logo'] =
        (darkRedRatio > 0.15 ? darkRedRatio * 1.5 : 0) + 
        (goldRatio > 0.10 ? goldRatio * 1.5 : 0);
    scores['McDonald logo'] =
        (veryBrightRedRatio > 0.12 ? veryBrightRedRatio * 1.8 : 0) + 
        (brightYellowRatio > 0.15 ? brightYellowRatio * 1.8 : 0);
    scores['KFC logo'] = 
        (whiteRatio > 0.25 && blackRatio > 0.15 ? whiteRatio * 0.6 : 0) +
        (blackRatio > 0.15 ? blackRatio * 0.6 : 0);
    scores['Chowking logo'] =
        (darkRedRatio > 0.08 ? darkRedRatio * 0.4 : 0) + 
        (whiteRatio > 0.20 ? whiteRatio * 0.3 : 0);
    scores['Greenwich logo'] =
        (orangeRatio > 0.15 ? orangeRatio * 2.0 : 0);
    scores['Mang Inasal logo'] =
        (brightYellowRatio > 0.20 ? brightYellowRatio * 1.8 : 0) + 
        (goldRatio > 0.12 ? goldRatio * 1.2 : 0);
    scores['Burger King logo'] =
        (darkRedRatio > 0.12 ? darkRedRatio * 1.2 : 0) + 
        (brightYellowRatio > 0.15 ? brightYellowRatio * 1.3 : 0);
    scores['Shakeys logo'] =
        (darkRedRatio > 0.10 ? darkRedRatio * 1.3 : 0) + 
        (brightYellowRatio > 0.15 ? brightYellowRatio * 1.4 : 0);
    scores['Pizza Hut logo'] =
        (darkRedRatio > 0.15 ? darkRedRatio * 1.5 : 0) + 
        (blackRatio > 0.20 ? blackRatio * 1.0 : 0);
    scores['Goldilocks logo'] =
        (brightYellowRatio > 0.20 ? brightYellowRatio * 1.7 : 0) + 
        (goldRatio > 0.15 ? goldRatio * 1.5 : 0) + 
        (brownRatio > 0.08 ? brownRatio * 1.2 : 0);

    double maxScore = scores.values.reduce((a, b) => a > b ? a : b);

    if (maxScore < 0.05) {
      final random = Random();
      scores.forEach((label, _) {
        scores[label] = (0.4 + random.nextDouble() * 0.5).clamp(0.0, 1.0);
      });
      maxScore = scores.values.reduce((a, b) => a > b ? a : b);
    }

    scores.updateAll((label, score) => (score / (maxScore + 0.001)).clamp(0.0, 1.0));

    return scores;
  }
}

class TFLiteModel {
  static Interpreter? _interpreter;
  static bool _isInitialized = false;

  static const List<String> labels = [
    'Jollibee logo',
    'McDonald logo',
    'KFC logo',
    'Chowking logo',
    'Greenwich logo',
    'Mang Inasal logo',
    'Burger King logo',
    'Shakeys logo',
    'Pizza Hut logo',
    'Goldilocks logo',
  ];

  static Future<void> initialize() async {
    if (_isInitialized) return;
    try {
      final options = InterpreterOptions();
      _interpreter = await Interpreter.fromAsset(
        'assets/model/model_unquant.tflite',
        options: options,
      );
      _isInitialized = true;
    } catch (e) {
      rethrow;
    }
  }

  static Future<Map<String, dynamic>> classifyImage(String imagePath) async {
    if (!_isInitialized || _interpreter == null) {
      await initialize();
    }

    try {
      final File imageFile = File(imagePath);
      final Uint8List imageBytes = imageFile.readAsBytesSync();
      img.Image? image = img.decodeImage(imageBytes);

      if (image == null) {
        return {
          'success': false,
          'error': 'Failed to decode image',
        };
      }

      image = _preprocessImage(image);

      final input = _imageToByteBuffer(image);
      final output = List<List<double>>.filled(1, List<double>.filled(10, 0));

      _interpreter!.run(input, output);

      final predictions = output[0];
      double maxConfidence = 0.0;
      int maxIndex = 0;

      for (int i = 0; i < predictions.length; i++) {
        if (predictions[i] > maxConfidence) {
          maxConfidence = predictions[i];
          maxIndex = i;
        }
      }

      return {
        'success': true,
        'label': labels[maxIndex],
        'confidence': maxConfidence.clamp(0.0, 1.0),
      };
    } catch (e) {
      return {
        'success': false,
        'error': e.toString(),
      };
    }
  }

  static img.Image _preprocessImage(img.Image image) {
    final int centerX = image.width ~/ 2;
    final int centerY = image.height ~/ 2;
    final int cropSize = (image.width * 0.7).toInt();
    final int x1 = (centerX - cropSize ~/ 2).clamp(0, image.width - 1);
    final int y1 = (centerY - cropSize ~/ 2).clamp(0, image.height - 1);
    final int x2 = (x1 + cropSize).clamp(x1, image.width);
    final int y2 = (y1 + cropSize).clamp(y1, image.height);

    var cropped = img.copyCrop(
      image,
      x: x1,
      y: y1,
      width: x2 - x1,
      height: y2 - y1,
    );

    cropped = img.copyResize(cropped, width: 224, height: 224);
    cropped = img.adjustColor(cropped, contrast: 1.2, saturation: 1.1);

    return cropped;
  }

  static List<List<List<List<double>>>> _imageToByteBuffer(img.Image image) {
    final List<List<List<List<double>>>> result = List.generate(
      1,
      (_) => List.generate(
        224,
        (_) => List.generate(
          224,
          (_) => List.filled(3, 0.0),
        ),
      ),
    );

    for (int y = 0; y < 224; y++) {
      for (int x = 0; x < 224; x++) {
        final pixel = image.getPixelSafe(x, y);
        final int r = pixel.r.toInt();
        final int g = pixel.g.toInt();
        final int b = pixel.b.toInt();

        result[0][y][x][0] = r / 255.0;
        result[0][y][x][1] = g / 255.0;
        result[0][y][x][2] = b / 255.0;
      }
    }

    return result;
  }

  static void dispose() {
    _interpreter?.close();
    _isInitialized = false;
  }
}

class HomePage extends StatefulWidget {
  final ThemeProvider themeProvider;
  final AudioManager audioManager;

  const HomePage({
    super.key,
    required this.themeProvider,
    required this.audioManager,
  });

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final ImagePicker _imagePicker = ImagePicker();

  static final List<FastFoodClass> classes = [
    FastFoodClass(id: 0, name: 'Jollibee logo', icon: Icons.restaurant),
    FastFoodClass(id: 1, name: 'McDonald logo', icon: Icons.fastfood),
    FastFoodClass(id: 2, name: 'KFC logo', icon: Icons.lunch_dining),
    FastFoodClass(id: 3, name: 'Chowking logo', icon: Icons.food_bank),
    FastFoodClass(id: 4, name: 'Greenwich logo', icon: Icons.local_pizza),
    FastFoodClass(id: 5, name: 'Mang Inasal logo', icon: Icons.restaurant_menu),
    FastFoodClass(id: 6, name: 'Burger King logo', icon: Icons.fastfood),
    FastFoodClass(id: 7, name: 'Shakeys logo', icon: Icons.local_dining),
    FastFoodClass(id: 8, name: 'Pizza Hut logo', icon: Icons.local_pizza_outlined),
    FastFoodClass(id: 9, name: 'Goldilocks logo', icon: Icons.cake),
  ];

  Future<void> _scanImage() async {
    final XFile? image =
        await _imagePicker.pickImage(source: ImageSource.camera);
    if (image != null && mounted) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => ResultPage(
            imagePath: image.path,
            audioManager: widget.audioManager,
          ),
        ),
      );
    }
  }

  Future<void> _uploadImage() async {
    final XFile? image =
        await _imagePicker.pickImage(source: ImageSource.gallery);
    if (image != null && mounted) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => ResultPage(
            imagePath: image.path,
            audioManager: widget.audioManager,
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Fast Food Logo Classifier'),
        centerTitle: true,
        elevation: 0,
        actions: [
          IconButton(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (context) => const HistoryPage()),
              );
            },
            icon: const Icon(Icons.history),
            tooltip: 'View History',
          ),
          IconButton(
            onPressed: () {
              widget.themeProvider.toggleTheme();
            },
            icon: Icon(
              widget.themeProvider.isDarkMode
                  ? Icons.light_mode
                  : Icons.dark_mode,
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _scanImage,
                    icon: const Icon(Icons.camera_alt),
                    label: const Text('Scan'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      backgroundColor:
                          Theme.of(context).colorScheme.primary,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _uploadImage,
                    icon: const Icon(Icons.image),
                    label: const Text('Upload'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      backgroundColor:
                          Theme.of(context).colorScheme.secondary,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16.0),
            child: Text(
              'Or tap a class below to classify:',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(12.0),
              child: GridView.builder(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  childAspectRatio: 1,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                ),
                itemCount: classes.length,
                itemBuilder: (context, index) {
                  final fastFoodClass = classes[index];
                  return ClassCard(
                    fastFoodClass: fastFoodClass,
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (context) =>
                              ClassificationPage(
                                fastFoodClass: fastFoodClass,
                                audioManager: widget.audioManager,
                              ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class ClassCard extends StatelessWidget {
  final FastFoodClass fastFoodClass;
  final VoidCallback onTap;

  const ClassCard({
    super.key,
    required this.fastFoodClass,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Card(
        elevation: 4,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Theme.of(context).colorScheme.primary.withAlpha(200),
                Theme.of(context).colorScheme.secondary.withAlpha(200),
              ],
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                fastFoodClass.icon,
                size: 48,
                color: Colors.white,
              ),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8.0),
                child: Text(
                  fastFoodClass.name,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ClassificationPage extends StatefulWidget {
  final FastFoodClass fastFoodClass;
  final AudioManager audioManager;

  const ClassificationPage({
    super.key,
    required this.fastFoodClass,
    required this.audioManager,
  });

  @override
  State<ClassificationPage> createState() => _ClassificationPageState();
}

class _ClassificationPageState extends State<ClassificationPage>
    with SingleTickerProviderStateMixin {
  final ImagePicker _imagePicker = ImagePicker();
  late CameraController? _cameraController;
  late AnimationController _animationController;
  bool _isCameraInitialized = false;
  bool _isClassifying = false;
  String? _liveLabel;
  double? _liveConfidence;
  bool _enableLivePreview = true;

  @override
  void initState() {
    super.initState();
    _initializeCamera();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat();
  }

  Future<void> _initializeCamera() async {
    try {
      _cameraController = CameraController(
        cameras[0],
        ResolutionPreset.high,
        enableAudio: false,
      );
      await _cameraController?.initialize();
      if (mounted) {
        setState(() {
          _isCameraInitialized = true;
        });
        _startLiveClassification();
      }
    } catch (e) {
      // Silently handle error
    }
  }

  Future<void> _startLiveClassification() async {
    if (!_enableLivePreview || _cameraController == null) return;
    
    Future.delayed(const Duration(milliseconds: 500), () async {
      if (!mounted || !_enableLivePreview || _isClassifying) {
        _startLiveClassification();
        return;
      }

      try {
        if (_cameraController == null || !_cameraController!.value.isInitialized) {
          _startLiveClassification();
          return;
        }

        _isClassifying = true;
        final image = await _cameraController!.takePicture();
        
        final result = await TFLiteModel.classifyImage(image.path);
        
        if (mounted && _enableLivePreview) {
          setState(() {
            if (result['success']) {
              _liveLabel = result['label'];
              _liveConfidence = result['confidence'];
            }
            _isClassifying = false;
          });
        }
      } catch (e) {
        _isClassifying = false;
      }

      if (mounted && _enableLivePreview) {
        _startLiveClassification();
      }
    });
  }

  Future<void> _captureAndClassify() async {
    try {
      final image = await _cameraController?.takePicture();
      if (image != null && mounted) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => ResultPage(
              imagePath: image.path,
              audioManager: widget.audioManager,
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  Future<void> _openCamera() async {
    try {
      final XFile? image =
          await _imagePicker.pickImage(source: ImageSource.camera);
      if (image != null && mounted) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => ResultPage(
              imagePath: image.path,
              audioManager: widget.audioManager,
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  Widget _buildTip(String text) {
    return Text(
      text,
      style: const TextStyle(fontSize: 14),
    );
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.fastFoodClass.name),
        actions: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Tooltip(
              message: _enableLivePreview ? 'Disable live preview' : 'Enable live preview',
              child: IconButton(
                icon: Icon(_enableLivePreview ? Icons.visibility : Icons.visibility_off),
                onPressed: () {
                  setState(() {
                    _enableLivePreview = !_enableLivePreview;
                    if (_enableLivePreview) {
                      _startLiveClassification();
                    }
                  });
                },
              ),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            if (_isCameraInitialized && _cameraController != null)
              Container(
                height: 350,
                margin: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Theme.of(context).colorScheme.primary,
                    width: 2,
                  ),
                ),
                child: Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: CameraPreview(_cameraController!),
                    ),
                    Center(
                      child: ScaleTransition(
                        scale: Tween<double>(begin: 0.8, end: 1.2)
                            .animate(_animationController),
                        child: Container(
                          width: 100,
                          height: 100,
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: Colors.green,
                              width: 3,
                            ),
                            borderRadius: BorderRadius.circular(50),
                          ),
                        ),
                      ),
                    ),
                    if (_enableLivePreview)
                      Positioned(
                        top: 8,
                        right: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withAlpha(180),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  color: Colors.red,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'LIVE',
                                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                      color: Colors.red,
                                      fontWeight: FontWeight.bold,
                                    ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    if (_enableLivePreview && _liveLabel != null)
                      Positioned(
                        bottom: 8,
                        left: 8,
                        right: 8,
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.black.withAlpha(200),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: Colors.green,
                              width: 2,
                            ),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Detected: $_liveLabel',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  Expanded(
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(4),
                                      child: LinearProgressIndicator(
                                        value: _liveConfidence ?? 0.0,
                                        minHeight: 6,
                                        backgroundColor: Colors.grey[700],
                                        valueColor: AlwaysStoppedAnimation<Color>(
                                          (_liveConfidence ?? 0) > 0.7
                                              ? Colors.green
                                              : (_liveConfidence ?? 0) > 0.5
                                                  ? Colors.orange
                                                  : Colors.red,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    '${((_liveConfidence ?? 0) * 100).toStringAsFixed(0)}%',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              )
            else
              Container(
                height: 350,
                margin: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: Colors.grey[300],
                ),
                child: Center(
                  child: CircularProgressIndicator(
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary.withAlpha(20),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Theme.of(context).colorScheme.primary.withAlpha(100),
                    width: 1,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '💡 Scanning Tips:',
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                    ),
                    const SizedBox(height: 8),
                    _buildTip('📍 Center the logo in the green circle'),
                    const SizedBox(height: 6),
                    _buildTip('💡 Ensure good lighting'),
                    const SizedBox(height: 6),
                    _buildTip('✋ Keep your hand steady'),
                    const SizedBox(height: 6),
                    _buildTip('📸 Fill 70% of the frame'),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Icon(
              widget.fastFoodClass.icon,
              size: 60,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 12),
            Text(
              widget.fastFoodClass.name,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 32),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _captureAndClassify,
                      icon: const Icon(Icons.camera),
                      label: const Text('Capture'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        backgroundColor:
                            Theme.of(context).colorScheme.primary,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _openCamera,
                      icon: const Icon(Icons.image),
                      label: const Text('Gallery'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        backgroundColor:
                            Theme.of(context).colorScheme.secondary,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

class ResultPage extends StatefulWidget {
  final String imagePath;
  final AudioManager audioManager;

  const ResultPage({
    super.key,
    required this.imagePath,
    required this.audioManager,
  });

  @override
  State<ResultPage> createState() => _ResultPageState();
}

class _ResultPageState extends State<ResultPage>
    with SingleTickerProviderStateMixin {
  bool _isLoading = true;
  String? _predictedLabel;
  double? _confidence;
  String? _errorMessage;
  late AnimationController _animationController;
  String? _correctedLabel;
  late FirestoreService _firestoreService;

  @override
  void initState() {
    super.initState();
    _firestoreService = FirestoreService();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    )..repeat();
    _runInference();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _runInference() async {
    await Future.delayed(const Duration(milliseconds: 800));

    final result = await TFLiteModel.classifyImage(widget.imagePath);

    if (mounted) {
      setState(() {
        _isLoading = false;
        if (result['success']) {
          _predictedLabel = result['label'];
          _confidence = result['confidence'];
          widget.audioManager.playSuccessSound();
          _logToFirestore();
        } else {
          _errorMessage = result['error'] ?? 'Unknown error occurred';
        }
      });
    }
  }

  Future<void> _logToFirestore() async {
    if (_predictedLabel == null || _confidence == null) return;
    try {
      await _firestoreService.logClassificationResult(
        label: _predictedLabel!,
        confidence: _confidence!,
        imagePath: widget.imagePath,
        correctedLabel: _correctedLabel,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to log data: $e')),
        );
      }
    }
  }

  void _showBrandInfo() {
    if (_predictedLabel == null) return;

    final info = brandInfoMap[_predictedLabel];
    if (info == null) return;

    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                info.name,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary.withAlpha(50),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Colors: ${info.color}',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                info.description,
                style: Theme.of(context).textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showManualCorrection() {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Correct Prediction',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.withAlpha(50),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Predicted: $_predictedLabel',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    children: TFLiteModel.labels
                        .map((label) => ListTile(
                              title: Text(label),
                              onTap: () async {
                                final ctx = context;
                                setState(() {
                                  _correctedLabel = label;
                                });
                                await _logToFirestore();
                                if (mounted) {
                                  // ignore: use_build_context_synchronously
                                  Navigator.pop(ctx);
                                  // ignore: use_build_context_synchronously
                                  ScaffoldMessenger.of(ctx).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        'Thank you! Corrected to: $label',
                                      ),
                                      duration: const Duration(seconds: 2),
                                    ),
                                  );
                                }
                              },
                            ))
                        .toList(),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Classification Result'),
      ),
      body: Center(
        child: _isLoading
            ? Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ScaleTransition(
                    scale:
                        Tween<double>(begin: 0.8, end: 1.0).animate(
                          _animationController,
                        ),
                    child: CircularProgressIndicator(
                      color: Theme.of(context).colorScheme.primary,
                      strokeWidth: 4,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Analyzing image...',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Processing with AI',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.grey,
                        ),
                  ),
                ],
              )
            : _errorMessage != null
                ? Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.error_outline,
                        size: 64,
                        color: Colors.red,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        _errorMessage!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.red),
                      ),
                      const SizedBox(height: 24),
                      ElevatedButton(
                        onPressed: () {
                          Navigator.pop(context);
                        },
                        child: const Text('Go Back'),
                      ),
                    ],
                  )
                : SingleChildScrollView(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 280,
                          height: 280,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: Theme.of(context).colorScheme.primary,
                              width: 2,
                            ),
                          ),
                          child: Image.file(
                            File(widget.imagePath),
                            fit: BoxFit.cover,
                          ),
                        ),
                        const SizedBox(height: 32),
                        if ((_confidence ?? 0) < 0.6)
                          Container(
                            padding: const EdgeInsets.all(20),
                            margin: const EdgeInsets.symmetric(horizontal: 16),
                            decoration: BoxDecoration(
                              color: Colors.orange.withAlpha(50),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: Colors.orange,
                                width: 2,
                              ),
                            ),
                            child: Column(
                              children: [
                                Icon(
                                  Icons.help_outline,
                                  size: 48,
                                  color: Colors.orange,
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  'Could Not Identify',
                                  style: Theme.of(context)
                                      .textTheme
                                      .headlineSmall
                                      ?.copyWith(
                                        fontWeight: FontWeight.bold,
                                        color: Colors.orange,
                                      ),
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  'Confidence too low (${((_confidence ?? 0) * 100).toStringAsFixed(1)}%)',
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodyMedium
                                      ?.copyWith(color: Colors.grey),
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  'Please select the correct brand below',
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(color: Colors.grey),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          )
                        else
                          Container(
                            padding: const EdgeInsets.all(20),
                            margin: const EdgeInsets.symmetric(horizontal: 16),
                            decoration: BoxDecoration(
                              color: Theme.of(context)
                                  .colorScheme
                                  .primary
                                  .withAlpha(50),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: Theme.of(context).colorScheme.primary,
                                width: 2,
                              ),
                            ),
                            child: Column(
                              children: [
                                Text(
                                  'Predicted Class',
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium
                                      ?.copyWith(color: Colors.grey),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  _predictedLabel ?? 'Unknown',
                                  style: Theme.of(context)
                                      .textTheme
                                      .headlineSmall
                                      ?.copyWith(
                                        fontWeight: FontWeight.bold,
                                        color: Theme.of(context)
                                            .colorScheme
                                            .primary,
                                      ),
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 24),
                                Text(
                                  'Accuracy',
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium
                                      ?.copyWith(color: Colors.grey),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  '${((_confidence ?? 0) * 100).toStringAsFixed(2)}%',
                                  style: Theme.of(context)
                                      .textTheme
                                      .displaySmall
                                      ?.copyWith(
                                        fontWeight: FontWeight.bold,
                                        color: Theme.of(context)
                                            .colorScheme
                                            .primary,
                                      ),
                                ),
                                const SizedBox(height: 16),
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: LinearProgressIndicator(
                                    value: _confidence ?? 0,
                                    minHeight: 8,
                                    backgroundColor: Colors.grey[300],
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      Theme.of(context).colorScheme.primary,
                                    ),
                                ),
                              ),
                              if (_correctedLabel != null) ...[
                                const SizedBox(height: 16),
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: Colors.green.withAlpha(50),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    'Corrected to: $_correctedLabel',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall
                                        ?.copyWith(
                                          color: Colors.green,
                                          fontWeight: FontWeight.bold,
                                        ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16.0),
                          child: Row(
                            children: [
                              Expanded(
                                child: ElevatedButton.icon(
                                  onPressed: _showBrandInfo,
                                  icon: const Icon(Icons.info),
                                  label: const Text('Info'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor:
                                        Theme.of(context).colorScheme.primary,
                                    foregroundColor: Colors.white,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: ElevatedButton.icon(
                                  onPressed: _showManualCorrection,
                                  icon: const Icon(Icons.edit),
                                  label: const Text('Correct'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.orange,
                                    foregroundColor: Colors.white,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16.0),
                          child: Row(
                            children: [
                              Expanded(
                                child: ElevatedButton.icon(
                                  onPressed: () {
                                    Navigator.pop(context);
                                  },
                                  icon: const Icon(Icons.arrow_back),
                                  label: const Text('Back'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.grey,
                                    foregroundColor: Colors.white,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: ElevatedButton.icon(
                                  onPressed: () {
                                    Navigator.popUntil(
                                      context,
                                      (route) => route.isFirst,
                                    );
                                  },
                                  icon: const Icon(Icons.home),
                                  label: const Text('Home'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor:
                                        Theme.of(context).colorScheme.primary,
                                    foregroundColor: Colors.white,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 32),
                      ],
                    ),
                  ),
      ),
    );
  }
}

class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  late FirestoreService _firestoreService;

  @override
  void initState() {
    super.initState();
    _firestoreService = FirestoreService();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Classification History'),
        elevation: 0,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: _firestoreService.getClassificationsStream(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(
              child: Text('Error: ${snapshot.error}'),
            );
          }

          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.history,
                    size: 64,
                    color: Theme.of(context).colorScheme.primary.withAlpha(100),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No classifications yet',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Scan logos to see your history',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Colors.grey,
                        ),
                  ),
                ],
              ),
            );
          }

          final docs = snapshot.data!.docs;

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final data = docs[index].data() as Map<String, dynamic>;
              final docId = docs[index].id;
              final label = data['label'] ?? 'Unknown';
              final confidence = data['confidence'] ?? 0.0;
              final timestamp = data['timestamp'] as Timestamp?;
              final correctedLabel = data['correctedLabel'] as String?;

              final dateStr = timestamp != null
                  ? '${timestamp.toDate().month}/${timestamp.toDate().day}/${timestamp.toDate().year}'
                  : 'N/A';

              final displayLabel = correctedLabel ?? label;
              final confidencePercent = (confidence * 100).toStringAsFixed(1);

              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  displayLabel,
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium
                                      ?.copyWith(fontWeight: FontWeight.bold),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Confidence: $confidencePercent%',
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(color: Colors.grey),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  dateStr,
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(color: Colors.grey),
                                ),
                              ],
                            ),
                          ),
                          PopupMenuButton(
                            itemBuilder: (context) => [
                              PopupMenuItem(
                                child: const Text('Delete'),
                                onTap: () async {
                                  final ctx = context;
                                  await _firestoreService
                                      .deleteClassification(docId);
                                  if (mounted) {
                                    // ignore: use_build_context_synchronously
                                    ScaffoldMessenger.of(ctx).showSnackBar(
                                      const SnackBar(
                                        content:
                                            Text('Classification deleted'),
                                        duration: Duration(seconds: 2),
                                      ),
                                    );
                                  }
                                },
                              ),
                            ],
                          ),
                        ],
                      ),
                      if (correctedLabel != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.green.withAlpha(30),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              'Corrected from: $label',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(color: Colors.green),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

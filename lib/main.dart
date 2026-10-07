import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:math';
import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:http/http.dart' as http;
import 'secrets.dart';
void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Çizim Oyunu',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: Colors.deepPurple),
      home: const DrawingPage(),
    );
  }
}

class DrawingPoint {
  final Offset offset;
  final Paint paint;
  DrawingPoint(this.offset, this.paint);
}

class DrawingPage extends StatefulWidget {
  const DrawingPage({super.key});

  @override
  State<DrawingPage> createState() => _DrawingPageState();
}

class _DrawingPageState extends State<DrawingPage> {

  static const String _apiKey = Secrets.openRouterApiKey;

  final List<String> words = [
    'kedi', 'köpek', 'balık', 'kuş',
    'ev', 'araba', 'top', 'elma', 'ay',
    'güneş', 'yıldız', 'bulut', 'ağaç', 'çiçek',
    'masa', 'sandalye', 'kapı', 'pencere', 'merdiven',
    'kalem', 'kitap', 'çanta', 'bardak', 'tabak',
    'ekmek', 'pasta', 'dondurma', 'muz', 'çilek',
    'bisiklet', 'uçak', 'gemi', 'tren', 'balon',
    'şemsiye', 'şapka', 'ayakkabı', 'gözlük',
    'gökkuşağı', 'kar', 'yağmur', 'ateş',
    'tavuk', 'inek', 'kelebek', 'arı',
  ];

  final GlobalKey _canvasKey = GlobalKey();
  List<DrawingPoint?> points = [];
  String currentWord = '';
  int score = 0;
  int correctCount = 0;
  int wrongCount = 0;
  int timeLeft = 20;
  Timer? timer;
  bool gameStarted = false;
  bool isGuessing = false;
  String aiMessage = 'Çizmeye başla, AI tahmin etsin!';

  Paint get _paint => Paint()
    ..color = Colors.black
    ..strokeWidth = 5.0
    ..strokeCap = StrokeCap.round;

  @override
  void initState() {
    super.initState();
    _pickNewWord();
  }

  void _pickNewWord() {
    final random = Random();
    setState(() {
      currentWord = words[random.nextInt(words.length)];
      points.clear();
      timeLeft = 30;
      gameStarted = false;
      aiMessage = 'Çizmeye başla, AI tahmin etsin!';
    });
  }

  void _startTimer() {
    timer?.cancel();
    timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      setState(() {
        if (timeLeft > 0) {
          timeLeft--;
          if (timeLeft % 5 == 0 && points.isNotEmpty) {
            _askAI();
          }
        } else {
          t.cancel();
          _timeUp();
        }
      });
    });
  }

  Future<void> _askAI() async {
    if (isGuessing) return;
    setState(() => isGuessing = true);

    try {
      final boundary = _canvasKey.currentContext
          ?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) {
        setState(() => aiMessage = 'Canvas bulunamadı 😅');
        return;
      }

      final image = await boundary.toImage(pixelRatio: 0.5);
      final byteData =
      await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return;

      final base64Image = base64Encode(byteData.buffer.asUint8List());


      final response = await http.post(
        Uri.parse('https://openrouter.ai/api/v1/chat/completions'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $_apiKey',
        },
        body: jsonEncode({
          'model': 'google/gemini-2.5-flash',
          'max_tokens': 100,
          'messages': [
            {
              'role': 'user',
              'content': [
                {
                  'type': 'image_url',
                  'image_url': {
                    'url': 'data:image/png;base64,$base64Image',
                  },
                },
                {
                  'type': 'text',
                  'text':
                  'Bu çizimin ne olduğunu TAHMİN ET. Sadece 1-3 kelime söyle, açıklama yapma. Türkçe cevap ver.',
                },
              ],
            },
          ],
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        // OpenRouter formatı: data['choices'][0]['message']['content']
        final guess = (data['choices'][0]['message']['content'] as String)
            .trim()
            .toLowerCase();

        setState(() => aiMessage = '🤖 AI: "$guess"');

        if (guess.contains(currentWord) ||
            currentWord.contains(guess)) {
          _correctGuess(guess);
        }
      } else {
        final errBody = jsonDecode(response.body);
        final errMsg = errBody['error']?['message'] ?? response.statusCode.toString();
        setState(() => aiMessage = 'API Hatası: $errMsg 😅');
        debugPrint('OpenRouter Error ${response.statusCode}: ${response.body}');
      }
    } catch (e) {
      setState(() => aiMessage = 'Bağlantı hatası 😅');
      debugPrint('Exception: $e');
    } finally {
      if (mounted) setState(() => isGuessing = false);
    }
  }

  void _correctGuess(String guess) {
    timer?.cancel();
    final gained = 10;
    setState(() => score += gained);
    correctCount++;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: const Text('🎉 Doğru!'),
        content: Text(
            'AI "$guess" dedi!\nKelime: $currentWord\n+$gained puan!\nToplam: $score'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _pickNewWord();
              _startTimer();
            },
            child: const Text('Devam Et'),
          ),
        ],
      ),
    );
  }

  void _timeUp() {
    setState(() {
      score = (score - 5).clamp(0, 999999);
      wrongCount++;
    });
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: const Text('⏰ Süre Doldu!'),
        content: Text('Kelime: $currentWord\nToplam Puan: $score'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _pickNewWord();
              _startTimer();
            },
            child: const Text('Devam Et'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('✏️ Çizim Oyunu'),
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
        actions: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Center(
              child: Text(
                '✅$correctCount ❌$wrongCount',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Center(
              child: Text(
                '⭐ $score',
                style: const TextStyle(
                    fontSize: 20, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 16, vertical: 12),
            color: Colors.deepPurple.shade50,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '🎯 Çiz: $currentWord',
                  style: const TextStyle(
                      fontSize: 22, fontWeight: FontWeight.bold),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: timeLeft <= 10
                        ? Colors.red
                        : Colors.deepPurple,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '⏱️ $timeLeft',
                    style: const TextStyle(
                        fontSize: 18,
                        color: Colors.white,
                        fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),

          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            color: Colors.purple.shade100,
            child: Row(
              children: [
                if (isGuessing)
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    aiMessage,
                    style: const TextStyle(fontSize: 16),
                  ),
                ),
              ],
            ),
          ),

          Expanded(
            child: RepaintBoundary(
              key: _canvasKey,
              child: GestureDetector(
                onPanStart: (details) {
                  if (!gameStarted) {
                    gameStarted = true;
                    _startTimer();
                  }
                  setState(() {
                    points.add(
                        DrawingPoint(details.localPosition, _paint));
                  });
                },
                onPanUpdate: (details) {
                  setState(() {
                    points.add(
                        DrawingPoint(details.localPosition, _paint));
                  });
                },
                onPanEnd: (_) {
                  setState(() => points.add(null));
                  _askAI();
                },
                child: Container(
                  color: Colors.white,
                  child: CustomPaint(
                    painter: DrawingPainter(points),
                    child: const SizedBox.expand(),
                  ),
                ),
              ),
            ),
          ),

          Padding(
            padding: const EdgeInsets.all(12.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton.icon(
                  onPressed: () => setState(() => points.clear()),
                  icon: const Icon(Icons.delete),
                  label: const Text('Temizle'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.grey.shade600,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 12),
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: _askAI,
                  icon: const Icon(Icons.psychology),
                  label: const Text('AI Tahmin Et'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.deepPurple,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 12),
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: () {
                    timer?.cancel();
                    gameStarted = false;
                    setState(() {
                      score = (score - 15).clamp(0, 999999);
                      wrongCount++; // pas da yanlış sayılsın istersen
                    });
                    _pickNewWord();
                  },
                  icon: const Icon(Icons.skip_next),
                  label: const Text('Pas'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 12),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class DrawingPainter extends CustomPainter {
  final List<DrawingPoint?> points;
  DrawingPainter(this.points);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = Colors.white,
    );
    for (int i = 0; i < points.length - 1; i++) {
      if (points[i] != null && points[i + 1] != null) {
        canvas.drawLine(
          points[i]!.offset,
          points[i + 1]!.offset,
          points[i]!.paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(DrawingPainter oldDelegate) => true;
}

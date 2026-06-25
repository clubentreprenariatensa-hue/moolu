import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:typed_data';
import 'afis_engine.dart';
import 'database_helper.dart';
import 'sms_codec.dart';
import 'yolo_detector.dart';
import 'geometric_hasher.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const NagglyApp());
}

class NagglyApp extends StatelessWidget {
  const NagglyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Naggly OS',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.green,
          brightness: Brightness.dark,
        ),
      ),
      home: const DashboardScreen(),
    );
  }
}

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({Key? key}) : super(key: key);

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final AfisEngine _afisEngine = AfisEngine();
  final YoloDetector _yoloDetector = YoloDetector();
  final TextEditingController _smsController = TextEditingController();
  final TextEditingController _idController = TextEditingController();

  String _statusMessage = 'Prêt à scanner...';
  bool _isProcessing = false;
  int _registeredCount = 0;

  @override
  void initState() {
    super.initState();
    _yoloDetector.loadModel();
    _afisEngine.initialize();
    _loadStats();
  }

  Future<void> _loadStats() async {
    final count = await DatabaseHelper.instance.getAnimalCount();
    setState(() => _registeredCount = count);
  }

  @override
  void dispose() {
    _smsController.dispose();
    _idController.dispose();
    super.dispose();
  }

  // ─── PIPELINE COMMUNE : Photo → YOLO → C++ → Bifurcations ────────────────
  Future<List<Point>?> _extractBifurcationsFromPhoto() async {
    final picker = ImagePicker();
    final XFile? photo = await picker.pickImage(source: ImageSource.camera);
    if (photo == null) return null;

    setState(() => _statusMessage = '📷 Détection YOLO en cours...');
    final Uint8List imageBytes = await photo.readAsBytes();

    // 1. YOLO détecte le museau et crop la Zone T
    final Uint8List? croppedBytes = await _yoloDetector.detectAndCrop(imageBytes);
    if (croppedBytes == null) {
      setState(() => _statusMessage = '⚠️ Aucun museau détecté. Essaie de face.');
      return null;
    }

    setState(() => _statusMessage = '🧬 Extraction des minuties C++ (OpenCV)...');

    // 2. Extraction des bifurcations via C++ natif
    final List<Point> bifurcations = _afisEngine.extractBifurcations(
      croppedBytes, 640, 640,
    );

    if (bifurcations.isEmpty) {
      setState(() => _statusMessage = '⚠️ Aucune bifurcation extraite. Image trop floue ?');
      return null;
    }

    setState(() => _statusMessage = '📐 ${bifurcations.length} bifurcations trouvées. Triangulation...');
    return bifurcations;
  }

  // ─── 1. ENREGISTRER UNE VACHE ─────────────────────────────────────────────
  Future<void> _onEnregistrerVache() async {
    // Demander l'identifiant de la vache
    final animalId = await _showInputDialog(
      title: '🐮 Nouvel enregistrement',
      hint: 'Identifiant de la vache (ex: FR-2025-0042)',
    );
    if (animalId == null || animalId.trim().isEmpty) return;

    setState(() {
      _isProcessing = true;
      _statusMessage = '📸 Enregistrement de $animalId...';
    });

    try {
      final List<Point>? bifurcations = await _extractBifurcationsFromPhoto();
      if (bifurcations == null) return;

      // 3. Triangulation de Delaunay + Geometric Hashing
      final List<String> signatures = GeometricHasher.extractSignatures(bifurcations);

      setState(() => _statusMessage = '💾 Insertion de ${signatures.length} signatures dans la base...');

      // 4. Enregistrement dans SQLite (permanent !)
      await DatabaseHelper.instance.registerAnimal(animalId.trim(), signatures);

      // 5. Génération du code SMS (pour archivage ou partage)
      final String smsCode = SMSCodec.encode(bifurcations);

      await _loadStats();
      setState(() => _statusMessage =
        '✅ $animalId enregistrée !\n'
        '📐 ${signatures.length} triangles indexés\n'
        '💬 Code SMS (${smsCode.length} chars) généré\n'
        '🗄️ Base locale : $_registeredCount vaches');
    } catch (e) {
      setState(() => _statusMessage = '❌ Erreur : $e');
    } finally {
      setState(() => _isProcessing = false);
    }
  }

  // ─── 2. IDENTIFIER DEPUIS UNE PHOTO ───────────────────────────────────────
  Future<void> _onIdentifierPhoto() async {
    setState(() {
      _isProcessing = true;
      _statusMessage = '📸 Identification en cours...';
    });

    try {
      final List<Point>? bifurcations = await _extractBifurcationsFromPhoto();
      if (bifurcations == null) return;

      // 3. Triangulation de Delaunay + Geometric Hashing
      final List<String> signatures = GeometricHasher.extractSignatures(bifurcations);

      setState(() => _statusMessage = '🔍 Recherche parmi $_registeredCount vaches...');

      // 4. Recherche dans SQLite via l'index inversé
      final Map<String, int> votes = await DatabaseHelper.instance.identify(signatures);

      if (votes.isEmpty) {
        setState(() => _statusMessage = '❓ Vache inconnue. Elle n\'est pas dans la base locale.');
      } else {
        final best = votes.entries.reduce((a, b) => a.value > b.value ? a : b);
        final confidence = (best.value / signatures.length * 100).toStringAsFixed(1);
        setState(() => _statusMessage =
          '✅ IDENTIFIÉE : ${best.key}\n'
          '📊 Confiance : $confidence%\n'
          '📐 ${best.value}/${signatures.length} triangles en commun');
      }
    } catch (e) {
      setState(() => _statusMessage = '❌ Erreur : $e');
    } finally {
      setState(() => _isProcessing = false);
    }
  }

  // ─── 3. IDENTIFIER VIA CODE SMS (BASE LOCALE) ────────────────────────────
  Future<void> _onIdentifierSMS() async {
    final smsCode = _smsController.text.trim();
    if (smsCode.isEmpty) {
      setState(() => _statusMessage = '⚠️ Collez un code SMS avant de valider.');
      return;
    }

    setState(() {
      _isProcessing = true;
      _statusMessage = '💬 Décodage du code SMS...';
    });

    try {
      // 1. Décodage Lossless
      final List<Point> bifurcations = SMSCodec.decode(smsCode);
      setState(() => _statusMessage = '📐 ${bifurcations.length} minuties reconstitués. Triangulation...');

      // 2. Triangulation de Delaunay + Geometric Hashing
      final List<String> signatures = GeometricHasher.extractSignatures(bifurcations);

      // 3. Recherche dans SQLite (base locale du téléphone)
      final Map<String, int> votes = await DatabaseHelper.instance.identify(signatures);

      if (votes.isEmpty) {
        setState(() => _statusMessage = '❓ Aucune correspondance dans la base locale ($_registeredCount vaches).');
      } else {
        final best = votes.entries.reduce((a, b) => a.value > b.value ? a : b);
        final confidence = (best.value / signatures.length * 100).toStringAsFixed(1);
        setState(() => _statusMessage =
          '✅ IDENTIFIÉE VIA SMS : ${best.key}\n'
          '📊 Confiance : $confidence%\n'
          '📐 ${best.value}/${signatures.length} triangles');
      }
    } catch (e) {
      setState(() => _statusMessage = '❌ Code SMS invalide : $e');
    } finally {
      setState(() => _isProcessing = false);
    }
  }

  // ─── DIALOG INPUT ─────────────────────────────────────────────────────────
  Future<String?> _showInputDialog({required String title, required String hint}) {
    _idController.clear();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: _idController,
          decoration: InputDecoration(hintText: hint),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, _idController.text),
            child: const Text('Valider'),
          ),
        ],
      ),
    );
  }

  // ─── UI ───────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('🐮 Naggly OS — Edge AFIS'),
        centerTitle: true,
        elevation: 0,
        actions: [
          // Compteur de vaches dans la base
          Center(
            child: Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Text('🗄️ $_registeredCount',
                style: const TextStyle(fontSize: 14, color: Colors.greenAccent)),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(Icons.pets, size: 80, color: Colors.greenAccent),
            const SizedBox(height: 12),

            // ─ Status ─
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.green.shade900.withOpacity(0.4),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.greenAccent.withOpacity(0.4)),
              ),
              child: _isProcessing
                  ? Row(
                      children: [
                        const SizedBox(width: 20, height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.greenAccent)),
                        const SizedBox(width: 12),
                        Expanded(child: Text(_statusMessage,
                          style: const TextStyle(color: Colors.greenAccent, fontSize: 14))),
                      ],
                    )
                  : Text(_statusMessage,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.greenAccent, fontSize: 14)),
            ),

            const SizedBox(height: 24),

            // ─ Bouton ENREGISTRER ─
            ElevatedButton.icon(
              icon: const Icon(Icons.add_a_photo, size: 26),
              label: const Text('Enregistrer une Vache', style: TextStyle(fontSize: 16)),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                backgroundColor: Colors.teal.shade700,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: _isProcessing ? null : _onEnregistrerVache,
            ),

            const SizedBox(height: 14),

            // ─ Bouton IDENTIFIER PHOTO ─
            ElevatedButton.icon(
              icon: const Icon(Icons.camera_alt, size: 26),
              label: const Text('Identifier depuis Photo', style: TextStyle(fontSize: 16)),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                backgroundColor: Colors.green.shade700,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: _isProcessing ? null : _onIdentifierPhoto,
            ),

            const SizedBox(height: 24),
            const Divider(color: Colors.green),
            const SizedBox(height: 12),

            const Text('Identification via Code SMS (Base locale)',
                style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontSize: 13),
                textAlign: TextAlign.center),
            const SizedBox(height: 10),

            // ─ Champ SMS ─
            TextField(
              controller: _smsController,
              maxLines: 3,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
              decoration: InputDecoration(
                hintText: 'Collez le code SMS reçu ici...',
                filled: true,
                fillColor: Colors.black38,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: Colors.green),
                ),
              ),
            ),

            const SizedBox(height: 10),

            OutlinedButton.icon(
              icon: const Icon(Icons.sms, size: 24),
              label: const Text('Identifier via SMS', style: TextStyle(fontSize: 16)),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                foregroundColor: Colors.greenAccent,
                side: const BorderSide(color: Colors.greenAccent),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: _isProcessing ? null : _onIdentifierSMS,
            ),

            const SizedBox(height: 20),

            // ─ Option future : Serveur National SMS (désactivée) ─
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey.shade900.withOpacity(0.5),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.grey.shade700),
              ),
              child: const Row(
                children: [
                  Icon(Icons.cloud_off, color: Colors.grey, size: 20),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Serveur National (150M) — Bientôt disponible via SMS',
                      style: TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

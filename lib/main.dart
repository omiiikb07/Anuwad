import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:speech_to_text/speech_to_text.dart' as stt;

void main() => runApp(const AnuwadApp());

const green = Color(0xFF0EA36E);
const brightGreen = Color(0xFF22C55E);
const forest = Color(0xFF073D32);
const muted = Color(0xFF718078);

class AnuwadApp extends StatefulWidget {
  const AnuwadApp({super.key});
  @override
  State<AnuwadApp> createState() => _AnuwadAppState();
}

class _AnuwadAppState extends State<AnuwadApp> {
  ThemeMode mode = ThemeMode.light;

  ThemeData theme(bool dark) {
    final scheme = ColorScheme.fromSeed(
      seedColor: green,
      brightness: dark ? Brightness.dark : Brightness.light,
    );
    final background = dark ? const Color(0xFF101713) : const Color(0xFFF8FBF8);
    final surface = dark ? const Color(0xFF19231D) : Colors.white;
    final outline = dark ? const Color(0xFF34453A) : const Color(0xFFE4EBE5);
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: background,
      fontFamily: 'Arial',
      appBarTheme: AppBarTheme(backgroundColor: background, foregroundColor: dark ? Colors.white : forest, elevation: 0),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        hintStyle: TextStyle(color: dark ? Colors.white54 : muted),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide(color: outline)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide(color: outline)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: const BorderSide(color: green, width: 1.5)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Anuwad',
        debugShowCheckedModeBanner: false,
        theme: theme(false),
        darkTheme: theme(true),
        themeMode: mode,
        home: HomeScreen(
          darkMode: mode == ThemeMode.dark,
          toggleTheme: () => setState(() => mode = mode == ThemeMode.light ? ThemeMode.dark : ThemeMode.light),
        ),
      );
}

class TranslationEntry {
  const TranslationEntry(this.source, this.translation, this.sourceLanguage, this.targetLanguage, this.createdAt);
  final String source, translation, sourceLanguage, targetLanguage;
  final DateTime createdAt;
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.darkMode, required this.toggleTheme});
  final bool darkMode;
  final VoidCallback toggleTheme;
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin {
  static const backend = 'http://127.0.0.1:8000';
  final speech = stt.SpeechToText();
  final input = TextEditingController();
  late final AnimationController pulse;
  html.AudioElement? audio;
  String? audioUrl;
  StreamSubscription<html.Event>? audioEndedSubscription;
  StreamSubscription<html.Event>? audioErrorSubscription;
  bool audioPlaybackCompleted = false;
  bool hindiToKannada = true, listening = false, translating = false, speaking = false;
  String result = '', status = 'Type a message or tap the microphone.', error = '';
  final List<TranslationEntry> history = [];

  String get sourceCode => hindiToKannada ? 'hi-IN' : 'kn-IN';
  String get targetCode => hindiToKannada ? 'kn-IN' : 'hi-IN';
  String get sourceLocale => hindiToKannada ? 'hi_IN' : 'kn_IN';
  String get sourceName => hindiToKannada ? 'Hindi' : 'Kannada';
  String get targetName => hindiToKannada ? 'Kannada' : 'Hindi';

  @override
  void initState() {
    super.initState();
    pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat(reverse: true);
  }

  @override
  void dispose() {
    pulse.dispose();
    input.dispose();
    speech.stop();
    disposeAudio();
    super.dispose();
  }

  Future<void> toggleListening() async {
    if (listening) {
      await speech.stop();
      if (!mounted) return;
      setState(() {
        listening = false;
        status = input.text.trim().isEmpty ? 'Tap the microphone and speak.' : 'Voice captured. Ready to translate.';
      });
      return;
    }
    setState(() { error = ''; status = 'Checking microphone…'; });
    try {
      final available = await speech.initialize(
        onStatus: (s) {
          if (!mounted) return;
          if (s == 'done' || s == 'notListening') {
            setState(() {
              listening = false;
              status = input.text.trim().isEmpty ? 'Tap the microphone and speak.' : 'Voice captured. Ready to translate.';
            });
          }
        },
        onError: (e) {
          if (!mounted) return;
          setState(() { listening = false; error = 'Microphone error: ${e.errorMsg}'; status = 'You can type your message instead.'; });
        },
      );
      if (!available) {
        setState(() { error = 'Speech recognition is unavailable. Check browser microphone permission.'; status = 'You can type your message instead.'; });
        return;
      }
      await speech.listen(
        localeId: sourceLocale,
        onResult: (r) {
          if (!mounted) return;
          setState(() {
            input.text = r.recognizedWords;
            input.selection = TextSelection.collapsed(offset: input.text.length);
            status = r.finalResult ? 'Voice captured. Ready to translate.' : 'Listening… speak naturally.';
          });
        },
      );
      if (mounted) setState(() { listening = true; status = 'Listening… speak naturally.'; });
    } catch (_) {
      if (!mounted) return;
      setState(() { listening = false; error = 'Could not start the microphone. Check browser permissions.'; status = 'You can type your message instead.'; });
    }
  }

  void swapLanguages() => setState(() {
        hindiToKannada = !hindiToKannada;
        result = '';
        error = '';
        status = 'Language pair changed.';
      });

  Future<void> translate() async {
    final text = input.text.trim();
    if (text.isEmpty) {
      setState(() => error = 'Enter some text or use the microphone first.');
      return;
    }
    setState(() { translating = true; error = ''; status = 'Translating…'; });
    try {
      final response = await http.post(
        Uri.parse('$backend/translate'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'text': text, 'source_language': sourceCode, 'target_language': targetCode}),
      );
      if (response.statusCode < 200 || response.statusCode >= 300) throw Exception('Server returned ${response.statusCode}');
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final translated = (body['translated_text'] ?? '').toString().trim();
      if (translated.isEmpty) throw Exception('Empty translation');
      if (!mounted) return;
      setState(() {
        result = translated;
        history.insert(0, TranslationEntry(text, translated, sourceName, targetName, DateTime.now()));
        if (history.length > 8) history.removeLast();
        status = 'Translation complete.';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() { error = 'Could not translate. Make sure the Anuwad backend is running.'; status = 'Translation failed.'; });
    } finally {
      if (mounted) setState(() => translating = false);
    }
  }

  Future<void> copyResult() async {
    if (result.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: result));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Translation copied')));
  }

  Future<void> playResult() async {
    if (result.isEmpty || speaking) return;
    setState(() { error = ''; status = 'Preparing audio…'; });
    try {
      final response = await http.post(
        Uri.parse('$backend/speak'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'text': result, 'language_code': targetCode}),
      );
      if (response.statusCode < 200 || response.statusCode >= 300) throw Exception('Audio service failed');
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final encoded = (body['audio_base64'] ?? '').toString();
      if (encoded.isEmpty) throw Exception('No audio returned');
      // Cancel listeners on any previous audio element before clearing its
      // source. Clearing an old element's src can itself emit an error event;
      // that stale event must not mark the new playback as failed.
      disposeAudio();
      audioPlaybackCompleted = false;
      final blob = html.Blob([base64Decode(encoded)], 'audio/wav');
      audioUrl = html.Url.createObjectUrlFromBlob(blob);
      final currentAudio = html.AudioElement()
        ..src = audioUrl!
        ..preload = 'auto';
      audio = currentAudio;

      audioEndedSubscription = currentAudio.onEnded.listen((_) {
        audioPlaybackCompleted = true;
        if (!mounted) return;
        setState(() {
          speaking = false;
          error = '';
          status = 'Audio finished.';
        });
      });
      audioErrorSubscription = currentAudio.onError.listen((_) {
        // Ignore late/stale errors after successful completion or disposal.
        if (audioPlaybackCompleted || !identical(audio, currentAudio)) return;
        if (!mounted) return;
        setState(() {
          speaking = false;
          error = 'Audio playback failed in this browser.';
          status = 'Audio unavailable.';
        });
      });

      await currentAudio.play();
      if (mounted && identical(audio, currentAudio) && !audioPlaybackCompleted) {
        setState(() {
          speaking = true;
          error = '';
          status = 'Playing translated audio…';
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() { speaking = false; error = 'Could not play audio. Check the backend and try again.'; status = 'Audio unavailable.'; });
    }
  }

  void stopAudio() {
    audio?.pause();
    if (audio != null) audio!.currentTime = 0;
    setState(() { speaking = false; status = 'Audio stopped.'; });
  }

  void disposeAudio() {
    // Remove callbacks before pausing/clearing src: browsers may emit an
    // error event when an audio element is reset, which is not a real failure.
    audioEndedSubscription?.cancel();
    audioErrorSubscription?.cancel();
    audioEndedSubscription = null;
    audioErrorSubscription = null;

    final oldAudio = audio;
    final oldUrl = audioUrl;
    audio = null;
    audioUrl = null;

    try {
      oldAudio?.pause();
      if (oldAudio != null) oldAudio.src = '';
      if (oldUrl != null) html.Url.revokeObjectUrl(oldUrl);
    } catch (_) {}
  }

  void loadEntry(TranslationEntry entry) => setState(() {
        hindiToKannada = entry.sourceLanguage == 'Hindi';
        input.text = entry.source;
        result = entry.translation;
        error = '';
        status = 'Recent translation loaded.';
      });

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final width = MediaQuery.sizeOf(context).width;
    final wide = width >= 880;
    final surface = dark ? const Color(0xFF19231D) : Colors.white;
    final border = dark ? const Color(0xFF34453A) : const Color(0xFFE4EBE5);
    final ink = dark ? const Color(0xFFF2F7F3) : forest;
    final secondary = dark ? const Color(0xFFACB9AF) : muted;

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 76,
        title: Row(
          children: [
            BrandMark(size: 42),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Anuwad',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 23,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.7,
                      color: ink,
                    ),
                  ),
                  Text(
                    'Bridging languages, Bringing people closer.',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11, color: secondary),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(tooltip: dark ? 'Light mode' : 'Dark mode', onPressed: widget.toggleTheme, icon: Icon(dark ? Icons.light_mode_rounded : Icons.dark_mode_rounded)),
          const SizedBox(width: 12),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1180),
          child: Padding(
            padding: EdgeInsets.fromLTRB(wide ? 28 : 16, 10, wide ? 28 : 16, 22),
            child: wide
                ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(flex: 6, child: SingleChildScrollView(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      intro(ink, secondary), const SizedBox(height: 20),
                      languageSelector(surface, border, ink), const SizedBox(height: 14),
                      inputCard(surface, border, ink, secondary), const SizedBox(height: 14),
                      micPanel(border, ink, secondary, dark), const SizedBox(height: 14),
                      actionButtons(), if (error.isNotEmpty) errorBox(), const SizedBox(height: 18), statusLine(secondary),
                    ]))),
                    const SizedBox(width: 24),
                    Expanded(flex: 5, child: SingleChildScrollView(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      resultCard(surface, border, ink, secondary, dark), const SizedBox(height: 22),
                      historySection(surface, border, ink, secondary),
                    ]))),
                  ])
                : SingleChildScrollView(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    intro(ink, secondary), const SizedBox(height: 18),
                    languageSelector(surface, border, ink), const SizedBox(height: 12),
                    inputCard(surface, border, ink, secondary), const SizedBox(height: 12),
                    micPanel(border, ink, secondary, dark), const SizedBox(height: 12),
                    actionButtons(), if (error.isNotEmpty) errorBox(), const SizedBox(height: 12),
                    statusLine(secondary), const SizedBox(height: 18),
                    resultCard(surface, border, ink, secondary, dark), const SizedBox(height: 20),
                    historySection(surface, border, ink, secondary), const SizedBox(height: 16),
                  ])),
          ),
        ),
      ),
    );
  }

  Widget intro(Color ink, Color secondary) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Say it your way.', style: TextStyle(fontSize: 30, height: 1.15, fontWeight: FontWeight.w800, letterSpacing: -1, color: ink)),
          const SizedBox(height: 7),
          Text('Translate naturally. Understand each other better.', style: TextStyle(fontSize: 14, color: secondary)),
        ]),
      );

  Widget languageSelector(Color surface, Color border, Color ink) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: surface, border: Border.all(color: border), borderRadius: BorderRadius.circular(22)),
        child: Row(children: [
          Expanded(child: languagePill(sourceName, ink)),
          IconButton(tooltip: 'Swap languages', onPressed: swapLanguages, icon: const Icon(Icons.swap_horiz_rounded, color: green, size: 28)),
          Expanded(child: languagePill(targetName, ink)),
        ]),
      );

  Widget languagePill(String label, Color ink) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(color: green.withValues(alpha: 0.09), borderRadius: BorderRadius.circular(14)),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Icon(Icons.language_rounded, size: 18, color: green), const SizedBox(width: 7),
          Flexible(child: Text(label, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w700, color: ink))),
        ]),
      );

  Widget inputCard(Color surface, Color border, Color ink, Color secondary) => Container(
        padding: const EdgeInsets.fromLTRB(16, 15, 16, 10),
        decoration: BoxDecoration(color: surface, borderRadius: BorderRadius.circular(22), border: Border.all(color: border)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text('Your message', style: TextStyle(color: secondary, fontSize: 12, fontWeight: FontWeight.w700))),
            Text('${input.text.length}/500', style: TextStyle(color: secondary, fontSize: 11)),
            if (input.text.isNotEmpty) IconButton(visualDensity: VisualDensity.compact, tooltip: 'Clear text', onPressed: () => setState(() { input.clear(); result = ''; error = ''; }), icon: const Icon(Icons.close_rounded, size: 18)),
          ]),
          TextField(
            controller: input,
            maxLength: 500,
            minLines: 4,
            maxLines: 7,
            style: TextStyle(fontSize: 18, height: 1.45, color: ink),
            decoration: const InputDecoration(hintText: 'Type something to translate…', counterText: '', filled: false, border: InputBorder.none, contentPadding: EdgeInsets.only(top: 8, bottom: 8)),
            onChanged: (_) => setState(() {}),
          ),
          Row(children: [
            Icon(Icons.lock_outline_rounded, size: 14, color: secondary), const SizedBox(width: 5),
            Expanded(child: Text('Your words, your conversation.', style: TextStyle(fontSize: 11, color: secondary))),
            IconButton(tooltip: 'Paste', onPressed: () async {
              final data = await Clipboard.getData('text/plain');
              if (data?.text != null) setState(() => input.text = data!.text!);
            }, icon: Icon(Icons.content_paste_rounded, size: 19, color: secondary)),
          ]),
        ]),
      );

  Widget micPanel(Color border, Color ink, Color secondary, bool dark) => Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 14),
        decoration: BoxDecoration(color: dark ? const Color(0xFF17251D) : const Color(0xFFF0FAF2), border: Border.all(color: border), borderRadius: BorderRadius.circular(22)),
        child: Row(children: [
          AnimatedBuilder(
            animation: pulse,
            builder: (context, child) => Transform.scale(scale: listening ? 1 + pulse.value * 0.12 : 1, child: child),
            child: InkWell(
              onTap: toggleListening,
              customBorder: const CircleBorder(),
              child: Container(
                width: 66, height: 66,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(colors: [brightGreen, green, forest], begin: Alignment.topLeft, end: Alignment.bottomRight),
                  boxShadow: [BoxShadow(color: green.withValues(alpha: listening ? 0.34 : 0.18), blurRadius: listening ? 24 : 12, spreadRadius: listening ? 3 : 0)],
                ),
                child: Icon(listening ? Icons.stop_rounded : Icons.mic_rounded, color: Colors.white, size: 29),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(listening ? 'Listening…' : 'Prefer speaking?', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: ink)),
            const SizedBox(height: 4),
            Text(listening ? 'Tap the button to stop' : 'Tap the microphone and speak', style: TextStyle(fontSize: 12, color: secondary)),
            const SizedBox(height: 8),
            if (listening)
              Row(children: List.generate(13, (i) => AnimatedBuilder(
                animation: pulse,
                builder: (_, _) => Container(
                  margin: const EdgeInsets.only(right: 3), width: 3,
                  height: 5 + (((i % 4) + 1) * 4 * (pulse.value + 0.25)),
                  decoration: BoxDecoration(color: green, borderRadius: BorderRadius.circular(5)),
                ),
              )))
            else
              const Text('VOICE INPUT', style: TextStyle(color: green, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 1)),
          ])),
        ]),
      );

  Widget actionButtons() => Row(children: [
        Expanded(child: OutlinedButton.icon(
          onPressed: input.text.trim().isEmpty ? null : () => setState(() { input.clear(); result = ''; error = ''; status = 'Ready for a new translation.'; }),
          icon: const Icon(Icons.delete_outline_rounded, size: 18), label: const Text('Clear'),
          style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 15), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))),
        )),
        const SizedBox(width: 10),
        Expanded(flex: 2, child: FilledButton.icon(
          onPressed: translating ? null : translate,
          icon: translating ? const SizedBox(width: 17, height: 17, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.auto_awesome_rounded, size: 19),
          label: Text(translating ? 'Translating…' : 'Translate'),
          style: FilledButton.styleFrom(backgroundColor: green, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 15), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))),
        )),
      ]);

  Widget resultCard(Color surface, Color border, Color ink, Color secondary, bool dark) => Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(color: surface, borderRadius: BorderRadius.circular(24), border: Border.all(color: border), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: dark ? 0.08 : 0.025), blurRadius: 20, offset: const Offset(0, 7))]),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: green.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)), child: const Icon(Icons.auto_awesome_rounded, color: green, size: 18)),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Translation', style: TextStyle(fontWeight: FontWeight.w800, color: ink, fontSize: 15)),
              Text(targetName, style: TextStyle(fontSize: 12, color: secondary)),
            ])),
            if (result.isNotEmpty) IconButton(tooltip: 'Copy translation', onPressed: copyResult, icon: const Icon(Icons.copy_rounded, size: 19)),
          ]),
          const SizedBox(height: 16),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            child: result.isEmpty
                ? Container(key: const ValueKey('empty'), width: double.infinity, padding: const EdgeInsets.symmetric(vertical: 20), child: Column(children: [
                    Icon(Icons.forum_outlined, size: 32, color: secondary.withValues(alpha: 0.7)),
                    const SizedBox(height: 9),
                    Text('Your translation will appear here', textAlign: TextAlign.center, style: TextStyle(color: secondary, fontSize: 13)),
                  ]))
                : Container(
                    key: ValueKey(result), width: double.infinity, padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(colors: dark ? [const Color(0xFF1B382A), const Color(0xFF172820)] : [const Color(0xFFE9F9EE), const Color(0xFFF5FCF6)], begin: Alignment.topLeft, end: Alignment.bottomRight),
                      borderRadius: BorderRadius.circular(17),
                    ),
                    child: SelectableText(result, style: TextStyle(fontSize: 21, height: 1.5, fontWeight: FontWeight.w600, color: ink)),
                  ),
          ),
          if (result.isNotEmpty) ...[
            const SizedBox(height: 13),
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: copyResult,
                  icon: const Icon(Icons.copy_rounded, size: 17),
                  label: const Text('Copy', maxLines: 1, overflow: TextOverflow.ellipsis),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  onPressed: speaking ? stopAudio : playResult,
                  icon: Icon(speaking ? Icons.stop_rounded : Icons.volume_up_rounded, size: 18),
                  label: Text(
                    speaking ? 'Stop audio' : 'Listen',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: forest,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
                  ),
                ),
              ),
            ]),
          ],
        ]),
      );

  Widget historySection(Color surface, Color border, Color ink, Color secondary) => Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(color: surface, borderRadius: BorderRadius.circular(24), border: Border.all(color: border)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [Expanded(child: Text('Recent translations', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: ink))), Text('${history.length}', style: TextStyle(color: secondary, fontSize: 12))]),
          const SizedBox(height: 12),
          if (history.isEmpty)
            Padding(padding: const EdgeInsets.symmetric(vertical: 18), child: Center(child: Column(children: [
              Icon(Icons.history_rounded, color: secondary, size: 28), const SizedBox(height: 8),
              Text('Your recent translations will show up here.', textAlign: TextAlign.center, style: TextStyle(color: secondary, fontSize: 12)),
            ])))
          else
            ...history.map((entry) => InkWell(
              onTap: () => loadEntry(entry),
              borderRadius: BorderRadius.circular(14),
              child: Padding(padding: const EdgeInsets.symmetric(vertical: 10), child: Row(children: [
                Container(width: 34, height: 34, decoration: BoxDecoration(color: green.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(11)), child: const Icon(Icons.translate_rounded, color: green, size: 17)),
                const SizedBox(width: 10),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(entry.source, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w700, color: ink, fontSize: 13)),
                  const SizedBox(height: 3),
                  Text(entry.translation, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: secondary, fontSize: 12)),
                ])),
                const SizedBox(width: 8), Icon(Icons.chevron_right_rounded, color: secondary, size: 20),
              ])),
            )),
        ]),
      );

  Widget statusLine(Color secondary) => Row(children: [
        Icon(Icons.circle, size: 7, color: error.isNotEmpty ? Colors.redAccent : green),
        const SizedBox(width: 8), Expanded(child: Text(status, style: TextStyle(color: secondary, fontSize: 12))),
      ]);

  Widget errorBox() => Container(
        margin: const EdgeInsets.only(top: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: const Color(0xFFFFEEEE), borderRadius: BorderRadius.circular(14), border: Border.all(color: const Color(0xFFFFCCCC))),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Icon(Icons.error_outline_rounded, color: Colors.redAccent, size: 19), const SizedBox(width: 8),
          Expanded(child: Text(error, style: const TextStyle(color: Color(0xFF9E2A2A), fontSize: 12))),
        ]),
      );
}

class BrandMark extends StatelessWidget {
  const BrandMark({super.key, required this.size});
  final double size;
  @override
  Widget build(BuildContext context) => Container(
        width: size, height: size,
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(size * 0.3), gradient: const LinearGradient(colors: [brightGreen, green, forest], begin: Alignment.topLeft, end: Alignment.bottomRight)),
        child: Stack(alignment: Alignment.center, children: [
          Transform.rotate(angle: -0.5, child: Container(width: size * 0.57, height: size * 0.25, decoration: BoxDecoration(border: Border.all(color: Colors.white, width: size * 0.09), borderRadius: BorderRadius.circular(size)))),
          Icon(Icons.chat_bubble_outline_rounded, color: Colors.white, size: size * 0.46),
        ]),
      );
}

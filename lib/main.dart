
import 'dart:convert';
import 'dart:html' as html;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:speech_to_text/speech_to_text.dart' as stt;

void main() {
  runApp(const AnuwadApp());
}

class AnuwadApp extends StatelessWidget {
  const AnuwadApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Anuwad',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF267A70),
        ),
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
  final stt.SpeechToText _speech = stt.SpeechToText();
  final TextEditingController _textController = TextEditingController();

  bool hindiToKannada = true;
  bool _isListening = false;
  bool _speechAvailable = false;
  bool _isTranslating = false;
  bool _isSpeaking = false;

  String _status = 'Tap the microphone and speak.';
  String _translatedText = '';

  static const String _backendUrl = 'http://127.0.0.1:8000';
  html.AudioElement? _audioElement;
  String? _audioObjectUrl;

  String get _sourceLocale => hindiToKannada ? 'hi_IN' : 'kn_IN';
  String get _sourceLanguage => hindiToKannada ? 'hi-IN' : 'kn-IN';
  String get _targetLanguage => hindiToKannada ? 'kn-IN' : 'hi-IN';

  @override
  void initState() {
    super.initState();
    _textController.addListener(_clearOldTranslation);


  }

  void _clearOldTranslation() {
    if (_translatedText.isNotEmpty && mounted) {
      setState(() {
        _translatedText = '';
      });
    }
  }

  @override
  void dispose() {
    _speech.stop();
    _disposeAudio();
    _textController.removeListener(_clearOldTranslation);
    _textController.dispose();
    super.dispose();
  }

  void _disposeAudio() {
    try {
      _audioElement?.pause();
      _audioElement?.src = '';
      if (_audioObjectUrl != null) {
        html.Url.revokeObjectUrl(_audioObjectUrl!);
      }
    } catch (error) {
      debugPrint('Audio cleanup error: $error');
    }
    _audioElement = null;
    _audioObjectUrl = null;
  }

  Future<void> _startListening() async {
    try {
      _speechAvailable = await _speech.initialize(
        onStatus: (status) {
          if (!mounted) return;
          setState(() {
            _isListening = status == 'listening';
            if (!_isListening && _status == 'Listening...') {
              _status = 'Listening finished. Review your text.';
            }
          });
        },
        onError: (error) {
          if (!mounted) return;
          setState(() {
            _isListening = false;
            _status = 'Speech error: ${error.errorMsg}';
          });
        },
      );

      if (!_speechAvailable) {
        setState(() {
          _status =
              'Speech recognition unavailable. Check microphone permission.';
        });
        return;
      }

      setState(() {
        _isListening = true;
        _status = 'Listening...';
      });

      await _speech.listen(
        localeId: _sourceLocale,
        onResult: (result) {
          if (!mounted) return;
          setState(() {
            _textController.text = result.recognizedWords;
            _textController.selection = TextSelection.collapsed(
              offset: _textController.text.length,
            );
            if (result.finalResult) {
              _status = 'Review your text before translating.';
            }
          });
        },
      );
    } catch (error, stackTrace) {
      debugPrint('Speech error: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (!mounted) return;
      setState(() {
        _isListening = false;
        _status = 'Could not start speech recognition.';
      });
    }
  }

  Future<void> _toggleListening() async {
    if (_isListening) {
      await _speech.stop();
      if (!mounted) return;
      setState(() {
        _isListening = false;
        _status = 'Review your text before translating.';
      });
    } else {
      await _startListening();
    }
  }

  void _swapLanguages() {
    setState(() {
      hindiToKannada = !hindiToKannada;
      _translatedText = '';
      _status = 'Language direction changed. Ready to speak.';
    });
  }

  Future<void> _translateText() async {
    final text = _textController.text.trim();

    if (text.isEmpty) {
      setState(() {
        _status = 'Please speak or type some text first.';
      });
      return;
    }

    if (_isTranslating) return;

    await _stopSpeaking();

    setState(() {
      _isTranslating = true;
      _translatedText = '';
      _status = 'Translating...';
    });

    debugPrint('Anuwad: sending translation request');
    debugPrint('Source: $_sourceLanguage, target: $_targetLanguage');
    debugPrint('Input text: $text');

    try {
      final response = await http
          .post(
            Uri.parse('$_backendUrl/translate'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'text': text,
              'source_language': _sourceLanguage,
              'target_language': _targetLanguage,
            }),
          )
          .timeout(const Duration(seconds: 30));

      debugPrint('Anuwad HTTP status: ${response.statusCode}');
      debugPrint('Anuwad response body: ${response.body}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final translated = data['translated_text'] as String? ?? '';

        debugPrint('Anuwad translated text: $translated');

        if (!mounted) return;

        setState(() {
          _translatedText = translated;
          _status = translated.isNotEmpty
              ? 'Translation complete.'
              : 'The backend returned an empty translation.';
        });
      } else {
        if (!mounted) return;
        setState(() {
          _status =
              'Translation failed (${response.statusCode}). Check the backend.';
        });
      }
    } catch (error, stackTrace) {
      debugPrint('Anuwad translation exception: $error');
      debugPrintStack(stackTrace: stackTrace);

      if (!mounted) return;
      setState(() {
        _status = 'Translation request failed: $error';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isTranslating = false;
        });
      }
    }
  }

  Future<void> _copyTranslation() async {
    if (_translatedText.isEmpty) return;

    try {
      await Clipboard.setData(
        ClipboardData(text: _translatedText),
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Translation copied!')),
      );
    } catch (error) {
      debugPrint('Clipboard error: $error');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not copy the translation.')),
      );
    }
  }

  Future<void> _speakTranslation() async {
    if (_translatedText.trim().isEmpty || _isSpeaking) return;

    try {
      await _stopSpeaking();
      if (!mounted) return;
      setState(() {
        _isSpeaking = true;
        _status = 'Generating translated audio...';
      });

      final response = await http
          .post(
            Uri.parse('$_backendUrl/speak'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'text': _translatedText,
              'language_code': _targetLanguage,
            }),
          )
          .timeout(const Duration(seconds: 60));

      if (response.statusCode != 200) {
        throw Exception('Speech generation failed (${response.statusCode}): ${response.body}');
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final audioBase64 = data['audio_base64'] as String?;
      if (audioBase64 == null || audioBase64.isEmpty) {
        throw Exception('The backend returned no audio data.');
      }

      final audioBytes = base64Decode(audioBase64);
      _disposeAudio();
      _audioObjectUrl = html.Url.createObjectUrlFromBlob(
        html.Blob([audioBytes], 'audio/wav'),
      );
      final audio = html.AudioElement(_audioObjectUrl!);
      _audioElement = audio;

      audio.onEnded.listen((_) {
        if (!mounted) return;
        setState(() {
          _isSpeaking = false;
          _status = 'Audio playback complete.';
        });
        _disposeAudio();
      });

      audio.onError.listen((_) {
        if (!mounted) return;
        setState(() {
          _isSpeaking = false;
          _status = 'Audio playback failed. Please try again.';
        });
        _disposeAudio();
      });

      await audio.play();
      if (!mounted) return;
      setState(() {
        _status = 'Playing translated audio...';
      });
    } catch (error, stackTrace) {
      debugPrint('Anuwad audio error: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (!mounted) return;
      setState(() {
        _isSpeaking = false;
        _status = 'Could not play audio: $error';
      });
      _disposeAudio();
    }
  }

  Future<void> _stopSpeaking() async {
    _disposeAudio();
    if (!mounted) return;
    setState(() {
      _isSpeaking = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final sourceNative = hindiToKannada ? 'हिन्दी' : 'ಕನ್ನಡ';
    final sourceLanguage = hindiToKannada ? 'Hindi' : 'Kannada';
    final targetNative = hindiToKannada ? 'ಕನ್ನಡ' : 'हिन्दी';
    final targetLanguage = hindiToKannada ? 'Kannada' : 'Hindi';

    return Scaffold(
      backgroundColor: const Color(0xFFF7F8F6),
      appBar: AppBar(
        backgroundColor: const Color(0xFFE5EFEB),
        title: const Text(
          'Anuwad',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 12),
              const Text(
                'Your voice, across languages.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 23,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'Speak naturally. Understand each other.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.black54),
              ),
              const SizedBox(height: 32),
              Row(
                children: [
                  Expanded(child: _languageCard(sourceNative, sourceLanguage)),
                  IconButton(
                    onPressed: _swapLanguages,
                    tooltip: 'Swap languages',
                    icon: const Icon(Icons.swap_horiz, size: 30),
                  ),
                  Expanded(child: _languageCard(targetNative, targetLanguage)),
                ],
              ),
              const SizedBox(height: 28),
              FilledButton.icon(
                onPressed: _toggleListening,
                icon: Icon(_isListening ? Icons.stop : Icons.mic),
                label: Text(
                  _isListening ? 'Stop listening' : 'Tap to speak',
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: _isListening
                      ? Colors.red.shade700
                      : const Color(0xFF267A70),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  textStyle: const TextStyle(fontSize: 18),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                _status,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.black54),
              ),
              const SizedBox(height: 24),
              const Text(
                'Review your words',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _textController,
                minLines: 3,
                maxLines: 5,
                decoration: InputDecoration(
                  hintText: 'Your recognized speech will appear here...',
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Check names, numbers, and places before translating.',
                style: TextStyle(color: Colors.black54, fontSize: 12),
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: _isTranslating ? null : _translateText,
                icon: _isTranslating
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.translate),
                label: Text(
                  _isTranslating ? 'Translating...' : 'Translate',
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF267A70),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
              if (_translatedText.isNotEmpty) ...[
                const SizedBox(height: 28),
                Text(
                  'Translation · $targetLanguage',
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFE0E5E1)),
                  ),
                  child: SelectableText(
                    _translatedText,
                    style: const TextStyle(fontSize: 18),
                  ),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: _copyTranslation,
                    icon: const Icon(Icons.copy),
                    label: const Text('Copy translation'),
                  ),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _isSpeaking ? _stopSpeaking : _speakTranslation,
                  icon: Icon(
                    _isSpeaking ? Icons.stop : Icons.volume_up,
                  ),
                  label: Text(
                    _isSpeaking
                        ? 'Stop audio'
                        : 'Listen to translation',
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _languageCard(String nativeName, String languageName) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE0E5E1)),
      ),
      child: Column(
        children: [
          Text(
            nativeName,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            languageName,
            style: const TextStyle(color: Colors.black54),
          ),
        ],
      ),
    );
  }
}

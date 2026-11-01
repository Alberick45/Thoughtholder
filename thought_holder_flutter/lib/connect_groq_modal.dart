import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'settings_service.dart';
import 'app_theme.dart';

class ConnectGroqModal extends StatefulWidget {
  const ConnectGroqModal({Key? key}) : super(key: key);

  @override
  State<ConnectGroqModal> createState() => _ConnectGroqModalState();
}

class _ConnectGroqModalState extends State<ConnectGroqModal> {
  int _currentStep = 1; // 1 to 4
  final TextEditingController _keyController = TextEditingController();
  bool _isTesting = false;
  String? _statusMessage;
  bool _isSuccess = false;

  @override
  void dispose() {
    _keyController.dispose();
    super.dispose();
  }

  Future<void> _launchUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _saveAndTest(SettingsService settings) async {
    final rawKey = _keyController.text.trim();
    if (rawKey.isEmpty) return;

    if (!rawKey.startsWith('gsk_')) {
      setState(() {
        _isSuccess = false;
        _statusMessage =
            "That key doesn't start with gsk_. Check for extra spaces or make a new key.";
      });
      return;
    }

    setState(() {
      _isTesting = true;
      _statusMessage = null;
    });

    final success = await settings.testGroqKey(rawKey);
    if (!mounted) return;

    if (success) {
      await settings.setGroqApiKey(rawKey);
      setState(() {
        _isTesting = false;
        _isSuccess = true;
        _statusMessage = 'Key works. It stays on this device.';
      });
    } else {
      // Even if network ping timed out, check format and offer to save
      setState(() {
        _isTesting = false;
        _isSuccess = false;
        _statusMessage =
            "That key didn't work. Check for extra spaces or create a new key.";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsService>();
    final colors = AppColors.of(settings.theme);

    return Container(
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
        border: Border.all(color: colors.line, width: 2),
      ),
      padding: EdgeInsets.fromLTRB(
        20,
        20,
        20,
        MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Top Bar
            Row(
              children: [
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: Icon(Icons.close, color: colors.mute),
                  tooltip: 'Close',
                ),
                Expanded(
                  child: Text(
                    'Connect Groq for voice',
                    style: appFont(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: colors.text,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'The key powers voice transcription (and any AI suggestions). Typing works without it.',
              style: appFont(
                fontSize: 15,
                color: colors.mute,
              ),
            ),
            const SizedBox(height: 16),

            // 4-Step Progress Bar
            Row(
              children: List.generate(4, (index) {
                final stepNum = index + 1;
                final isActive = stepNum <= _currentStep;
                return Expanded(
                  child: Container(
                    height: 6,
                    margin: EdgeInsets.only(right: index < 3 ? 6 : 0),
                    decoration: BoxDecoration(
                      color: isActive ? colors.gold : colors.line,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                );
              }),
            ),
            const SizedBox(height: 16),

            // Step Content Box
            Container(
              decoration: BoxDecoration(
                color: colors.bg,
                border: Border.all(color: colors.line, width: 2),
                borderRadius: BorderRadius.circular(16),
              ),
              padding: const EdgeInsets.all(18),
              child: _buildStepBody(settings, colors),
            ),
            const SizedBox(height: 16),

            // Navigation Buttons (Back / Next / Skip)
            Row(
              children: [
                if (_currentStep > 1) ...[
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () {
                        setState(() {
                          _currentStep--;
                          _statusMessage = null;
                        });
                      },
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: colors.line, width: 2),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        'Back',
                        style: appFont(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: colors.text,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                ],
                if (_currentStep < 4) ...[
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        setState(() {
                          _currentStep++;
                          _statusMessage = null;
                        });
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: colors.gold,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        'Next',
                        style: appFont(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.black,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 10),
            Center(
              child: TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(
                  'Skip for now',
                  style: appFont(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: colors.gold,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStepBody(SettingsService settings, AppColors colors) {
    switch (_currentStep) {
      case 1:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Step 1 of 4',
              style: appFont(fontSize: 14, fontWeight: FontWeight.bold, color: colors.gold),
            ),
            const SizedBox(height: 6),
            Text(
              'Open Groq and sign up',
              style: appFont(fontSize: 19, fontWeight: FontWeight.bold, color: colors.text),
            ),
            const SizedBox(height: 8),
            Text(
              'Make a free account with email, Google or GitHub. A free tier is available and no credit card is needed to start.',
              style: appFont(fontSize: 16, color: colors.mute),
            ),
            const SizedBox(height: 14),
            ElevatedButton.icon(
              onPressed: () => _launchUrl('https://console.groq.com'),
              icon: const Icon(Icons.open_in_new, size: 20, color: Colors.black),
              label: Text(
                'Open Groq',
                style: appFont(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: colors.gold,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        );

      case 2:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Step 2 of 4',
              style: appFont(fontSize: 14, fontWeight: FontWeight.bold, color: colors.gold),
            ),
            const SizedBox(height: 6),
            Text(
              'Create an API key',
              style: appFont(fontSize: 19, fontWeight: FontWeight.bold, color: colors.text),
            ),
            const SizedBox(height: 8),
            Text(
              'Open the API Keys page, tap "Create API Key", and name it "ThoughtHolder".',
              style: appFont(fontSize: 16, color: colors.mute),
            ),
            const SizedBox(height: 14),
            ElevatedButton.icon(
              onPressed: () => _launchUrl('https://console.groq.com/keys'),
              icon: const Icon(Icons.vpn_key_outlined, size: 20, color: Colors.black),
              label: Text(
                'Open API Keys',
                style: appFont(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: colors.gold,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        );

      case 3:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Step 3 of 4',
              style: appFont(fontSize: 14, fontWeight: FontWeight.bold, color: colors.gold),
            ),
            const SizedBox(height: 6),
            Text(
              'Copy your key',
              style: appFont(fontSize: 19, fontWeight: FontWeight.bold, color: colors.text),
            ),
            const SizedBox(height: 8),
            Text(
              'It starts with gsk_. Groq shows it only once, so copy it before closing the box. Lost it? Delete it and create a new one.',
              style: appFont(fontSize: 16, color: colors.mute),
            ),
          ],
        );

      case 4:
      default:
        final hasKey = settings.hasGroqKey;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Step 4 of 4',
              style: appFont(fontSize: 14, fontWeight: FontWeight.bold, color: colors.gold),
            ),
            const SizedBox(height: 6),
            Text(
              'Paste it here',
              style: appFont(fontSize: 19, fontWeight: FontWeight.bold, color: colors.text),
            ),
            const SizedBox(height: 8),
            Text(
              'Your key stays on this device.',
              style: appFont(fontSize: 15, color: colors.mute),
            ),
            const SizedBox(height: 14),
            if (hasKey) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colors.card,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: colors.line),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle, color: Color(0xFF5FD282), size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Saved: ${settings.maskedGroqApiKey}',
                        style: appFont(fontSize: 15, color: colors.text),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () async {
                  await settings.removeGroqApiKey();
                  setState(() {
                    _statusMessage = null;
                  });
                },
                icon: const Icon(Icons.delete_outline, size: 18, color: Color(0xFFFF8A80)),
                label: Text(
                  'Remove key',
                  style: appFont(fontSize: 15, fontWeight: FontWeight.bold, color: const Color(0xFFFF8A80)),
                ),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Color(0xFFFF8A80)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ] else ...[
              TextField(
                controller: _keyController,
                obscureText: true,
                style: appFont(fontSize: 16, color: colors.text),
                decoration: InputDecoration(
                  hintText: 'gsk_...',
                  hintStyle: appFont(fontSize: 16, color: colors.mute),
                  filled: true,
                  fillColor: colors.card,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: colors.line, width: 2),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: colors.gold, width: 2),
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                ),
              ),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: _isTesting ? null : () => _saveAndTest(settings),
                style: ElevatedButton.styleFrom(
                  backgroundColor: colors.gold,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: _isTesting
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                      )
                    : Text(
                        'Save and test',
                        style: appFont(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black),
                      ),
              ),
            ],
            if (_statusMessage != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _isSuccess ? colors.goldBg : const Color(0x22FF8A80),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: _isSuccess ? colors.gold : colors.bad),
                ),
                child: Text(
                  _statusMessage!,
                  style: appFont(
                    fontSize: 14,
                    color: _isSuccess ? colors.gold : colors.bad,
                  ),
                ),
              ),
            ],
          ],
        );
    }
  }
}

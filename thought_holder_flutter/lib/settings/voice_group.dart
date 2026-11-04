import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../app_theme.dart';
import '../settings_service.dart';
import '../voice_transcription_service.dart';
import '../connect_groq_modal.dart';
import 'group_page_scaffold.dart';
import 'settings_state.dart';
import 'settings_widgets.dart';

class VoiceGroupScreen extends StatelessWidget {
  const VoiceGroupScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const GroupPageScaffold(
      title: 'Voice and AI',
      child: VoiceGroupContent(),
    );
  }
}

class VoiceGroupContent extends StatefulWidget {
  const VoiceGroupContent({super.key});

  @override
  State<VoiceGroupContent> createState() => _VoiceGroupContentState();
}

class _VoiceGroupContentState extends State<VoiceGroupContent> {
  static const String _groupId = 'voice_group';

  late TextEditingController _apiKeyController;
  late TextEditingController _promptController;
  bool _controllersInit = false;
  bool _editingKey = false;
  bool _testingGroq = false;
  String? _groqStatusText;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_controllersInit) {
      final settings = context.read<SettingsService>();
      _apiKeyController = TextEditingController(text: settings.groqApiKey);
      _promptController = TextEditingController(text: settings.whisperPrompt);
      _controllersInit = true;
    }
  }

  @override
  void dispose() {
    if (_controllersInit) {
      _apiKeyController.dispose();
      _promptController.dispose();
    }
    super.dispose();
  }

  Future<void> _testConnection(SettingsService settings) async {
    setState(() {
      _testingGroq = true;
      _groqStatusText = null;
    });
    final key = _apiKeyController.text.trim();
    await settings.setGroqApiKey(key);
    await settings.setWhisperPrompt(_promptController.text.trim());

    final reachable = await VoiceTranscriptionService().checkGroqReachability(key);

    if (mounted) {
      setState(() {
        _testingGroq = false;
        _groqStatusText = reachable
            ? '✓ Connected! Whisper Large V3 Turbo is online and ready.'
            : '✗ Failed to reach Groq. Check your internet connection & API key.';
      });
    }
  }

  String _formatMaskedKey(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return 'No key saved';
    if (trimmed.length <= 8) return '••••••••';
    final prefix = trimmed.substring(0, 4);
    final suffix = trimmed.substring(trimmed.length - 4);
    return '$prefix••••$suffix';
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsService>();
    final colors = AppColors.of(settings.theme);
    final isExpanded = SettingsState.isExpanded(_groupId);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 1. Set up Groq (4 steps) wizard button
        SizedBox(
          width: double.infinity,
          height: 48,
          child: ElevatedButton.icon(
            onPressed: () {
              showModalBottomSheet(
                context: context,
                isScrollControlled: true,
                backgroundColor: Colors.transparent,
                builder: (_) => const ConnectGroqModal(),
              );
            },
            icon: const Icon(Icons.key, size: 18),
            label: const Text('Set up Groq (4 steps)'),
            style: ElevatedButton.styleFrom(
              backgroundColor: colors.gold,
              foregroundColor: Colors.black,
              textStyle: appFont(fontWeight: FontWeight.bold, fontSize: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
        ),

        const SizedBox(height: 16),
        Divider(color: colors.line, height: 1),
        const SizedBox(height: 12),

        // 2. Use Whisper AI first switch
        SettingsSwitchRow(
          title: 'Use Whisper AI first',
          subtitle: 'Uses Groq Whisper Large V3 Turbo when online, with automatic offline fallback to device',
          value: settings.useWhisperAsPrimary,
          onChanged: (val) async {
            await settings.setUseWhisperAsPrimary(val);
            if (mounted) setState(() {});
          },
          colors: colors,
        ),

        const SizedBox(height: 16),
        Divider(color: colors.line, height: 1),
        const SizedBox(height: 16),

        // 3. Groq key (masked display with Edit key button)
        Text(
          'Groq API key',
          style: appFont(
            color: colors.text,
            fontWeight: FontWeight.bold,
            fontSize: 14,
          ),
        ),
        const SizedBox(height: 8),

        if (!_editingKey)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: colors.bg,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: colors.line),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _formatMaskedKey(settings.groqApiKey),
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 14,
                      letterSpacing: 1.2,
                    ),
                  ),
                ),
                SizedBox(
                  height: 36,
                  child: OutlinedButton(
                    onPressed: () {
                      setState(() {
                        _editingKey = true;
                      });
                    },
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: colors.gold),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: Text(
                      'Edit key',
                      style: appFont(
                        color: colors.gold,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
                if (settings.hasGroqKey) ...[
                  const SizedBox(width: 8),
                  SizedBox(
                    height: 36,
                    child: OutlinedButton(
                      onPressed: () async {
                        await settings.removeGroqApiKey();
                        _apiKeyController.clear();
                        setState(() {
                          _groqStatusText = null;
                        });
                      },
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Color(0xFFFF8A80)),
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: Text(
                        'Remove key',
                        style: appFont(
                          color: const Color(0xFFFF8A80),
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          )
        else
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _apiKeyController,
                  obscureText: true,
                  style: appFont(color: colors.text, fontSize: 13),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: 'gsk_...',
                    hintStyle: appFont(color: colors.mute),
                    filled: true,
                    fillColor: colors.bg,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: colors.line),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: colors.gold, width: 1.5),
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                  onChanged: (val) => settings.setGroqApiKey(val),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                height: 38,
                child: ElevatedButton(
                  onPressed: () {
                    settings.setGroqApiKey(_apiKeyController.text.trim());
                    setState(() {
                      _editingKey = false;
                    });
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: colors.gold,
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: const Text('Save'),
                ),
              ),
            ],
          ),

        if (settings.hasGroqKey) ...[
          const SizedBox(height: 6),
          Row(
            children: [
              Icon(
                settings.isGroqKeyInSecureStorage ? Icons.lock : Icons.lock_open,
                size: 13,
                color: settings.isGroqKeyInSecureStorage ? const Color(0xFF5FD282) : colors.bad,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  settings.isGroqKeyInSecureStorage
                      ? 'Stored securely in OS Credential Vault.'
                      : 'Not yet in OS secure storage.',
                  style: appFont(
                    color: settings.isGroqKeyInSecureStorage ? colors.mute : colors.bad,
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          ),
          if (settings.hasLegacyGroqKeyInSettings) ...[
            const SizedBox(height: 4),
            Text(
              'A legacy copy exists in plain settings until you confirm its removal.',
              style: appFont(color: const Color(0xFFFFD54F), fontSize: 11),
            ),
          ],
        ],

        const SizedBox(height: 16),

        // 4. Test connection button
        Row(
          children: [
            SizedBox(
              height: 48,
              child: ElevatedButton.icon(
                onPressed: _testingGroq ? null : () => _testConnection(settings),
                icon: _testingGroq
                    ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                    : const Icon(Icons.wifi_tethering, size: 16),
                label: Text(_testingGroq ? 'Checking…' : 'Test connection'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: colors.gold,
                  foregroundColor: Colors.black,
                  textStyle: appFont(fontWeight: FontWeight.bold, fontSize: 13),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            if (_groqStatusText != null)
              Expanded(
                child: Text(
                  _groqStatusText!,
                  style: appFont(
                    color: _groqStatusText!.startsWith('✓') ? colors.done : colors.bad,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
          ],
        ),

        // 5. Collapsible "Names and terms" (Prompt Priming)
        if (isExpanded) ...[
          const SizedBox(height: 20),
          Divider(color: colors.line, height: 1),
          const SizedBox(height: 16),
          Text(
            'Names and terms',
            style: appFont(
              color: colors.text,
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Primes Whisper so it accurately spells names like Albert, local towns, and technical jargon.',
            style: appFont(color: colors.mute, fontSize: 12),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _promptController,
            style: appFont(color: colors.text, fontSize: 13),
            decoration: InputDecoration(
              isDense: true,
              hintText: 'e.g. Albert, PK, Aaenics, Ghana...',
              hintStyle: appFont(color: colors.mute),
              filled: true,
              fillColor: colors.bg,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: colors.line),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: colors.gold, width: 1.5),
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
            onChanged: (val) => settings.setWhisperPrompt(val),
          ),
        ],

        const SizedBox(height: 12),
        ShowMoreButton(
          count: 1,
          isExpanded: isExpanded,
          onTap: () {
            setState(() {
              SettingsState.toggleExpanded(_groupId);
            });
          },
          colors: colors,
        ),
      ],
    );
  }
}

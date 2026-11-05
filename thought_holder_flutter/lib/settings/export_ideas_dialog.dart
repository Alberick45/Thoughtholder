import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../app_theme.dart';
import '../services/thought_bundle_service.dart';
import '../settings_service.dart';
import '../utils/app_logger.dart';
import '../widgets/keyboard_safe_sheet.dart';

/// Modal dialog for configuring and executing an export to `.thoughtbundle`.
class ExportIdeasDialog extends StatefulWidget {
  const ExportIdeasDialog({super.key});

  @override
  State<ExportIdeasDialog> createState() => _ExportIdeasDialogState();
}

class _ExportIdeasDialogState extends State<ExportIdeasDialog> {
  bool _protectWithPassphrase = false;
  bool _obscurePassphrase = true;
  final TextEditingController _passphraseController = TextEditingController();
  final TextEditingController _confirmController = TextEditingController();
  bool _isExporting = false;
  String? _errorMessage;

  @override
  void dispose() {
    _passphraseController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _handleExport(AppColors colors) async {
    setState(() {
      _errorMessage = null;
    });

    String? passphrase;
    if (_protectWithPassphrase) {
      final p1 = _passphraseController.text;
      final p2 = _confirmController.text;
      if (p1.trim().isEmpty) {
        setState(() {
          _errorMessage = 'Please enter a passphrase or uncheck protection.';
        });
        return;
      }
      if (p1 != p2) {
        setState(() {
          _errorMessage = 'Passphrases do not match. Please verify.';
        });
        return;
      }
      passphrase = p1.trim();
    }

    setState(() {
      _isExporting = true;
    });

    try {
      final result = await ThoughtBundleService.instance.exportToFile(
        passphrase: passphrase,
      );

      if (!mounted) return;
      Navigator.of(context).pop(); // Close export setup dialog

      // Show result dialog with exact required phrasing and Share action
      _showResultDialog(context, result, colors);
    } catch (e, stack) {
      AppLogger.error('ExportIdeasDialog', 'Export failed: $e\n$stack');
      if (mounted) {
        setState(() {
          _isExporting = false;
          _errorMessage = 'Export failed: $e';
        });
      }
    }
  }

  void _showResultDialog(BuildContext context, ExportResult result, AppColors colors) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: colors.bg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: colors.line),
        ),
        title: Row(
          children: [
            Icon(Icons.check_circle_outline, color: colors.ok, size: 24),
            const SizedBox(width: 10),
            Text(
              'Export complete',
              style: appFont(color: colors.text, fontWeight: FontWeight.bold, fontSize: 18),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Exact requirement: "Saved N ideas and M buckets to <folder>"
            Text(
              'Saved ${result.ideasCount} ideas and ${result.bucketsCount} buckets to ${result.folderPath}',
              style: appFont(color: colors.text, fontSize: 14, height: 1.4),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: colors.card,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: colors.line),
              ),
              child: Row(
                children: [
                  Icon(Icons.description_outlined, color: colors.gold, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      p.basename(result.file.path),
                      style: appFont(color: colors.mute, fontSize: 12),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            if (result.isEncrypted) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.lock_outline, color: colors.gold, size: 14),
                  const SizedBox(width: 6),
                  Text(
                    'Protected with passphrase',
                    style: appFont(color: colors.gold, fontSize: 12),
                  ),
                ],
              ),
            ],
          ],
        ),
        actions: [
          // Share button
          OutlinedButton.icon(
            onPressed: () async {
              try {
                await Share.shareXFiles(
                  [XFile(result.file.path)],
                  text: 'My ThoughtHolder ideas bundle',
                );
              } catch (_) {
                // If platform share sheet fails or on Windows without native share target:
                if (!Platform.isAndroid && !Platform.isIOS && Platform.isWindows) {
                  try {
                    await Process.run('explorer.exe', ['/select,', result.file.path]);
                  } catch (_) {}
                }
              }
              if (ctx.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    backgroundColor: colors.card,
                    content: Text(
                      'Exported file: ${result.file.path}',
                      style: appFont(color: colors.text, fontSize: 13),
                    ),
                    duration: const Duration(seconds: 3),
                  ),
                );
              }
            },
            icon: Icon(Icons.share_outlined, size: 18, color: colors.gold),
            label: Text(
              'Share',
              style: appFont(color: colors.gold, fontWeight: FontWeight.bold),
            ),
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: colors.gold),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(),
            style: ElevatedButton.styleFrom(
              backgroundColor: colors.gold,
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    AppColors colors;
    try {
      final settings = context.watch<SettingsService>();
      colors = AppColors.of(settings.theme);
    } catch (_) {
      colors = AppColors.dark;
    }

    return KeyboardSafeSheet(
      isDialog: true,
      maxWidth: 500,
      backgroundColor: colors.bg,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: colors.line),
      header: Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(
          children: [
            Icon(Icons.file_upload_outlined, color: colors.gold, size: 24),
            const SizedBox(width: 10),
            Text(
              'Export my ideas',
              style: appFont(color: colors.text, fontWeight: FontWeight.bold, fontSize: 18),
            ),
          ],
        ),
      ),
      pinnedFooter: Padding(
        padding: const EdgeInsets.only(top: 14),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              onPressed: _isExporting ? null : () => Navigator.of(context).pop(),
              child: Text('Cancel', style: appFont(color: colors.mute)),
            ),
            const SizedBox(width: 8),
            ElevatedButton(
              onPressed: _isExporting ? null : () => _handleExport(colors),
              style: ElevatedButton.styleFrom(
                backgroundColor: colors.gold,
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: _isExporting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                    )
                  : const Text('Export'),
            ),
          ],
        ),
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Save all ideas and buckets to a portable .thoughtbundle file for backup or transferring to another device.',
              style: appFont(color: colors.mute, fontSize: 13, height: 1.4),
            ),
            const SizedBox(height: 16),

            // Optional Passphrase protection toggle
            Container(
              decoration: BoxDecoration(
                color: colors.card,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: colors.line),
              ),
              child: SwitchListTile(
                value: _protectWithPassphrase,
                onChanged: _isExporting
                    ? null
                    : (val) {
                        setState(() {
                          _protectWithPassphrase = val;
                          _errorMessage = null;
                        });
                      },
                title: Text(
                  'Protect with a passphrase',
                  style: appFont(color: colors.text, fontWeight: FontWeight.w600, fontSize: 14),
                ),
                activeThumbColor: colors.gold,
              ),
            ),

            const SizedBox(height: 12),

            // Message when NOT protected
            if (!_protectWithPassphrase) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colors.card,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: colors.line),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: colors.mute, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'This file contains your ideas in readable form.',
                        style: appFont(color: colors.mute, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            // Message & Inputs when PROTECTED
            if (_protectWithPassphrase) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colors.bad.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: colors.bad.withValues(alpha: 0.4)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.warning_amber_rounded, color: colors.bad, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'If you forget it, the file cannot be opened.',
                        style: appFont(color: colors.bad, fontSize: 13, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _passphraseController,
                obscureText: _obscurePassphrase,
                enabled: !_isExporting,
                style: appFont(color: colors.text, fontSize: 14),
                decoration: InputDecoration(
                  labelText: 'Passphrase',
                  labelStyle: TextStyle(color: colors.mute),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscurePassphrase ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                      color: colors.mute,
                      size: 20,
                    ),
                    onPressed: () {
                      setState(() {
                        _obscurePassphrase = !_obscurePassphrase;
                      });
                    },
                  ),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _confirmController,
                obscureText: _obscurePassphrase,
                enabled: !_isExporting,
                style: appFont(color: colors.text, fontSize: 14),
                decoration: InputDecoration(
                  labelText: 'Confirm passphrase',
                  labelStyle: TextStyle(color: colors.mute),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ],

            if (_errorMessage != null) ...[
              const SizedBox(height: 12),
              Text(
                _errorMessage!,
                style: appFont(color: colors.bad, fontSize: 12),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

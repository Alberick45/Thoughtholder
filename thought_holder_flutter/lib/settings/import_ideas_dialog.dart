import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import '../app_theme.dart';
import '../services/thought_bundle_service.dart';
import '../settings_service.dart';
import '../utils/app_logger.dart';
import '../widgets/keyboard_safe_sheet.dart';

/// Helper to launch file picking and import process from Settings.
class ImportIdeasFlow {
  /// Opens file picker for `.thoughtbundle` files, previews analysis, and prompts confirmation.
  static Future<void> startImport(
    BuildContext context, {
    VoidCallback? onImportCompleted,
  }) async {
    AppColors colors;
    try {
      final settings = context.read<SettingsService>();
      colors = AppColors.of(settings.theme);
    } catch (_) {
      colors = AppColors.dark;
    }

    try {
      final pickerResult = await FilePicker.pickFiles(
        dialogTitle: 'Select .thoughtbundle file to import',
        type: FileType.custom,
        allowedExtensions: ['thoughtbundle'],
      );

      if (pickerResult == null || pickerResult.files.isEmpty) {
        return; // User cancelled file selection
      }

      final rawPath = pickerResult.files.single.path;
      if (rawPath == null || rawPath.isEmpty) {
        if (context.mounted) {
          _showErrorDialog(context, 'Unable to access the selected file.', colors);
        }
        return;
      }

      final file = File(rawPath);
      if (!await file.exists()) {
        if (context.mounted) {
          _showErrorDialog(context, 'The selected file does not exist on disk.', colors);
        }
        return;
      }

      // Untrusted validation 1: File size cap (50 MB)
      final size = await file.length();
      if (size > ThoughtBundleService.maxBundleFileSize) {
        if (context.mounted) {
          _showErrorDialog(context, 'File too large (exceeds 50 MB limit).', colors);
        }
        return;
      }

      // Check if file is encrypted by inspecting header JSON
      bool isEncrypted = false;
      try {
        final headChunk = await file.openRead(0, 4096).transform(utf8.decoder).first;
        if (headChunk.contains('"is_encrypted": true') || headChunk.contains('"is_encrypted":true')) {
          isEncrypted = true;
        }
      } catch (_) {}

      String? passphrase;
      if (isEncrypted) {
        if (!context.mounted) return;
        passphrase = await _promptPassphrase(context, colors);
        if (passphrase == null) {
          return; // User cancelled passphrase prompt
        }
      }

      // Analyze import preview without writing to the database
      if (!context.mounted) return;
      _showLoadingDialog(context, 'Analyzing bundle...', colors);

      ImportAnalysis analysis;
      try {
        analysis = await ThoughtBundleService.instance.previewImport(
          file: file,
          passphrase: passphrase,
        );
      } catch (e) {
        if (context.mounted) {
          Navigator.of(context, rootNavigator: true).pop(); // dismiss loading
        }
        final message = e is FormatException ? e.message : e.toString().replaceFirst('Exception: ', '');
        if (context.mounted) {
          _showErrorDialog(context, message, colors);
        }
        return;
      }

      if (context.mounted) {
        Navigator.of(context, rootNavigator: true).pop(); // dismiss loading
      }

      // Display preview modal with exact counts and Confirm / Cancel buttons
      if (!context.mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => ImportPreviewDialog(
          file: file,
          analysis: analysis,
          colors: colors,
        ),
      );

      if (confirmed != true) {
        return; // User cancelled import
      }

      // Confirmed: Apply in one single transaction with automatic verified backup
      if (!context.mounted) return;
      _showLoadingDialog(context, 'Applying import and creating verified safety backup...', colors);

      ImportApplyResult result;
      try {
        result = await ThoughtBundleService.instance.applyImport(analysis: analysis);
      } catch (e) {
        if (context.mounted) {
          Navigator.of(context, rootNavigator: true).pop(); // dismiss loading
          _showErrorDialog(context, 'Import failed: $e. Your database was not modified.', colors);
        }
        return;
      }

      if (context.mounted) {
        Navigator.of(context, rootNavigator: true).pop(); // dismiss loading
      }

      onImportCompleted?.call();

      if (context.mounted) {
        _showSuccessDialog(context, result, colors);
      }
    } catch (e, stack) {
      AppLogger.error('ImportIdeasFlow', 'Error during import: $e\n$stack');
      if (context.mounted) {
        _showErrorDialog(context, 'An unexpected error occurred during import: $e', colors);
      }
    }
  }

  static Future<String?> _promptPassphrase(BuildContext context, AppColors colors) async {
    final controller = TextEditingController();
    bool obscure = true;

    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => KeyboardSafeSheet(
          isDialog: true,
          maxWidth: 480,
          backgroundColor: colors.bg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: colors.line),
          header: Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              children: [
                Icon(Icons.lock_outline, color: colors.gold, size: 22),
                const SizedBox(width: 10),
                Text(
                  'Passphrase Protected',
                  style: appFont(color: colors.text, fontWeight: FontWeight.bold, fontSize: 17),
                ),
              ],
            ),
          ),
          pinnedFooter: Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(null),
                  child: Text('Cancel', style: appFont(color: colors.mute)),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: colors.gold,
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: const Text('Unlock'),
                ),
              ],
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'This .thoughtbundle file is encrypted. Enter the passphrase to unlock it.',
                style: appFont(color: colors.text, fontSize: 13, height: 1.4),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: controller,
                obscureText: obscure,
                autofocus: true,
                style: appFont(color: colors.text),
                decoration: InputDecoration(
                  labelText: 'Passphrase',
                  labelStyle: appFont(color: colors.mute),
                  enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: colors.line),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: colors.gold),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  suffixIcon: IconButton(
                    icon: Icon(
                      obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                      color: colors.mute,
                    ),
                    onPressed: () => setDialogState(() => obscure = !obscure),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static void _showLoadingDialog(BuildContext context, String message, AppColors colors) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: colors.bg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: colors.line),
        ),
        content: Row(
          children: [
            CircularProgressIndicator(color: colors.gold),
            const SizedBox(width: 20),
            Expanded(
              child: Text(
                message,
                style: appFont(color: colors.text, fontSize: 14),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static void _showErrorDialog(BuildContext context, String message, AppColors colors) {
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
            Icon(Icons.error_outline, color: colors.bad, size: 22),
            const SizedBox(width: 10),
            Text(
              'Cannot import file',
              style: appFont(color: colors.text, fontWeight: FontWeight.bold, fontSize: 17),
            ),
          ],
        ),
        content: Text(
          message,
          style: appFont(color: colors.text, fontSize: 14, height: 1.4),
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(),
            style: ElevatedButton.styleFrom(
              backgroundColor: colors.card,
              foregroundColor: colors.text,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  static void _showSuccessDialog(BuildContext context, ImportApplyResult result, AppColors colors) {
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
              'Import complete',
              style: appFont(color: colors.text, fontWeight: FontWeight.bold, fontSize: 18),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Your ideas have been successfully imported:',
              style: appFont(color: colors.text, fontSize: 14),
            ),
            const SizedBox(height: 12),
            _buildStatLine(Icons.add_circle_outline, '${result.insertedIdeasCount} new ideas added', colors.ok, colors),
            _buildStatLine(Icons.update_outlined, '${result.updatedIdeasCount} existing ideas updated', colors.gold, colors),
            if (result.conflictCopiesCount > 0)
              _buildStatLine(Icons.call_split_outlined, '${result.conflictCopiesCount} conflict copies created in Unsorted', colors.bad, colors),
            if (result.addedBucketsCount > 0)
              _buildStatLine(Icons.folder_outlined, '${result.addedBucketsCount} new buckets added', colors.gold, colors),
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
                  Icon(Icons.shield_outlined, color: colors.ok, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'A safety backup was saved. You can undo this import at any time within 7 days from Settings.',
                      style: appFont(color: colors.mute, fontSize: 12, height: 1.3),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(),
            style: ElevatedButton.styleFrom(
              backgroundColor: colors.gold,
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  static Widget _buildStatLine(IconData icon, String text, Color iconColor, AppColors colors) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 18, color: iconColor),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: appFont(color: colors.text, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

/// Dialog displaying exact analysis numbers before import is confirmed.
class ImportPreviewDialog extends StatelessWidget {
  final File file;
  final ImportAnalysis analysis;
  final AppColors colors;

  const ImportPreviewDialog({
    super.key,
    required this.file,
    required this.analysis,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: colors.bg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colors.line),
      ),
      title: Row(
        children: [
          Icon(Icons.file_download_outlined, color: colors.gold, size: 24),
          const SizedBox(width: 10),
          Text(
            'Import preview',
            style: appFont(color: colors.text, fontWeight: FontWeight.bold, fontSize: 18),
          ),
        ],
      ),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'File: ${p.basename(file.path)}',
                style: appFont(color: colors.mute, fontSize: 13),
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Text(
                'Contains ${analysis.totalIncomingIdeas} ideas and ${analysis.totalIncomingBuckets} buckets.',
                style: appFont(color: colors.text, fontWeight: FontWeight.w600, fontSize: 14),
              ),
              const SizedBox(height: 16),
              Divider(color: colors.line, height: 1),
              const SizedBox(height: 12),
              Text(
                'Changes that will be made:',
                style: appFont(color: colors.text, fontWeight: FontWeight.bold, fontSize: 13),
              ),
              const SizedBox(height: 8),

              // Exact counts
              _buildCountRow(
                icon: Icons.add_circle_outline,
                iconColor: colors.ok,
                label: 'New ideas to add',
                count: analysis.newIdeasCount,
              ),
              _buildCountRow(
                icon: Icons.update_outlined,
                iconColor: colors.gold,
                label: 'Ideas with newer edits to update',
                count: analysis.newerEditsCount,
              ),
              _buildCountRow(
                icon: Icons.check_circle_outline,
                iconColor: colors.mute,
                label: 'Already up to date (no change)',
                count: analysis.upToDateCount,
              ),
              _buildCountRow(
                icon: Icons.call_split_outlined,
                iconColor: analysis.conflictsCount > 0 ? colors.bad : colors.mute,
                label: 'Conflicts (creates copy in Unsorted)',
                count: analysis.conflictsCount,
              ),
              if (analysis.statusChangesCount > 0)
                _buildCountRow(
                  icon: Icons.swap_horiz_outlined,
                  iconColor: colors.gold,
                  label: 'Status changes (done/trash)',
                  count: analysis.statusChangesCount,
                ),
              _buildCountRow(
                icon: Icons.create_new_folder_outlined,
                iconColor: colors.gold,
                label: 'New buckets to add',
                count: analysis.bucketsToAddCount,
              ),
              _buildCountRow(
                icon: Icons.folder_shared_outlined,
                iconColor: colors.mute,
                label: 'Buckets matched by name',
                count: analysis.bucketsMatchedByNameCount,
              ),

              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: colors.card,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: colors.line),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: colors.gold, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'A verified safety backup will be taken before importing. Nothing is written until you confirm.',
                        style: appFont(color: colors.mute, fontSize: 12, height: 1.3),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        // Buttons: "Confirm import" and "Cancel"
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text('Cancel', style: appFont(color: colors.mute)),
        ),
        ElevatedButton(
          onPressed: () => Navigator.of(context).pop(true),
          style: ElevatedButton.styleFrom(
            backgroundColor: colors.gold,
            foregroundColor: Colors.black,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          ),
          child: const Text('Confirm import'),
        ),
      ],
    );
  }

  Widget _buildCountRow({
    required IconData icon,
    required Color iconColor,
    required String label,
    required int count,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 18, color: iconColor),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: appFont(color: colors.text, fontSize: 13),
            ),
          ),
          Text(
            '$count',
            style: appFont(
              color: count > 0 ? colors.text : colors.mute,
              fontWeight: FontWeight.bold,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}

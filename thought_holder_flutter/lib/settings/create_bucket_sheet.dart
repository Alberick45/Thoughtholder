import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../app_theme.dart';
import '../settings_service.dart';
import '../sound_service.dart';
import '../thought_provider.dart';

/// Opens the name and icon sheet/dialog to create a new custom bucket.
Future<String?> showCreateBucketSheet(
  BuildContext context,
  ThoughtProvider provider,
  AppColors colors, {
  VoidCallback? onCreated,
}) async {
  final isDesktop = (!kIsWeb &&
          (Platform.isWindows || Platform.isMacOS || Platform.isLinux)) ||
      MediaQuery.of(context).size.width >= 600;

  if (isDesktop) {
    return showDialog<String>(
      context: context,
      builder: (dialogCtx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 480),
          decoration: BoxDecoration(
            color: colors.card,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
                color: colors.gold.withValues(alpha: 0.5), width: 1.5),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.35),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: CreateBucketSheetContent(
            provider: provider,
            colors: colors,
            isDialog: true,
            onCreated: onCreated,
          ),
        ),
      ),
    );
  } else {
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(sheetCtx).size.height * 0.88,
        ),
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(sheetCtx).viewInsets.bottom,
        ),
        decoration: BoxDecoration(
          color: colors.card,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          border: Border.all(color: colors.line),
        ),
        child: CreateBucketSheetContent(
          provider: provider,
          colors: colors,
          isDialog: false,
          onCreated: onCreated,
        ),
      ),
    );
  }
}

class CreateBucketSheetContent extends StatefulWidget {
  final ThoughtProvider provider;
  final AppColors colors;
  final bool isDialog;
  final VoidCallback? onCreated;

  const CreateBucketSheetContent({
    super.key,
    required this.provider,
    required this.colors,
    this.isDialog = false,
    this.onCreated,
  });

  @override
  State<CreateBucketSheetContent> createState() =>
      _CreateBucketSheetContentState();
}

class _CreateBucketSheetContentState extends State<CreateBucketSheetContent> {
  final _nameController = TextEditingController();
  String _selectedIcon = 'folder';
  String? _errorMessage;
  bool _isSaving = false;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() {
        _errorMessage = 'Please enter a bucket name.';
      });
      return;
    }

    final alreadyExists = widget.provider.buckets.any((b) =>
        (b['name'] as String).trim().toLowerCase() == name.toLowerCase());
    if (alreadyExists) {
      setState(() {
        _errorMessage = 'A bucket named "$name" already exists.';
      });
      return;
    }

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    try {
      final canonical =
          await widget.provider.addBucket(name, icon: _selectedIcon);
      if (mounted) {
        final settings = context.read<SettingsService>();
        SoundService.instance.play(SoundEvent.save, settings: settings);

        Navigator.of(context).pop(canonical);
        widget.onCreated?.call();

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Created bucket "$canonical"',
              style: appFont(color: Colors.white),
            ),
            backgroundColor: const Color(0xFF2C2C2C),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSaving = false;
          _errorMessage = 'Could not create bucket. Please try again.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = widget.colors;

    return SingleChildScrollView(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: widget.isDialog ? 20 : 32,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: colors.goldBg,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  kBucketIcons[_selectedIcon] ?? Icons.folder_outlined,
                  color: colors.gold,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Make a new bucket',
                  style: appFont(
                    color: colors.text,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              IconButton(
                icon: Icon(Icons.close, color: colors.mute, size: 20),
                onPressed: () => Navigator.of(context).pop(),
                splashRadius: 20,
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Name text field
          TextField(
            controller: _nameController,
            autofocus: true,
            style: appFont(color: colors.text, fontSize: 16),
            onChanged: (val) {
              if (_errorMessage != null) {
                setState(() => _errorMessage = null);
              }
            },
            onSubmitted: (_) => _submit(),
            decoration: InputDecoration(
              labelText: 'Bucket name',
              labelStyle: appFont(color: colors.mute, fontSize: 14),
              hintText: 'e.g. Work, Finance, Ideas',
              hintStyle: appFont(
                  color: colors.mute.withValues(alpha: 0.6), fontSize: 14),
              filled: true,
              fillColor: colors.bg,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: colors.line),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: colors.line),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: colors.gold, width: 2),
              ),
              suffixIcon: _nameController.text.isNotEmpty
                  ? IconButton(
                      icon: Icon(Icons.clear, color: colors.mute, size: 18),
                      onPressed: () {
                        _nameController.clear();
                        setState(() {});
                      },
                    )
                  : null,
            ),
          ),
          if (_errorMessage != null) ...[
            const SizedBox(height: 8),
            Text(
              _errorMessage!,
              style: appFont(color: Colors.redAccent, fontSize: 13),
            ),
          ],
          const SizedBox(height: 20),

          // Choose an icon
          Text(
            'Choose an icon',
            style: appFont(
              color: colors.mute,
              fontSize: 13,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 10),

          // 12 Icons Selector Grid
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: kBucketIcons.entries.map((entry) {
              final isSelected = _selectedIcon == entry.key;
              return Tooltip(
                message: entry.key,
                child: InkWell(
                  onTap: () {
                    setState(() => _selectedIcon = entry.key);
                  },
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: isSelected ? colors.goldBg : colors.bg,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isSelected ? colors.gold : colors.line,
                        width: isSelected ? 2.0 : 1.0,
                      ),
                    ),
                    child: Icon(
                      entry.value,
                      size: 22,
                      color: isSelected ? colors.gold : colors.mute,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 24),

          // Buttons
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
                style: TextButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
                child: Text(
                  'Cancel',
                  style: appFont(color: colors.mute, fontSize: 14),
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                height: 48,
                child: ElevatedButton.icon(
                  onPressed: _isSaving ? null : _submit,
                  icon: _isSaving
                      ? SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation(colors.text),
                          ),
                        )
                      : const Icon(Icons.check, size: 18),
                  label: Text(
                    _isSaving ? 'Creating...' : 'Make bucket',
                    style: appFont(
                      color: Colors.black,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: colors.gold,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

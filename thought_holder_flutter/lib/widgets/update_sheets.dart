import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../background_recording_service.dart';
import '../config/update_config.dart';
import '../services/app_update_service.dart';
import '../settings_service.dart';
import '../thought_provider.dart';

class UpdateAvailableSheet extends StatelessWidget {
  final VersionManifest manifest;
  final String installedVersion;
  final bool isRequired;
  final VoidCallback onStartUpdate;

  const UpdateAvailableSheet({
    super.key,
    required this.manifest,
    required this.installedVersion,
    required this.isRequired,
    required this.onStartUpdate,
  });

  @override
  Widget build(BuildContext context) {
    final settings = Provider.of<SettingsService>(context, listen: false);

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF1E1E22),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Download icon tile + Title + Subtitle
            Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE5A93C).withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    Icons.cloud_download_outlined,
                    color: Color(0xFFE5A93C),
                    size: 28,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isRequired ? 'Update required' : 'Update available',
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Version ${manifest.version} · you have $installedVersion',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey.shade400,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // WHAT'S NEW heading
            const Text(
              "WHAT'S NEW",
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2,
                color: Color(0xFFE5A93C),
              ),
            ),
            const SizedBox(height: 12),

            // Notes list with green ticks
            if (manifest.notes.isEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.check_circle_rounded, color: Color(0xFF4CAF50), size: 18),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'General bug fixes, performance improvements, and polish.',
                        style: TextStyle(fontSize: 14, color: Colors.grey.shade300, height: 1.3),
                      ),
                    ),
                  ],
                ),
              )
            else
              ...manifest.notes.map((note) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Padding(
                          padding: EdgeInsets.only(top: 2),
                          child: Icon(Icons.check_circle_rounded, color: Color(0xFF4CAF50), size: 18),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            note,
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey.shade300,
                              height: 1.3,
                            ),
                          ),
                        ),
                      ],
                    ),
                  )),

            const SizedBox(height: 12),

            // Safety notice
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Icon(Icons.shield_outlined, size: 16, color: Colors.grey.shade400),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    "Your thoughts and voice notes are backed up before the update starts.",
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade400,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Action Buttons
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: onStartUpdate,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFE5A93C),
                  foregroundColor: Colors.black,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: const Text(
                  'Update now',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),

            if (isRequired)
              SizedBox(
                width: double.infinity,
                height: 52,
                child: OutlinedButton(
                  onPressed: () {
                    final provider = Provider.of<ThoughtProvider>(context, listen: false);
                    provider.exportAllThoughtsAsJson();
                  },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white24),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: const Text(
                    'Export data before updating',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                ),
              )
            else
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 52,
                      child: TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.grey.shade300,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: const Text(
                          'Later',
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: SizedBox(
                      height: 52,
                      child: TextButton(
                        onPressed: () async {
                          await settings.setSkippedBuild(manifest.build);
                          if (context.mounted) Navigator.of(context).pop();
                        },
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.grey.shade400,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: const Text(
                          'Skip this version',
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class UpdatingModal extends StatelessWidget {
  final VersionManifest manifest;
  final VoidCallback onRetry;
  final VoidCallback onCancel;

  const UpdatingModal({
    super.key,
    required this.manifest,
    required this.onRetry,
    required this.onCancel,
  });

  Widget _buildStepRow({
    required String title,
    required String? subtitle,
    required bool isDone,
    required bool isActive,
    required bool isFailed,
  }) {
    Color iconColor;
    IconData icon;

    if (isFailed) {
      icon = Icons.error_outline;
      iconColor = const Color(0xFFEF5350);
    } else if (isDone) {
      icon = Icons.check_circle_rounded;
      iconColor = const Color(0xFF4CAF50);
    } else if (isActive) {
      icon = Icons.radio_button_checked;
      iconColor = const Color(0xFFE5A93C);
    } else {
      icon = Icons.radio_button_unchecked;
      iconColor = Colors.white24;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(icon, color: iconColor, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: isActive || isDone ? FontWeight.w600 : FontWeight.normal,
                    color: isActive || isDone ? Colors.white : Colors.white38,
                  ),
                ),
                if (subtitle != null && subtitle.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 13,
                      color: isFailed ? const Color(0xFFEF5350) : Colors.grey.shade400,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final updateService = Provider.of<AppUpdateService>(context);
    final progress = updateService.progress;

    final isWaiting = progress.stage == UpdateStage.waitingForVoiceCapture;
    final isBackingUp = progress.stage == UpdateStage.backingUp;
    final isDownloading = progress.stage == UpdateStage.downloading;
    final isVerifying = progress.stage == UpdateStage.verifying;
    final isInstalling = progress.stage == UpdateStage.readyToInstall || progress.stage == UpdateStage.installing;
    final isFailed = progress.stage == UpdateStage.failed;

    final backupDone = isDownloading || isVerifying || isInstalling;
    final downloadDone = isVerifying || isInstalling;
    final verifyDone = isInstalling;

    return PopScope(
      canPop: isFailed,
      child: Container(
        decoration: const BoxDecoration(
          color: Color(0xFF1E1E22),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Updating to ${manifest.version}',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Keep the app open. This takes about a minute.',
                style: TextStyle(fontSize: 14, color: Colors.grey.shade400),
              ),
              const SizedBox(height: 20),

              // Step 1: Backup
              _buildStepRow(
                title: 'Backup',
                subtitle: progress.backupSummary ?? (isBackingUp ? 'Saving database snapshot…' : null),
                isDone: backupDone,
                isActive: isBackingUp || isWaiting,
                isFailed: isFailed && progress.statusMessage.contains('Backup'),
              ),

              // Step 2: Downloading
              _buildStepRow(
                title: 'Downloading',
                subtitle: isDownloading ? progress.formattedDownloadStats : null,
                isDone: downloadDone,
                isActive: isDownloading,
                isFailed: isFailed && (progress.statusMessage.contains('Download') || progress.statusMessage.contains('Network')),
              ),

              if (isDownloading) ...[
                Padding(
                  padding: const EdgeInsets.only(left: 34, top: 2, bottom: 8),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: progress.downloadFraction > 0 ? progress.downloadFraction : null,
                      backgroundColor: Colors.white12,
                      valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFFE5A93C)),
                      minHeight: 6,
                    ),
                  ),
                ),
              ],

              // Step 3: Safety check
              _buildStepRow(
                title: 'Check the file is safe',
                subtitle: isVerifying ? 'Verifying SHA-256 checksum…' : (verifyDone ? 'Verified safe' : null),
                isDone: verifyDone,
                isActive: isVerifying,
                isFailed: isFailed && (progress.statusMessage.contains('check') || progress.statusMessage.contains('Integrity')),
              ),

              // Step 4: Install and restart
              _buildStepRow(
                title: 'Install and restart',
                subtitle: isInstalling ? 'Launching platform installer…' : null,
                isDone: false,
                isActive: isInstalling,
                isFailed: isFailed && progress.statusMessage.contains('Install'),
              ),

              const SizedBox(height: 16),

              // Recording note
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    Icon(Icons.mic_none, size: 16, color: Colors.grey.shade400),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        "If you are recording a voice note, the update waits until it is saved and transcribed.",
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade400,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              if (progress.errorMessage != null) ...[
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEF5350).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFEF5350).withValues(alpha: 0.3)),
                  ),
                  child: Text(
                    progress.errorMessage!,
                    style: const TextStyle(fontSize: 13, color: Color(0xFFFF8A80)),
                  ),
                ),
              ],

              const SizedBox(height: 24),

              // Buttons: Cancel & Retry
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 52,
                      child: OutlinedButton(
                        onPressed: onCancel,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: const BorderSide(color: Colors.white24),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: const Text('Cancel', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                      ),
                    ),
                  ),
                  if (isFailed) ...[
                    const SizedBox(width: 12),
                    Expanded(
                      child: SizedBox(
                        height: 52,
                        child: ElevatedButton(
                          onPressed: onRetry,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFE5A93C),
                            foregroundColor: Colors.black,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: const Text('Retry', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}


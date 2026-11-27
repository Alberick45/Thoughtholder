import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../app_theme.dart';
import '../background_recording_service.dart';
import '../config/update_config.dart';
import '../services/app_update_service.dart';
import '../services/backup_service.dart';
import '../settings_service.dart';
import '../widgets/update_sheets.dart';
import 'group_page_scaffold.dart';

class UpdatesGroupScreen extends StatefulWidget {
  const UpdatesGroupScreen({super.key});

  @override
  State<UpdatesGroupScreen> createState() => _UpdatesGroupScreenState();
}

class _UpdatesGroupScreenState extends State<UpdatesGroupScreen> {
  bool _isChecking = false;
  String _installedVersionStr = 'Loading…';
  AppInstalledVersion? _installedVersion;

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    final v = await AppUpdateService.instance.getInstalledVersion();
    if (mounted) {
      setState(() {
        _installedVersion = v;
        _installedVersionStr = 'Version ${v.versionName} (Build ${v.buildNumber})';
      });
    }
  }

  Future<void> _checkForUpdates(BuildContext context) async {
    final settings = Provider.of<SettingsService>(context, listen: false);
    final recordingService = Provider.of<BackgroundRecordingService>(context, listen: false);

    if (AppUpdateService.instance.isVoiceCaptureActive(recordingService)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Voice recording or transcription in progress. Please wait until finished.'),
        ),
      );
      return;
    }

    setState(() => _isChecking = true);
    try {
      final manifest = await AppUpdateService.instance.checkForUpdates(
        settings: settings,
        manual: true,
      );

      if (!context.mounted) return;

      if (manifest == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not reach release server. Check your connection.')),
        );
        return;
      }

      final note = AppUpdateService.instance.lastCheckNote;
      if (note != null && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(note)));
      }

      final isAvail = await AppUpdateService.instance.isUpdateAvailable(
        manifest: manifest,
        settings: settings,
        ignoreSkipped: true, // Manual check ignores skipped version
      );

      if (!context.mounted) return;

      if (isAvail) {
        final isReq = await AppUpdateService.instance.isUpdateRequired(manifest);
        _showUpdateFlow(manifest, isReq);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFF2E7D32),
            content: Text('ThoughtHolder is up to date (Version ${manifest.version}).'),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        final message = e is UpdateCheckException ? e.userMessage : 'Update check failed: $e';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message)),
        );
      }
    } finally {
      if (mounted) setState(() => _isChecking = false);
    }
  }

  void _showUpdateFlow(VersionManifest manifest, bool isRequired) {
    final settings = Provider.of<SettingsService>(context, listen: false);
    final recordingService = Provider.of<BackgroundRecordingService>(context, listen: false);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      isDismissible: !isRequired,
      enableDrag: !isRequired,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => UpdateAvailableSheet(
        manifest: manifest,
        installedVersion: _installedVersion?.versionName ?? '1.2.0',
        isRequired: isRequired,
        onStartUpdate: () {
          Navigator.of(sheetContext).pop();
          _showUpdatingModal(manifest, settings, recordingService);
        },
      ),
    );
  }

  void _showUpdatingModal(
    VersionManifest manifest,
    SettingsService settings,
    BackgroundRecordingService recordingService,
  ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      builder: (modalContext) => UpdatingModal(
        manifest: manifest,
        onRetry: () {
          AppUpdateService.instance.startUpdate(
            manifest: manifest,
            settings: settings,
            recordingService: recordingService,
          );
        },
        onCancel: () {
          AppUpdateService.instance.cancelUpdate();
          Navigator.of(modalContext).pop();
        },
      ),
    );

    AppUpdateService.instance.startUpdate(
      manifest: manifest,
      settings: settings,
      recordingService: recordingService,
    );
  }

  Future<void> _createManualBackup(BuildContext context) async {
    final settings = Provider.of<SettingsService>(context, listen: false);
    try {
      final backup = await BackupService.instance.createBackup();
      await settings.setLastBackupDate(backup.createdAt);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFF2E7D32),
            content: Text('Safety backup created: ${backup.fileName} (${backup.ideaCount} thoughts)'),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Backup creation failed: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsService>();
    final colors = AppColors.of(settings.theme);

    final lastBackup = settings.lastBackupDate;
    final lastBackupStr = lastBackup != null
        ? '${lastBackup.year}-${lastBackup.month.toString().padLeft(2, '0')}-${lastBackup.day.toString().padLeft(2, '0')} ${lastBackup.hour.toString().padLeft(2, '0')}:${lastBackup.minute.toString().padLeft(2, '0')}'
        : 'No backup recorded yet';

    return GroupPageScaffold(
      title: 'Updates & data safety',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Current Version Card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: colors.card,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: colors.line),
            ),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: colors.goldBg,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: colors.gold.withValues(alpha: 0.3)),
                  ),
                  child: Icon(Icons.info_outline, color: colors.gold, size: 24),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Installed ThoughtHolder',
                        style: appFont(
                          color: colors.mute,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _installedVersionStr,
                        style: appFont(
                          color: colors.text,
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Check for Updates Button
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton.icon(
              onPressed: _isChecking ? null : () => _checkForUpdates(context),
              icon: _isChecking
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                    )
                  : const Icon(Icons.refresh, color: Colors.black),
              label: Text(
                _isChecking ? 'Checking for updates...' : 'Check for updates',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.black,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: colors.gold,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
          if (settings.hasSkippedUpdate) ...[
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: colors.card,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: colors.line),
              ),
              child: Row(
                children: [
                  Icon(Icons.visibility_off_outlined, color: colors.mute, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Skipped update: ${settings.skippedVersion ?? 'build ${settings.skippedBuild}'}',
                      style: appFont(color: colors.mute, fontSize: 13),
                    ),
                  ),
                  TextButton(
                    onPressed: () async {
                      await settings.clearSkippedUpdate();
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Skipped update cleared')),
                        );
                      }
                    },
                    child: Text(
                      'Reset',
                      style: appFont(
                        color: colors.gold,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
          ],

          // Backup Date & Safety Card
          Text(
            'DATA SAFETY',
            style: appFont(
              color: colors.gold,
              fontSize: 12,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.1,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: colors.card,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: colors.line),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.shield_outlined, color: colors.gold, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Last automatic backup',
                            style: appFont(
                              color: colors.text,
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            lastBackupStr,
                            style: appFont(
                              color: colors.mute,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Text(
                  'Your thoughts, tags, buckets, and voice notes are automatically backed up before every update. On Windows, user data is stored safely in AppData and is never touched by installers or updates.',
                  style: appFont(
                    color: colors.mute,
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  height: 44,
                  child: OutlinedButton.icon(
                    onPressed: () => _createManualBackup(context),
                    icon: Icon(Icons.backup_outlined, color: colors.text, size: 18),
                    label: Text(
                      'Back up database now',
                      style: TextStyle(color: colors.text, fontSize: 14, fontWeight: FontWeight.w600),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: colors.line),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Release Channel Settings
          Text(
            'RELEASE CHANNEL',
            style: appFont(
              color: colors.gold,
              fontSize: 12,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.1,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: colors.card,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: colors.line),
            ),
            child: SwitchListTile(
              contentPadding: EdgeInsets.zero,
              activeThumbColor: colors.gold,
              title: Text(
                'Get beta versions',
                style: appFont(
                  color: colors.text,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              subtitle: Text(
                'Receive experimental preview builds before general release',
                style: appFont(
                  color: colors.mute,
                  fontSize: 13,
                ),
              ),
              value: settings.betaUpdatesEnabled,
              onChanged: (val) async {
                await settings.setBetaUpdatesEnabled(val);
              },
            ),
          ),
        ],
      ),
    );
  }
}


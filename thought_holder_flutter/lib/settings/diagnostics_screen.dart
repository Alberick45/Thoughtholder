import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../app_theme.dart';
import '../services/backup_service.dart';
import '../services/self_check_service.dart';
import '../settings_service.dart';
import '../thought_provider.dart';
import 'group_page_scaffold.dart';

class DiagnosticsScreen extends StatefulWidget {
  const DiagnosticsScreen({super.key});

  @override
  State<DiagnosticsScreen> createState() => _DiagnosticsScreenState();
}

class _DiagnosticsScreenState extends State<DiagnosticsScreen> {
  SelfCheckReport? _report;
  List<BackupMetadata> _backups = [];
  bool _isRunningCheck = false;
  bool _isBackingUp = false;
  bool _isRepairing = false;
  bool _isRestoring = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isRunningCheck = true);
    try {
      final report = await SelfCheckService.instance.runSelfCheck();
      final backups = await BackupService.instance.listBackups();
      if (mounted) {
        setState(() {
          _report = report;
          _backups = backups;
          _isRunningCheck = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isRunningCheck = false);
      }
    }
  }

  Future<void> _handleRunCheck() async {
    setState(() => _isRunningCheck = true);
    final report = await SelfCheckService.instance.runSelfCheck();
    final backups = await BackupService.instance.listBackups();
    if (mounted) {
      setState(() {
        _report = report;
        _backups = backups;
        _isRunningCheck = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Self-check complete.'),
          duration: Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _handleFixIt() async {
    setState(() => _isRepairing = true);
    final res = await SelfCheckService.instance.performSafeSelfRepair();
    final report = await SelfCheckService.instance.runSelfCheck();
    final backups = await BackupService.instance.listBackups();
    if (mounted) {
      setState(() {
        _report = report;
        _backups = backups;
        _isRepairing = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(res.message),
          duration: const Duration(seconds: 4),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _handleCreateBackup() async {
    setState(() => _isBackingUp = true);
    try {
      final meta = await BackupService.instance.createBackup();
      final backups = await BackupService.instance.listBackups();
      final report = await SelfCheckService.instance.runSelfCheck();
      if (mounted) {
        setState(() {
          _backups = backups;
          _report = report;
          _isBackingUp = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Backup saved: ${meta.ideaCount} ideas, ${meta.formattedSize}.',
            ),
            duration: const Duration(seconds: 3),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isBackingUp = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not create backup. Please try again.'),
            duration: Duration(seconds: 3),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _handleCopyReport() async {
    if (_report == null) return;
    final text = _report!.toDiagnosticReport();
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Diagnostic report copied (numbers and statuses only).'),
          duration: Duration(seconds: 3),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _handleRestore(BackupMetadata backup) async {
    final file = File(backup.filePath);
    if (!await file.exists()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Selected backup file is no longer on disk.')),
        );
      }
      return;
    }

    setState(() => _isRestoring = true);
    RestorePreparation prep;
    try {
      prep = await BackupService.instance.prepareRestore(file);
    } catch (e) {
      if (mounted) {
        setState(() => _isRestoring = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Cannot restore: ${e.toString()}')),
        );
      }
      return;
    }

    setState(() => _isRestoring = false);

    if (!mounted) return;

    final provider = context.read<ThoughtProvider>();
    final messenger = ScaffoldMessenger.of(context);

    final shouldRestore = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        final colors = AppColors.of(context.read<SettingsService>().theme);
        return AlertDialog(
          backgroundColor: colors.card,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(
            'Restore ideas from backup?',
            style: appFont(
              color: colors.text,
              fontWeight: FontWeight.bold,
              fontSize: 18,
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'This backup has ${prep.backupIdeaCount} ideas, now you have ${prep.currentIdeaCount}. Replace?',
                style: appFont(color: colors.text, fontSize: 15),
              ),
              const SizedBox(height: 12),
              Text(
                'A fresh safety backup of your current database was saved before opening this prompt. Nothing will be lost.',
                style: appFont(color: colors.mute, fontSize: 13),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(
                'Cancel',
                style: appFont(color: colors.mute, fontWeight: FontWeight.bold),
              ),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: colors.gold,
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: const Text('Replace and restore'),
            ),
          ],
        );
      },
    );

    if (shouldRestore == true) {
      setState(() => _isRestoring = true);
      try {
        await BackupService.instance.completeRestore(prep);
        // Reload all thoughts into the provider
        await provider.loadAll();
        if (mounted) {
          await _loadData();
          messenger.showSnackBar(
            const SnackBar(
              content: Text('Restore completed successfully.'),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          messenger.showSnackBar(
            const SnackBar(
              content: Text('Could not complete restore.'),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      } finally {
        if (mounted) {
          setState(() => _isRestoring = false);
        }
      }
    }
  }

  Color _statusColor(CheckStatus status, AppColors colors) {
    switch (status) {
      case CheckStatus.green:
        return colors.done;
      case CheckStatus.amber:
        return const Color(0xFFFFD54F);
      case CheckStatus.red:
        return colors.bad;
    }
  }

  IconData _statusIcon(CheckStatus status) {
    switch (status) {
      case CheckStatus.green:
        return Icons.check_circle_outline;
      case CheckStatus.amber:
        return Icons.warning_amber_rounded;
      case CheckStatus.red:
        return Icons.error_outline;
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsService>();
    final colors = AppColors.of(settings.theme);

    return GroupPageScaffold(
      title: 'Diagnostics',
      child: _report == null && _isRunningCheck
          ? Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 40),
                child: CircularProgressIndicator(color: colors.gold),
              ),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.only(bottom: 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 1. Overview card with numbers
                  _buildOverviewCard(colors),
                  const SizedBox(height: 16),

                  // 2. Action buttons row: Run Check & Copy Report
                  Row(
                    children: [
                      Expanded(
                        child: SizedBox(
                          height: 48,
                          child: ElevatedButton.icon(
                            onPressed: _isRunningCheck ? null : _handleRunCheck,
                            icon: _isRunningCheck
                                ? SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: colors.bg,
                                    ),
                                  )
                                : const Icon(Icons.refresh, size: 20),
                            label: Text(
                              _isRunningCheck ? 'Checking...' : 'Run check',
                              style: appFont(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: colors.gold,
                              foregroundColor: Colors.black,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: SizedBox(
                          height: 48,
                          child: OutlinedButton.icon(
                            onPressed: _report == null ? null : _handleCopyReport,
                            icon: Icon(Icons.copy, size: 18, color: colors.text),
                            label: Text(
                              'Copy report',
                              style: appFont(
                                color: colors.text,
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                            style: OutlinedButton.styleFrom(
                              side: BorderSide(color: colors.line),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),

                  // 3. Auto-repair banner if issues exist
                  if (_report != null && _report!.hasRepairableIssues) ...[
                    const SizedBox(height: 16),
                    _buildRepairBanner(colors),
                  ],

                  const SizedBox(height: 24),

                  // 4. Per-area check results
                  Text(
                    'Health by area',
                    style: appFont(
                      color: colors.text,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 10),
                  if (_report != null)
                    ..._report!.items.map((item) => _buildItemCard(item, colors)),

                  const SizedBox(height: 28),

                  // 5. Backups and Safe Restore section
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Stored backups',
                        style: appFont(
                          color: colors.text,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      SizedBox(
                        height: 38,
                        child: TextButton.icon(
                          onPressed: _isBackingUp ? null : _handleCreateBackup,
                          icon: _isBackingUp
                              ? SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: colors.gold,
                                  ),
                                )
                              : Icon(Icons.add, size: 18, color: colors.gold),
                          label: Text(
                            _isBackingUp ? 'Backing up...' : 'Back up now',
                            style: appFont(
                              color: colors.gold,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  _buildBackupsList(colors),
                ],
              ),
            ),
    );
  }

  Widget _buildOverviewCard(AppColors colors) {
    final report = _report;
    final dbSize = report?.formattedDatabaseSize ?? 'Calculating...';
    final lastBackup = report?.formattedLastBackup ?? 'Never';
    final appVer = report?.appVersion ?? SelfCheckService.appVersion;
    final dbVer = report != null ? 'v${report.databaseSchemaVersion}' : 'v3';

    return Container(
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
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'System Status',
                style: appFont(
                  color: colors.text,
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
              if (report != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: _statusColor(report.overallStatus, colors).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: _statusColor(report.overallStatus, colors)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _statusIcon(report.overallStatus),
                        size: 14,
                        color: _statusColor(report.overallStatus, colors),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        report.overallStatus == CheckStatus.green
                            ? 'All healthy'
                            : report.overallStatus == CheckStatus.amber
                                ? 'Attention'
                                : 'Critical',
                        style: appFont(
                          color: _statusColor(report.overallStatus, colors),
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _buildOverviewMetric('Database size', dbSize, colors),
              _buildOverviewMetric('Last backup', lastBackup, colors),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _buildOverviewMetric('App version', appVer, colors),
              _buildOverviewMetric('Database version', dbVer, colors),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildOverviewMetric(String label, String value, AppColors colors) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: appFont(color: colors.mute, fontSize: 12),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: appFont(
              color: colors.text,
              fontWeight: FontWeight.w600,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRepairBanner(AppColors colors) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFFD54F).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFFFD54F)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.build_circle_outlined, color: Color(0xFFFFD54F), size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Small fixes available',
                  style: appFont(
                    color: colors.text,
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Self-repair can safely add missing indexes or folder names. It will make a safety backup first, and will never delete, move, or alter any of your ideas.',
            style: appFont(color: colors.text, fontSize: 13),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 40,
            child: ElevatedButton.icon(
              onPressed: _isRepairing ? null : _handleFixIt,
              icon: _isRepairing
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                    )
                  : const Icon(Icons.healing, size: 18),
              label: Text(_isRepairing ? 'Repairing safely...' : 'Fix it'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFFD54F),
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildItemCard(CheckItemResult item, AppColors colors) {
    final color = _statusColor(item.status, colors);
    final icon = _statusIcon(item.status);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.line),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      item.title,
                      style: appFont(
                        color: colors.text,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    Text(
                      item.status == CheckStatus.green
                          ? 'Pass'
                          : item.status == CheckStatus.amber
                              ? 'Attention'
                              : 'Check',
                      style: appFont(
                        color: color,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  item.summary,
                  style: appFont(
                    color: colors.text,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (item.details.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    item.details,
                    style: appFont(color: colors.mute, fontSize: 12),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBackupsList(AppColors colors) {
    if (_backups.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: colors.bg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: colors.line),
        ),
        child: Center(
          child: Text(
            'No backups stored yet. Tap "Back up now" above.',
            style: appFont(color: colors.mute, fontSize: 13),
          ),
        ),
      );
    }

    return Column(
      children: _backups.map((b) {
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: colors.bg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: colors.line),
          ),
          child: Row(
            children: [
              Icon(Icons.inventory_2_outlined, color: colors.gold, size: 22),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      b.formattedDate,
                      style: appFont(
                        color: colors.text,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${b.ideaCount} ideas · ${b.formattedSize}',
                      style: appFont(color: colors.mute, fontSize: 12),
                    ),
                  ],
                ),
              ),
              SizedBox(
                height: 36,
                child: OutlinedButton(
                  onPressed: _isRestoring ? null : () => _handleRestore(b),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: colors.line),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: Text(
                    'Restore',
                    style: appFont(
                      color: colors.text,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

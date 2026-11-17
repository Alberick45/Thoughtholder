import 'dart:async';
import 'dart:io';
import 'package:audioplayers/audioplayers.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'app_theme.dart';
import 'background_recording_service.dart';
import 'database_helper.dart';
import 'settings_service.dart';
import 'thought_provider.dart';

class VoiceRecordingsScreen extends StatefulWidget {
  const VoiceRecordingsScreen({super.key});

  @override
  State<VoiceRecordingsScreen> createState() => _VoiceRecordingsScreenState();
}

class _VoiceRecordingsScreenState extends State<VoiceRecordingsScreen> {
  List<Map<String, dynamic>> _recordings = [];
  bool _loading = true;
  String? _currentlyPlayingId;
  final AudioPlayer _audioPlayer = AudioPlayer();
  PlayerState _playerState = PlayerState.stopped;
  Duration _currentPosition = Duration.zero;
  Duration _currentTotalDuration = Duration.zero;
  StreamSubscription? _posSub;
  StreamSubscription? _durSub;
  StreamSubscription? _stateSub;

  @override
  void initState() {
    super.initState();
    _loadRecordings();

    _posSub = _audioPlayer.onPositionChanged.listen((p) {
      if (mounted) setState(() => _currentPosition = p);
    });
    _durSub = _audioPlayer.onDurationChanged.listen((d) {
      if (mounted) setState(() => _currentTotalDuration = d);
    });
    _stateSub = _audioPlayer.onPlayerStateChanged.listen((s) {
      if (mounted) setState(() => _playerState = s);
    });
  }

  @override
  void dispose() {
    _posSub?.cancel();
    _durSub?.cancel();
    _stateSub?.cancel();
    _audioPlayer.dispose();
    super.dispose();
  }

  Future<void> _loadRecordings() async {
    setState(() => _loading = true);
    final list = await DatabaseHelper.instance.fetchVoiceRecordings();
    if (mounted) {
      setState(() {
        _recordings = list;
        _loading = false;
      });
    }
  }

  Future<void> _togglePlay(String id, String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Audio file no longer exists on disk'),
          behavior: SnackBarBehavior.floating,
          margin: EdgeInsets.only(bottom: 84, left: 16, right: 16),
        ),
      );
      return;
    }

    if (_currentlyPlayingId == id && _playerState == PlayerState.playing) {
      await _audioPlayer.pause();
    } else if (_currentlyPlayingId == id && _playerState == PlayerState.paused) {
      await _audioPlayer.resume();
    } else {
      await _audioPlayer.stop();
      _currentlyPlayingId = id;
      _currentPosition = Duration.zero;
      await _audioPlayer.play(DeviceFileSource(filePath));
    }
  }

  Future<void> _saveAudioFile(String filePath, String defaultName) async {
    final file = File(filePath);
    if (!await file.exists()) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Audio file not found on disk'),
          behavior: SnackBarBehavior.floating,
          margin: EdgeInsets.only(bottom: 84, left: 16, right: 16),
        ),
      );
      return;
    }

    try {
      if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
        final outputPath = await FilePicker.saveFile(
          dialogTitle: 'Save Audio Recording',
          fileName: '$defaultName.wav',
          type: FileType.custom,
          allowedExtensions: ['wav'],
        );
        if (outputPath != null && outputPath.isNotEmpty) {
          await file.copy(outputPath);
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Saved audio to $outputPath'),
              behavior: SnackBarBehavior.floating,
              margin: const EdgeInsets.only(bottom: 84, left: 16, right: 16),
            ),
          );
        }
      } else {
        // Mobile: share file
        await Share.shareXFiles([XFile(filePath)], text: 'ThoughtHolder voice note');
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to save audio: $e'),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.only(bottom: 84, left: 16, right: 16),
        ),
      );
    }
  }

  Future<void> _confirmDelete(String id, String filePath) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Voice Recording?'),
        content: const Text('This will delete the audio file from disk and remove its record. Pinned or created thoughts will stay.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      if (_currentlyPlayingId == id) {
        await _audioPlayer.stop();
        _currentlyPlayingId = null;
      }
      try {
        final f = File(filePath);
        if (await f.exists()) await f.delete();
      } catch (_) {}

      await DatabaseHelper.instance.deleteVoiceRecording(id);
      await _loadRecordings();
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsService>();
    final colors = AppColors.of(settings.theme);
    final bgService = context.watch<BackgroundRecordingService>();
    final thoughtProvider = context.watch<ThoughtProvider>();

    return Scaffold(
      backgroundColor: colors.bg,
      appBar: AppBar(
        backgroundColor: colors.bg,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: colors.text),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          'Voice Recordings',
          style: appFont(
            color: colors.text,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.refresh, color: colors.mute),
            tooltip: 'Refresh',
            onPressed: _loadRecordings,
          ),
        ],
      ),
      body: _loading
          ? Center(child: CircularProgressIndicator(color: colors.gold))
          : _recordings.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.mic_none, size: 54, color: colors.mute.withOpacity(0.5)),
                      const SizedBox(height: 12),
                      Text(
                        'No voice recordings yet',
                        style: appFont(color: colors.mute, fontSize: 16),
                      ),
                    ],
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  itemCount: _recordings.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final rec = _recordings[index];
                    final id = rec['id'] as String;
                    final filePath = rec['file_path'] as String;
                    final durationSec = (rec['duration_seconds'] as num?)?.toInt() ?? 0;
                    final createdAt = (rec['created_at'] as num?)?.toInt() ?? 0;
                    final dt = DateTime.fromMillisecondsSinceEpoch(createdAt);
                    final dateStr = BackgroundRecordingService.formatRecordingDate(dt);
                    final durStr = BackgroundRecordingService.formatSeconds(durationSec);
                    final status = (rec['status'] as String? ?? 'saved').toLowerCase();
                    final errorMsg = rec['error_message'] as String?;
                    final transcript = rec['transcript'] as String?;
                    final totalSegs = (rec['total_segments'] as num?)?.toInt() ?? 1;
                    final compSegs = (rec['completed_segments'] as num?)?.toInt() ?? 0;
                    final isPlaying = _currentlyPlayingId == id && _playerState == PlayerState.playing;

                    return Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: colors.card,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: colors.line),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Header: Date, Duration, Status
                          Row(
                            children: [
                              Icon(Icons.mic, size: 18, color: colors.gold),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  dateStr,
                                  style: appFont(
                                    color: colors.text,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                              Text(
                                durStr,
                                style: appFont(color: colors.mute, fontSize: 13),
                              ),
                              const SizedBox(width: 10),
                              _buildStatusBadge(status, totalSegs, compSegs, colors),
                            ],
                          ),

                          // Error message if any
                          if (errorMsg != null && errorMsg.isNotEmpty && status == 'failed') ...[
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: Colors.red.withOpacity(0.12),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                errorMsg,
                                style: appFont(color: Colors.redAccent, fontSize: 12),
                              ),
                            ),
                          ],

                          // Transcript snippet if done
                          if (transcript != null && transcript.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Text(
                              transcript,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: appFont(color: colors.mute, fontSize: 12, height: 1.3),
                            ),
                          ],

                          // Audio playback scrubber (if this item is selected/playing)
                          if (_currentlyPlayingId == id) ...[
                            const SizedBox(height: 10),
                            SliderTheme(
                              data: SliderTheme.of(context).copyWith(
                                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                                trackHeight: 3,
                                activeTrackColor: colors.gold,
                                inactiveTrackColor: colors.line,
                                thumbColor: colors.gold,
                              ),
                              child: Slider(
                                value: _currentPosition.inMilliseconds
                                    .clamp(0, _currentTotalDuration.inMilliseconds)
                                    .toDouble(),
                                max: (_currentTotalDuration.inMilliseconds > 0
                                        ? _currentTotalDuration.inMilliseconds
                                        : 1)
                                    .toDouble(),
                                onChanged: (v) {
                                  _audioPlayer.seek(Duration(milliseconds: v.round()));
                                },
                              ),
                            ),
                          ],

                          const SizedBox(height: 10),
                          // Action buttons
                          Row(
                            children: [
                              // Play / Pause
                              IconButton(
                                icon: Icon(
                                  isPlaying ? Icons.pause_circle_filled : Icons.play_circle_fill,
                                  color: colors.gold,
                                  size: 28,
                                ),
                                tooltip: isPlaying ? 'Pause' : 'Play',
                                onPressed: () => _togglePlay(id, filePath),
                              ),

                              // Retry Button (ALWAYS AVAILABLE)
                              ElevatedButton.icon(
                                icon: const Icon(Icons.refresh, size: 14),
                                label: const Text('Retry'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: colors.gold.withOpacity(0.15),
                                  foregroundColor: colors.gold,
                                  elevation: 0,
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                  textStyle: appFont(fontSize: 12, fontWeight: FontWeight.bold),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(6),
                                    side: BorderSide(color: colors.gold.withOpacity(0.4)),
                                  ),
                                ),
                                onPressed: () async {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Starting transcription retry…'),
                                      behavior: SnackBarBehavior.floating,
                                      margin: EdgeInsets.only(bottom: 84, left: 16, right: 16),
                                    ),
                                  );
                                  await bgService.retryRecording(
                                    id,
                                    thoughtProvider: thoughtProvider,
                                    settings: settings,
                                    onFeedback: (msg) {
                                      if (mounted) {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(
                                            content: Text(msg),
                                            behavior: SnackBarBehavior.floating,
                                            margin: const EdgeInsets.only(bottom: 84, left: 16, right: 16),
                                          ),
                                        );
                                      }
                                    },
                                  );
                                  await _loadRecordings();
                                },
                              ),

                              // Retry failed parts (if failed parts exist)
                              if (status == 'failed' || (totalSegs > 1 && compSegs < totalSegs)) ...[
                                const SizedBox(width: 8),
                                OutlinedButton(
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: colors.text,
                                    side: BorderSide(color: colors.line),
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                    textStyle: appFont(fontSize: 11),
                                  ),
                                  onPressed: () async {
                                    await bgService.retryFailedSegments(
                                      id,
                                      thoughtProvider: thoughtProvider,
                                      settings: settings,
                                      onFeedback: (msg) {
                                        if (mounted) {
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            SnackBar(
                                              content: Text(msg),
                                              behavior: SnackBarBehavior.floating,
                                              margin: const EdgeInsets.only(bottom: 84, left: 16, right: 16),
                                            ),
                                          );
                                        }
                                      },
                                    );
                                    await _loadRecordings();
                                  },
                                  child: const Text('Retry failed parts'),
                                ),
                              ],

                              const Spacer(),

                              // Save audio file button
                              IconButton(
                                icon: Icon(Icons.download, size: 20, color: colors.mute),
                                tooltip: 'Save audio file',
                                onPressed: () => _saveAudioFile(filePath, 'voice_note_${dt.millisecondsSinceEpoch}'),
                              ),

                              // Delete button
                              IconButton(
                                icon: Icon(Icons.delete_outline, size: 20, color: colors.mute),
                                tooltip: 'Delete recording',
                                onPressed: () => _confirmDelete(id, filePath),
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                ),
    );
  }

  Widget _buildStatusBadge(String status, int totalSegs, int compSegs, AppColors colors) {
    Color badgeColor;
    String label;

    switch (status) {
      case 'recording':
        badgeColor = Colors.blue;
        label = 'Recording';
        break;
      case 'transcribing':
        badgeColor = Colors.purpleAccent;
        label = totalSegs > 1 ? 'Transcribing $compSegs/$totalSegs' : 'Transcribing';
        break;
      case 'done':
        badgeColor = colors.ok;
        label = 'Done';
        break;
      case 'failed':
        badgeColor = colors.bad;
        label = 'Failed';
        break;
      case 'saved':
      default:
        badgeColor = Colors.amber;
        label = 'Saved';
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: badgeColor.withOpacity(0.18),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: badgeColor.withOpacity(0.4)),
      ),
      child: Text(
        label,
        style: appFont(
          color: badgeColor,
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

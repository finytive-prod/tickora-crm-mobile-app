import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:crm_mobile/core/theme/app_colors.dart';

class InAppAudioPlayerModal extends StatefulWidget {
  final String filePath;
  final String title;

  final Function(int)? onDurationFound;

  const InAppAudioPlayerModal({
    super.key,
    required this.filePath,
    required this.title,
    this.onDurationFound,
  });

  static Future<void> show(BuildContext context, {required String filePath, required String title, Function(int)? onDurationFound}) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => InAppAudioPlayerModal(filePath: filePath, title: title, onDurationFound: onDurationFound),
    );
  }

  @override
  State<InAppAudioPlayerModal> createState() => _InAppAudioPlayerModalState();
}

class _InAppAudioPlayerModalState extends State<InAppAudioPlayerModal> {
  late AudioPlayer _audioPlayer;
  bool _isPlaying = false;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;
  double _playbackRate = 1.0;
  bool _isLoading = true;
  bool _isBuffering = false;
  String? _errorMessage;
  bool _usingNativePlayer = false;
  Timer? _nativePoller;

  @override
  void initState() {
    super.initState();
    _audioPlayer = AudioPlayer();

    _listenToPlayerState();
    _initAudio();
  }

  Future<bool> _checkAudioFileValid(File file) async {
    if (!await file.exists()) return false;
    final len = await file.length();
    if (len < 500) return false;

    try {
      final raf = await file.open(mode: FileMode.read);
      final bytes = await raf.read(64);
      await raf.close();

      if (bytes.isEmpty) return false;

      final firstByte = bytes[0];
      if (firstByte == 0x7B /* '{' */ || firstByte == 0x3C /* '<' */) {
        return false;
      }

      final asciiStr = String.fromCharCodes(bytes.where((b) => b >= 32 && b <= 126));
      if (asciiStr.contains('<html>') || asciiStr.contains('<HTML>') || asciiStr.contains('404 Not Found') || asciiStr.contains('"success":false')) {
        return false;
      }
      return true;
    } catch (_) {
      return true;
    }
  }

  Future<void> _initAudio() async {
    try {
      final isUrl = widget.filePath.startsWith('http://') || widget.filePath.startsWith('https://');
      if (!isUrl) {
        final file = File(widget.filePath);
        final isValid = await _checkAudioFileValid(file);
        if (!isValid) {
          if (mounted) {
            setState(() {
              _isLoading = false;
              _errorMessage = 'Audio recording file is empty or unavailable on the server.';
            });
          }
          return;
        }
      }

      // Phase 1: Try native Android MediaPlayer for max OEM audio format compatibility (AMR, 3GP, M4A, MP3, WAV)
      if (Platform.isAndroid) {
        final success = await _playViaNativePlayer();
        if (success) return;
      }

      // Phase 2: Fallback to audioplayers plugin if not Android or native player fails
      try {
        await const MethodChannel('com.example.crm_mobile/call_recording').invokeMethod('forceLoudspeaker');
      } catch (_) {}

      await _audioPlayer.setAudioContext(AudioContext(
        android: AudioContextAndroid(
          stayAwake: true,
          contentType: AndroidContentType.music,
          usageType: AndroidUsageType.media,
          audioFocus: AndroidAudioFocus.gain,
        ),
      ));

      await _audioPlayer.setVolume(1.0);
      if (isUrl) {
        await _audioPlayer.play(UrlSource(widget.filePath));
      } else {
        await _audioPlayer.play(DeviceFileSource(widget.filePath));
      }

      // Ensure loading spinner is dismissed after brief delay if playing
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted && _isLoading) {
          setState(() {
            _isLoading = false;
            _isPlaying = true;
          });
        }
      });
    } catch (e) {
      debugPrint('audioplayers error: $e, trying native player...');
      final success = await _playViaNativePlayer();
      if (!success && mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Unable to play this audio recording.';
        });
      }
    }
  }

  Future<bool> _playViaNativePlayer() async {
    try {
      const channel = MethodChannel('com.example.crm_mobile/call_recording');
      final dynamic resRaw = await channel.invokeMethod('startNativeAudio', {'path': widget.filePath});
      if (resRaw != null) {
        final res = Map<String, dynamic>.from(resRaw as Map);
        if (res['success'] == true) {
          final durationMs = (res['durationMs'] as num?)?.toInt() ?? 0;
          if (mounted) {
            setState(() {
              _usingNativePlayer = true;
              _isPlaying = true;
              _isLoading = false;
              _errorMessage = null;
              _duration = Duration(milliseconds: durationMs);
            });
            if (durationMs > 0) {
              widget.onDurationFound?.call((durationMs / 1000).round());
            }
          }
          _startNativePoller();
          return true;
        }
      }
    } catch (e) {
      debugPrint('Native player start error: $e');
    }
    return false;
  }

  void _startNativePoller() {
    _nativePoller?.cancel();
    _nativePoller = Timer.periodic(const Duration(milliseconds: 300), (timer) async {
      if (!_usingNativePlayer || !mounted) {
        timer.cancel();
        return;
      }
      try {
        const channel = MethodChannel('com.example.crm_mobile/call_recording');
        final dynamic resRaw = await channel.invokeMethod('getNativeAudioState');
        if (resRaw != null && mounted) {
          final res = Map<String, dynamic>.from(resRaw as Map);
          final isPlaying = res['isPlaying'] == true;
          final posMs = (res['positionMs'] as num?)?.toInt() ?? 0;
          final durMs = (res['durationMs'] as num?)?.toInt() ?? 0;

          setState(() {
            _isPlaying = isPlaying;
            _position = Duration(milliseconds: posMs);
            if (durMs > 0) _duration = Duration(milliseconds: durMs);
          });

          if (!isPlaying && posMs > 0 && durMs > 0 && posMs >= durMs - 500) {
            setState(() {
              _position = Duration.zero;
              _isPlaying = false;
            });
          }
        }
      } catch (_) {}
    });
  }

  void _listenToPlayerState() {
    _audioPlayer.onPlayerStateChanged.listen((state) {
      if (mounted && !_usingNativePlayer) {
        setState(() {
          _isPlaying = state == PlayerState.playing;
          if (state == PlayerState.playing || state == PlayerState.paused) {
            _isLoading = false;
          }
        });
      }
    });

    _audioPlayer.onDurationChanged.listen((newDuration) {
      if (mounted && !_usingNativePlayer) {
        setState(() {
          _duration = newDuration;
        });
        if (newDuration.inSeconds > 0) {
          widget.onDurationFound?.call(newDuration.inSeconds);
        }
      }
    });

    _audioPlayer.onPositionChanged.listen((newPosition) {
      if (mounted && !_usingNativePlayer) {
        setState(() {
          _position = newPosition;
        });
      }
    });

    _audioPlayer.onPlayerComplete.listen((_) {
      if (mounted && !_usingNativePlayer) {
        setState(() {
          _position = Duration.zero;
          _isPlaying = false;
        });
      }
    });
  }

  @override
  void dispose() {
    _nativePoller?.cancel();
    if (_usingNativePlayer) {
      try {
        const MethodChannel('com.example.crm_mobile/call_recording').invokeMethod('stopNativeAudio');
      } catch (_) {}
    } else {
      _audioPlayer.stop();
      _audioPlayer.dispose();
    }
    super.dispose();
  }

  void _togglePlayPause() async {
    if (_isBuffering) return;
    if (_usingNativePlayer) {
      const channel = MethodChannel('com.example.crm_mobile/call_recording');
      if (_isPlaying) {
        await channel.invokeMethod('pauseNativeAudio');
        if (mounted) setState(() => _isPlaying = false);
      } else {
        if (mounted) setState(() => _isBuffering = true);
        try {
          await channel.invokeMethod('resumeNativeAudio');
          if (mounted) setState(() => _isPlaying = true);
        } finally {
          if (mounted) setState(() => _isBuffering = false);
        }
      }
      return;
    }

    try {
      if (_isPlaying) {
        await _audioPlayer.pause();
      } else {
        if (mounted) setState(() => _isBuffering = true);
        final state = _audioPlayer.state;
        final isUrl = widget.filePath.startsWith('http://') || widget.filePath.startsWith('https://');
        if (state == PlayerState.completed || state == PlayerState.stopped || _position == Duration.zero) {
          if (isUrl) {
            await _audioPlayer.play(UrlSource(widget.filePath));
          } else {
            await _audioPlayer.play(DeviceFileSource(widget.filePath));
          }
        } else {
          await _audioPlayer.resume();
        }
      }
    } catch (e) {
      debugPrint('Error toggling play/pause: $e');
      _playViaNativePlayer();
    } finally {
      if (mounted && _isBuffering) {
        setState(() => _isBuffering = false);
      }
    }
  }

  void _seek(double seconds) async {
    final posMs = (seconds * 1000).toInt();
    if (_usingNativePlayer) {
      const channel = MethodChannel('com.example.crm_mobile/call_recording');
      await channel.invokeMethod('seekNativeAudio', {'positionMs': posMs});
      if (mounted) setState(() => _position = Duration(milliseconds: posMs));
      return;
    }
    await _audioPlayer.seek(Duration(seconds: seconds.toInt()));
  }

  void _changeSpeed(double speed) async {
    if (!_usingNativePlayer) {
      await _audioPlayer.setPlaybackRate(speed);
    }
    setState(() {
      _playbackRate = speed;
    });
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    if (duration.inHours > 0) {
      final hours = twoDigits(duration.inHours);
      return '$hours:$minutes:$seconds';
    }
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: Colors.black26,
            blurRadius: 16,
            offset: Offset(0, -4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Drag handle indicator
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),

          // Header title & close button
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.graphic_eq_rounded, color: AppColors.primary, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Call Recording',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: AppColors.primary,
                        letterSpacing: 0.5,
                      ),
                    ),
                    Text(
                      widget.title,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.refresh_rounded, color: AppColors.primary),
                tooltip: 'Restart Playback',
                onPressed: () {
                  _seek(0.0);
                  if (!_isPlaying) _togglePlayPause();
                },
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded, color: AppColors.textHint),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),

          const SizedBox(height: 20),

          if (_isLoading) ...[
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24.0),
              child: CircularProgressIndicator(color: AppColors.primary),
            ),
          ] else if (_errorMessage != null) ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16.0),
              child: Text(
                _errorMessage!,
                style: const TextStyle(color: AppColors.primary, fontSize: 13),
              ),
            ),
          ] else ...[
            // Seekbar slider
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: AppColors.primary,
                inactiveTrackColor: AppColors.primary.withValues(alpha: 0.15),
                thumbColor: AppColors.primary,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7.0),
                overlayColor: AppColors.primary.withValues(alpha: 0.2),
                trackHeight: 4.0,
              ),
              child: Slider(
                min: 0.0,
                max: _duration.inSeconds.toDouble() > 0 ? _duration.inSeconds.toDouble() : 1.0,
                value: _position.inSeconds.toDouble().clamp(
                      0.0,
                      _duration.inSeconds.toDouble() > 0 ? _duration.inSeconds.toDouble() : 1.0,
                    ),
                onChanged: (val) => _seek(val),
              ),
            ),

            // Elapsed / Total duration timestamps
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _formatDuration(_position),
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                  ),
                  Text(
                    _formatDuration(_duration),
                    style: const TextStyle(fontSize: 12, color: AppColors.textHint),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Playback controls row
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                // Speed selector
                PopupMenuButton<double>(
                  initialValue: _playbackRate,
                  onSelected: (speed) => _changeSpeed(speed),
                  itemBuilder: (context) => [
                    const PopupMenuItem(value: 0.75, child: Text('0.75x')),
                    const PopupMenuItem(value: 1.0, child: Text('1.0x (Normal)')),
                    const PopupMenuItem(value: 1.25, child: Text('1.25x')),
                    const PopupMenuItem(value: 1.5, child: Text('1.5x')),
                    const PopupMenuItem(value: 2.0, child: Text('2.0x')),
                  ],
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: Text(
                      '${_playbackRate}x',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                    ),
                  ),
                ),

                // Rewind 10s
                IconButton(
                  iconSize: 28,
                  icon: const Icon(Icons.replay_10_rounded, color: AppColors.textPrimary),
                  onPressed: () {
                    final target = _position - const Duration(seconds: 10);
                    _seek(target.inSeconds < 0 ? 0 : target.inSeconds.toDouble());
                  },
                ),

                // Big Play / Pause button
                GestureDetector(
                  onTap: _togglePlayPause,
                  child: Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.primary.withValues(alpha: 0.35),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Center(
                      child: _isBuffering
                          ? const SizedBox(
                              width: 26,
                              height: 26,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2.5,
                              ),
                            )
                          : Icon(
                              _isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                              color: Colors.white,
                              size: 36,
                            ),
                    ),
                  ),
                ),

                // Fast Forward 10s
                IconButton(
                  iconSize: 28,
                  icon: const Icon(Icons.forward_10_rounded, color: AppColors.textPrimary),
                  onPressed: () {
                    final target = _position + const Duration(seconds: 10);
                    final maxSec = _duration.inSeconds.toDouble();
                    _seek(target.inSeconds.toDouble() > maxSec ? maxSec : target.inSeconds.toDouble());
                  },
                ),

                const SizedBox(width: 32),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

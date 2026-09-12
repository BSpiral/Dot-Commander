import 'package:audioplayers/audioplayers.dart';

/// Cosmetic local playback only. Missing audio devices cannot affect gameplay.
class CannonAudio {
  AudioPlayer? _player;
  bool _disposed = false;
  Future<void> play() async {
    if (_disposed) return;
    try {
      await (_player ??= AudioPlayer()).play(
        AssetSource('audio/cannon.wav'),
        volume: .3,
      );
    } catch (_) {
      /* Audio is optional on headless/test devices. */
    }
  }

  Future<void> dispose() async {
    _disposed = true;
    await _player?.dispose();
  }
}

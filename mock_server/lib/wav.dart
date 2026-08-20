import 'dart:math' as math;
import 'dart:typed_data';

/// 生成一段可播放的 PCM WAV（正弦波 + 泛音），用于流媒体播放路径验证。
///
/// [durationSeconds] 默认 20 秒，44100Hz / 16bit / 单声道。
Uint8List generateWav({int durationSeconds = 20}) {
  const int sampleRate = 44100;
  const int channels = 1;
  const int bitsPerSample = 16;
  final int sampleCount = sampleRate * durationSeconds;
  final int dataSize = sampleCount * channels * (bitsPerSample ~/ 8);
  final int bufferSize = 44 + dataSize;
  final Uint8List bytes = Uint8List(bufferSize);
  final ByteData bd = ByteData.view(bytes.buffer);

  void writeString(int offset, String s) {
    for (int i = 0; i < s.length; i++) {
      bd.setUint8(offset + i, s.codeUnitAt(i));
    }
  }

  // RIFF 头
  writeString(0, 'RIFF');
  bd.setUint32(4, 36 + dataSize, Endian.little);
  writeString(8, 'WAVE');
  writeString(12, 'fmt ');
  bd.setUint32(16, 16, Endian.little); // fmt chunk size
  bd.setUint16(20, 1, Endian.little); // PCM
  bd.setUint16(22, channels, Endian.little);
  bd.setUint32(24, sampleRate, Endian.little);
  bd.setUint32(28, sampleRate * channels * (bitsPerSample ~/ 8), Endian.little);
  bd.setUint16(32, channels * (bitsPerSample ~/ 8), Endian.little);
  bd.setUint16(34, bitsPerSample, Endian.little);
  writeString(36, 'data');
  bd.setUint32(40, dataSize, Endian.little);

  // 采样：基音 + 低幅泛音，产生非纯正弦的听感。
  const double baseFreq = 220.0;
  final math.Random random = math.Random(42);
  final double phaseOffset = random.nextDouble() * 2 * math.pi;
  for (int i = 0; i < sampleCount; i++) {
    final double t = i / sampleRate;
    final double sample =
        0.5 * math.sin(2 * math.pi * baseFreq * t + phaseOffset) +
        0.15 * math.sin(2 * math.pi * baseFreq * 1.5 * t) +
        0.08 * math.sin(2 * math.pi * baseFreq * 2.0 * t);
    final int value = (sample * 32767).round().clamp(-32768, 32767);
    bd.setInt16(44 + i * 2, value, Endian.little);
  }

  return bytes;
}

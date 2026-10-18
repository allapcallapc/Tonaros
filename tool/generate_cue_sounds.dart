// Generates the cue sounds in assets/sounds/ - short synthesized tones,
// one per phase change, so every cue is distinct and no third-party audio
// is bundled. Re-run after changing a sound:
//
//   dart run tool/generate_cue_sounds.dart
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

const sampleRate = 22050;

/// A note: [freq] Hz (gliding to [toFreq] if set) for [ms] milliseconds.
class Note {
  const Note(this.freq, this.ms, {this.toFreq, this.gapMs = 0, this.gain = 1});

  final double freq;
  final double? toFreq;
  final int ms;

  /// Silence after the note.
  final int gapMs;
  final double gain;
}

/// A soft bell: sine plus a quiet octave, fast attack, exponential decay.
List<double> render(List<Note> notes) {
  final out = <double>[];
  for (final n in notes) {
    final count = sampleRate * n.ms ~/ 1000;
    var phase = 0.0;
    for (var i = 0; i < count; i++) {
      final t = i / count;
      final f = n.toFreq == null ? n.freq : n.freq + (n.toFreq! - n.freq) * t;
      phase += 2 * pi * f / sampleRate;
      final attack = min(1.0, i / (sampleRate * 0.005));
      final decay = exp(-4 * t);
      final release = min(1.0, (count - i) / (sampleRate * 0.01));
      out.add((sin(phase) + 0.25 * sin(2 * phase)) /
          1.25 *
          attack *
          decay *
          release *
          n.gain);
    }
    out.addAll(List.filled(sampleRate * n.gapMs ~/ 1000, 0));
  }
  return out;
}

Uint8List wav(List<double> samples, {double volume = 0.8}) {
  final data = ByteData(44 + samples.length * 2);
  void ascii(int offset, String s) {
    for (var i = 0; i < s.length; i++) {
      data.setUint8(offset + i, s.codeUnitAt(i));
    }
  }

  ascii(0, 'RIFF');
  data.setUint32(4, 36 + samples.length * 2, Endian.little);
  ascii(8, 'WAVE');
  ascii(12, 'fmt ');
  data.setUint32(16, 16, Endian.little); // PCM chunk size
  data.setUint16(20, 1, Endian.little); // PCM
  data.setUint16(22, 1, Endian.little); // mono
  data.setUint32(24, sampleRate, Endian.little);
  data.setUint32(28, sampleRate * 2, Endian.little);
  data.setUint16(32, 2, Endian.little);
  data.setUint16(34, 16, Endian.little);
  ascii(36, 'data');
  data.setUint32(40, samples.length * 2, Endian.little);
  for (var i = 0; i < samples.length; i++) {
    data.setInt16(44 + i * 2,
        (samples[i].clamp(-1.0, 1.0) * volume * 32767).round(), Endian.little);
  }
  return data.buffer.asUint8List();
}

// Note frequencies.
const c5 = 523.25, e5 = 659.25, g5 = 783.99, a5 = 880.0, c6 = 1046.5;
const a4 = 440.0, e4 = 329.63, g4 = 392.0;

final sounds = <String, List<Note>>{
  // Hold 1: one bright, firm ding.
  'hold1': [const Note(a5, 350)],
  // Hold 2: two quick dings, so Left/Right sound different.
  'hold2': [const Note(e5, 140, gapMs: 40), const Note(e5, 220)],
  // Rest: a relaxing falling pair.
  'rest': [const Note(e5, 160, gapMs: 20), const Note(c5, 300)],
  // Rest between sets: a longer, lower falling triad.
  'set_rest': [
    const Note(g5, 160, gapMs: 20),
    const Note(e5, 160, gapMs: 20),
    const Note(c5, 400),
  ],
  // Tempo move: a rising glide.
  'move': [const Note(a4, 300, toFreq: a5)],
  // Tempo hold: a short high ping.
  'tempo_hold': [const Note(c6, 200)],
  // Tempo return: a falling glide.
  'back': [const Note(a5, 300, toFreq: a4)],
  // Get ready / transition: a soft neutral blip.
  'get_ready': [const Note(g4, 220, gain: 0.8)],
  'transition': [const Note(c5, 140, gapMs: 30), const Note(g5, 260)],
  // Waiting for a tap: two gentle low notes.
  'wait': [const Note(e4, 200, gapMs: 60, gain: 0.8), const Note(e4, 200, gain: 0.8)],
  // Last-3-seconds tick: a very short click.
  'tick': [const Note(1500, 45, gain: 0.7)],
  // Session done: an ascending arpeggio.
  'finished': [
    const Note(c5, 140, gapMs: 10),
    const Note(e5, 140, gapMs: 10),
    const Note(g5, 140, gapMs: 10),
    const Note(c6, 500),
  ],
};

void main() {
  final dir = Directory('assets/sounds')..createSync(recursive: true);
  sounds.forEach((name, notes) {
    final file = File('${dir.path}/$name.wav')..writeAsBytesSync(wav(render(notes)));
    stdout.writeln('${file.path} (${file.lengthSync()} bytes)');
  });
}

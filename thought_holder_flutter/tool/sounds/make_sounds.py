import os
import math
import struct
import wave

SAMPLE_RATE = 44100
PEAK_DB = -12.0
BASE_AMP = 32767.0 * (10.0 ** (PEAK_DB / 20.0))  # ~8212 max amplitude

def generate_tone(
    filename,
    frequencies,
    durations,
    style="soft",
    envelope="decay",
    reverb=False,
    volume_scale=1.0,
    bend=False,
):
    """
    Generates a 16-bit mono 44.1 kHz WAV file.
    frequencies: list of Hz (if bend is True, smooth sweep between them)
    durations: list of seconds
    """
    total_duration = sum(durations) if not bend else durations[0]
    total_samples = int(SAMPLE_RATE * total_duration)
    samples = []

    fade_samples = int(SAMPLE_RATE * 0.005)  # 5 ms fade in/out to prevent clicks

    if bend:
        # Smooth pitch bend from frequencies[0] to frequencies[-1]
        f_start = frequencies[0]
        f_end = frequencies[-1]
        dur = durations[0]
        n_samples = int(SAMPLE_RATE * dur)
        phase = 0.0
        for i in range(n_samples):
            t = i / float(SAMPLE_RATE)
            progress = i / float(n_samples)
            freq = f_start + (f_end - f_start) * progress
            phase += 2.0 * math.pi * freq / SAMPLE_RATE

            # Waveform
            val = math.sin(phase)
            if style == "crisp":
                # Add light 2nd harmonic for clarity
                val = 0.8 * val + 0.2 * math.sin(2.0 * phase)

            # Envelope
            decay = math.exp(-3.0 * progress) if envelope == "decay" else 1.0
            amp = BASE_AMP * volume_scale * decay

            # 5ms fade in/out
            if i < fade_samples:
                amp *= (i / float(fade_samples))
            elif i > n_samples - fade_samples:
                amp *= ((n_samples - i) / float(fade_samples))

            sample_int = int(max(-32767, min(32767, val * amp)))
            samples.append(sample_int)
    else:
        # Multi-note sequence
        note_offset = 0
        for note_idx, (freq, dur) in enumerate(zip(frequencies, durations)):
            n_samples = int(SAMPLE_RATE * dur)
            phase = 0.0
            for i in range(n_samples):
                progress = i / float(n_samples)
                phase += 2.0 * math.pi * freq / SAMPLE_RATE

                val = math.sin(phase)
                if style == "crisp":
                    val = 0.82 * val + 0.18 * math.sin(2.0 * phase)

                # Envelope for each note
                decay = math.exp(-3.5 * progress) if envelope == "decay" else 1.0
                amp = BASE_AMP * volume_scale * decay

                # 5ms fade in / out per note
                if i < fade_samples:
                    amp *= (i / float(fade_samples))
                elif i > n_samples - fade_samples:
                    amp *= ((n_samples - i) / float(fade_samples))

                sample_int = int(max(-32767, min(32767, val * amp)))
                samples.append(sample_int)

    # Optional subtle reverb (simple feedback comb filter delay of 25ms, decay 0.2)
    if reverb:
        delay_samples = int(SAMPLE_RATE * 0.025)
        decay_factor = 0.2
        reverbed = list(samples)
        for i in range(delay_samples, len(samples)):
            echo = int(reverbed[i - delay_samples] * decay_factor)
            reverbed[i] = int(max(-32767, min(32767, reverbed[i] + echo)))
        samples = reverbed

    os.makedirs(os.path.dirname(filename), exist_ok=True)
    with wave.open(filename, "w") as wav_file:
        wav_file.setnchannels(1)  # mono
        wav_file.setsampwidth(2)  # 16-bit
        wav_file.setframerate(SAMPLE_RATE)
        data = struct.pack(f"<{len(samples)}h", *samples)
        wav_file.writeframes(data)


def build_all_sounds(base_dir):
    styles = ["soft", "crisp"]

    for st in styles:
        out_dir = os.path.join(base_dir, st)
        dur_mult = 0.85 if st == "crisp" else 1.0

        # 1. Tap: button press (~880 Hz, 50 ms)
        generate_tone(
            os.path.join(out_dir, "tap.wav"),
            [880.0],
            [0.050 * dur_mult],
            style=st,
            volume_scale=0.7,
        )

        # 2. Tab switch / whoosh up-down
        generate_tone(
            os.path.join(out_dir, "tab_switch.wav"),
            [350.0, 600.0, 420.0],
            [0.035 * dur_mult, 0.040 * dur_mult, 0.045 * dur_mult],
            style=st,
            volume_scale=0.6,
        )

        # 3. Popup open (whoosh up)
        generate_tone(
            os.path.join(out_dir, "popup_open.wav"),
            [380.0, 650.0],
            [0.100 * dur_mult],
            style=st,
            bend=True,
            volume_scale=0.65,
        )

        # 4. Popup close (whoosh down)
        generate_tone(
            os.path.join(out_dir, "popup_close.wav"),
            [650.0, 360.0],
            [0.090 * dur_mult],
            style=st,
            bend=True,
            volume_scale=0.6,
        )

        # 5. Switch on (two rising tones: 660 -> 880 Hz)
        generate_tone(
            os.path.join(out_dir, "switch_on.wav"),
            [660.0, 880.0],
            [0.055 * dur_mult, 0.065 * dur_mult],
            style=st,
            volume_scale=0.75,
        )

        # 6. Switch off (two falling tones: 880 -> 660 Hz)
        generate_tone(
            os.path.join(out_dir, "switch_off.wav"),
            [880.0, 660.0],
            [0.055 * dur_mult, 0.065 * dur_mult],
            style=st,
            volume_scale=0.75,
        )

        # 7. Menu open (slightly lower tick ~600 Hz, 50 ms)
        generate_tone(
            os.path.join(out_dir, "menu_open.wav"),
            [600.0],
            [0.050 * dur_mult],
            style=st,
            volume_scale=0.65,
        )

        # 8. Swipe: light slide sound
        generate_tone(
            os.path.join(out_dir, "swipe.wav"),
            [400.0, 520.0],
            [0.075 * dur_mult],
            style=st,
            bend=True,
            volume_scale=0.5,
        )

        # 9. Threshold click: card swipe reaches action threshold
        generate_tone(
            os.path.join(out_dir, "threshold_click.wav"),
            [950.0],
            [0.030 * dur_mult],
            style=st,
            volume_scale=0.6,
        )

        # 10. Save: calm two-note rising chime 523 -> 659 Hz (C5 -> E5)
        generate_tone(
            os.path.join(out_dir, "save.wav"),
            [523.25, 659.25],
            [0.090 * dur_mult, 0.120 * dur_mult],
            style=st,
            reverb=True,
            volume_scale=0.85,
        )

        # 11. Drop: soft plop ~520 Hz downward bend
        generate_tone(
            os.path.join(out_dir, "drop.wav"),
            [520.0, 360.0],
            [0.085 * dur_mult],
            style=st,
            bend=True,
            volume_scale=0.8,
        )

        # 12. Done: pleasant three-note finish 523 -> 659 -> 784 Hz (C5 -> E5 -> G5)
        generate_tone(
            os.path.join(out_dir, "done.wav"),
            [523.25, 659.25, 783.99],
            [0.075 * dur_mult, 0.080 * dur_mult, 0.130 * dur_mult],
            style=st,
            reverb=True,
            volume_scale=0.9,
        )

        # 13. Celebrate: gentle ascending arpeggio 523 -> 659 -> 784 -> 1047 Hz
        generate_tone(
            os.path.join(out_dir, "celebrate.wav"),
            [523.25, 659.25, 783.99, 1046.50],
            [0.065 * dur_mult, 0.065 * dur_mult, 0.070 * dur_mult, 0.140 * dur_mult],
            style=st,
            reverb=True,
            volume_scale=0.8,
        )

        # 14. Trash: soft low whoosh-thud 220 -> 110 Hz, 180 ms
        generate_tone(
            os.path.join(out_dir, "trash.wav"),
            [220.0, 110.0],
            [0.180 * dur_mult],
            style=st,
            bend=True,
            volume_scale=0.85,
        )

        # 15. Delete forever: distinct, lower, slower tone 165 -> 82 Hz, 300 ms
        generate_tone(
            os.path.join(out_dir, "delete_forever.wav"),
            [165.0, 82.0],
            [0.300 * dur_mult],
            style=st,
            bend=True,
            volume_scale=0.9,
        )

        # 16. Undo: reverse of trash 110 -> 220 Hz upward rise, 180 ms
        generate_tone(
            os.path.join(out_dir, "undo.wav"),
            [110.0, 220.0],
            [0.180 * dur_mult],
            style=st,
            bend=True,
            volume_scale=0.85,
        )

        # 17. Error: soft low two-note descending tone 392 -> 330 Hz, 200 ms
        generate_tone(
            os.path.join(out_dir, "error.wav"),
            [392.0, 329.63],
            [0.090 * dur_mult, 0.120 * dur_mult],
            style=st,
            volume_scale=0.8,
        )

        # 18. Key: very quiet tick 1200 Hz, 20 ms
        generate_tone(
            os.path.join(out_dir, "key.wav"),
            [1200.0],
            [0.020 * dur_mult],
            style=st,
            volume_scale=0.35,
        )

        # 19. Key space: 800 Hz, 25 ms
        generate_tone(
            os.path.join(out_dir, "key_space.wav"),
            [800.0],
            [0.025 * dur_mult],
            style=st,
            volume_scale=0.35,
        )

        # 20. Key enter: 1000 -> 1200 Hz, 30 ms
        generate_tone(
            os.path.join(out_dir, "key_enter.wav"),
            [1000.0, 1200.0],
            [0.030 * dur_mult],
            style=st,
            bend=True,
            volume_scale=0.4,
        )

        # 21. Record start: 600 -> 850 Hz before mic opens
        generate_tone(
            os.path.join(out_dir, "record_start.wav"),
            [600.0, 850.0],
            [0.055 * dur_mult, 0.070 * dur_mult],
            style=st,
            volume_scale=0.75,
        )

        # 22. Record saved: 850 -> 600 Hz after mic closes
        generate_tone(
            os.path.join(out_dir, "record_saved.wav"),
            [850.0, 600.0],
            [0.065 * dur_mult, 0.080 * dur_mult],
            style=st,
            volume_scale=0.75,
        )

    print("Successfully built all sound files in:", base_dir)

if __name__ == "__main__":
    out = os.path.join(os.path.dirname(__file__), "..", "..", "assets", "sounds")
    build_all_sounds(os.path.abspath(out))

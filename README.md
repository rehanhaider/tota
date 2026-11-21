# Tota

Tota is a Mac app that speaks any text in your own voice. It clones your voice from a short recording, and it runs entirely on your Mac with no cloud service.

*Tota* means parrot in Hindi and Urdu.

It uses [Maya 2 Native](https://huggingface.co/maya-research/maya2-native) through [mlx-audio](https://github.com/Blaizzy/mlx-audio). Maya 2 was trained on English and 11 Indian languages, so it keeps Indian accents better than most open voice-cloning models.

## What it does

- **Voices.** Record yourself or import an audio file, then pick the part to use. Whisper transcribes it, and you can fix any words it got wrong.
- **Settings.** Every setting the model takes is in the side panel, with a plain explanation of what it does.
- **Takes.** Every take is saved with the exact settings and seed that made it. You can play your sample and a take back to back to compare them. "Use These Settings" brings back any take's settings.
- **Presets.** Save settings you like under a name.
- **Repeatable results.** With a fixed seed, the same text and settings give the same take. Change one setting and you hear only that change.
- **Long text.** Long text is split into chunks. If a chunk runs on past the end of its text, Tota generates it again.

## Requirements

- A Mac with Apple Silicon, running macOS 15 or later.
- Xcode, or the Swift 6 command line tools, to build the app.
- [uv](https://docs.astral.sh/uv/), to install mlx-audio.
- About 7 GB of free disk space for the models. Maya 2 is 5.4 GB, counting its audio codec and speaker encoder, and Whisper is 1.6 GB.

## Setup

1. Install mlx-audio as a uv tool. Tota was tested with version 0.6.7.

   ```sh
   uv tool install mlx-audio
   ```

   Tota expects mlx-audio's Python at `~/.local/share/uv/tools/mlx-audio/bin/python`, which is where `uv tool install` puts it.

2. Download the models. Tota runs offline, so it won't download them itself. Maya 2 needs two extra models: an audio codec, used for every take, and a speaker encoder, used by the `spk` and `icl_spk` modes.

   ```sh
   PY=~/.local/share/uv/tools/mlx-audio/bin/python
   $PY -c "from mlx_audio.tts.utils import load; load('maya-research/maya2-native')"
   $PY -c "from mlx_audio.codec.models.mimi import Mimi; Mimi.from_pretrained('kyutai/moshiko-pytorch-bf16', 'tokenizer-e351c8d8-checkpoint125.safetensors')"
   $PY -c "from mlx_audio.codec.models.ecapa_tdnn.speaker import EcapaSpeakerEmbeddingExtractor; EcapaSpeakerEmbeddingExtractor.from_pretrained('aufklarer/SpeechBrain-ECAPA-VoxCeleb-20M-MLX')"
   $PY -c "from mlx_audio.stt.utils import load; load('mlx-community/whisper-large-v3-turbo-asr-fp16')"
   ```

3. Build Tota and install it to `~/Applications/Tota.app`:

   ```sh
   ./build.sh
   ```

4. Open Tota. To get started, click New Voice… and record yourself.

## Getting a good clone

- **Talk freely, don't read.** Tota copies how you speak in the sample. A read-aloud sample gives a read-aloud clone.
- **Keep the sample short.** Record 30 to 60 seconds, then pick the best 5 to 15 seconds. Maya's makers recommend 3 to 10.
- **Match the words exactly.** The transcript has to match exactly what you say in the sample.
- **Start with icl mode at temperature 0.4.** These were the closest settings in testing. Raise the temperature for a livelier delivery, or lower it for a steadier one.
- **Compare on the same words.** "Use Sample's Words" fills in the words from your sample, so you can hear the clone and your own recording side by side.

## How it works

The app is SwiftUI. It starts `backend/worker.py` with mlx-audio's Python and keeps it running, so the model stays loaded between takes. The app and the helper exchange one JSON message per line over stdin and stdout.

Your voices, takes and presets are stored in `~/Music/tota`.

## Use it responsibly

Only clone voices you have permission to use, starting with your own.

## License

Tota is released under the [MIT license](LICENSE). The models it uses have their own licenses. Maya 2 Native is Apache 2.0, its Mimi audio codec from Kyutai is CC BY 4.0, its SpeechBrain ECAPA speaker encoder is Apache 2.0, and Whisper is MIT.

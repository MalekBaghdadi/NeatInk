---
license: mit
datasets:
- PellelNitram/xournalpp_htr_IAM_DB
---
# SimpleHTR — Word-Level Handwritten Text Recognition

A word-recognition model that reads individual handwritten words from
cropped images. It takes a single word image and predicts the text.
Part of the [Xournal++ HTR](https://github.com/PellelNitram/xournalpp_htr)
project.

## Model details

| Property | Value |
|---|---|
| Architecture | 5 CNN layers + 2 bidirectional LSTM layers + CTC output |
| Input | Grayscale image, resized to 128×32 (uniform scale, centered) |
| Output | CTC log-probabilities (seq_len × num_classes) |
| Decoding | Greedy best-path |
| Format | ONNX (opset 17) |
| Parameters | ~3.2M |
| Training data | [IAM Handwriting Database](https://huggingface.co/datasets/PellelNitram/xournalpp_htr_IAM_DB) |
| Best val CER | 0.056 (5.6%) |
| Best val word accuracy | 84.2% |
| License | MIT |

## Usage

```python
from xournalpp_htr.inference_models import SimpleHTRModel

model = SimpleHTRModel.from_pretrained()
text = model.recognize(word_image_grayscale)  # str
```

Requires `pip install xournalpp-htr` (pulls `onnxruntime` and
`huggingface-hub`, no PyTorch needed).

## How it works

The model processes a grayscale word image through:

1. **CNN encoder** (5 layers): extracts visual features, reducing height to 1
   and width to 32 timesteps via batch norm + ReLU + max pooling.
2. **Bidirectional LSTM** (2 layers, hidden=256): models sequential
   dependencies across timesteps.
3. **CTC output layer**: projects to character probabilities at each timestep.
4. **Greedy decoding**: collapses repeated characters and removes blanks.

Input images are resized with uniform scaling (preserving aspect ratio) and
centered on a white 128×32 canvas, then normalised to [-0.5, 0.5].

## Training

Trained on the IAM Handwriting Database (word-level, 95/5 random split).
Best configuration found via grid search over 3 experiments:

| Hyperparameter | Value |
|---|---|
| Optimizer | Adam |
| Learning rate | 0.0005 |
| Batch size | 64 |
| Dropout | 0.5 |
| Data augmentation | Enabled (blur, geometric, morphological, contrast) |
| Max epochs | 200 |
| Early stopping patience | 25 |

Full training instructions and experiment logs:
[docs/models/simple_htr.md](https://github.com/PellelNitram/xournalpp_htr/blob/master/docs/models/simple_htr.md).

## Intended use

This model is the recognition stage in a handwriting recognition pipeline,
following a word detector that crops individual words. It is designed to run
on personal devices (laptops, edge) via ONNX Runtime — no GPU required for
inference.

## Limitations

- Single-word recognition only — expects a pre-cropped word image.
- Greedy CTC decoding (no language model); beam search could improve results.
- Grayscale input required.
- Trained on IAM handwriting; performance on other styles may vary.
- 78-character charset (English letters, digits, punctuation) — does not
  support non-Latin scripts.

## Citation

The architecture is based on
[SimpleHTR](https://github.com/githubharald/SimpleHTR) by
[Harald Scheidl](https://github.com/githubharald).
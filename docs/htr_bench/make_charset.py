"""Builds assets/htr/charset.json from the inference.yml of the PP-OCRv5 model.

Usage: python -I make_charset.py <inference.yml> <out charset.json>

The model's classes are: 0 = CTC blank, 1..436 = `character_dict` in file order,
437 = space. The yml is parsed with PyYAML (pip install --user pyyaml): the
dictionary contains quote and backslash characters that a hand-written parser
gets wrong. Output is ASCII-only JSON (\\uXXXX escapes), 16 entries per line.
"""
import json
import sys

import yaml


def main(src, dst):
    with open(src, encoding="utf-8") as f:
        cd = yaml.safe_load(f)["PostProcess"]["character_dict"]
    assert len(cd) == 436 and all(isinstance(c, str) and len(c) == 1 for c in cd), len(cd)
    chars = [""] + cd + [" "]
    rows = []
    for i in range(0, len(chars), 16):
        rows.append("    " + ", ".join(json.dumps(c, ensure_ascii=True) for c in chars[i : i + 16]))
    text = (
        "{\n"
        '  "model": "en_PP-OCRv5_mobile_rec",\n'
        '  "source": "PaddlePaddle/en_PP-OCRv5_mobile_rec_onnx inference.yml, '
        'PostProcess.character_dict (436 characters)",\n'
        '  "blank": 0,\n'
        '  "space": 437,\n'
        '  "classes": 438,\n'
        '  "charset": [\n' + ",\n".join(rows) + "\n  ]\n}\n"
    )
    with open(dst, "w", encoding="utf-8", newline="\n") as f:
        f.write(text)
    with open(dst, encoding="utf-8") as f:
        assert json.load(f)["charset"] == chars
    print("wrote", dst, len(chars), "classes")


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    main(sys.argv[1], sys.argv[2])

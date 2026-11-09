"""Prepare local, vehicle-separated front-part detection data.

Input is a JSON array of objects with image, vehicle_group, split and boxes.
Boxes use normalized [left, top, right, bottom] on the EXIF-oriented image.
Every visible target must be labeled. An empty boxes object is a reviewed
negative. Left and right refer to the vehicle's direction of travel.
"""

import argparse
import hashlib
import json
import tempfile
from pathlib import Path

from PIL import Image, ImageOps


PARTS = ("hood", "leftLamp", "grille", "rightLamp", "bumper")
SPLITS = ("train", "val", "test")
IMAGE_SUFFIXES = {".jpg", ".jpeg", ".png", ".webp"}


def labels_for(boxes):
    if not isinstance(boxes, dict) or boxes.keys() - set(PARTS):
        raise ValueError("boxes must contain only recognized front-part names")
    lines = []
    for index, part in enumerate(PARTS):
        if part not in boxes:
            continue
        box = boxes[part]
        if (
            not isinstance(box, list)
            or len(box) != 4
            or any(type(x) not in (int, float) or not 0 <= x <= 1 for x in box)
        ):
            raise ValueError(f"{part}: box must have four normalized coordinates")
        left, top, right, bottom = box
        if left >= right or top >= bottom:
            raise ValueError(f"{part}: box must have a positive area")
        coordinates = ((left + right) / 2, (top + bottom) / 2, right - left, bottom - top)
        lines.append(f"{index} " + " ".join(format(value, ".12g") for value in coordinates))
    return "".join(line + "\n" for line in lines)


def prepare(manifest, photo_root, output):
    repo = Path(__file__).resolve().parents[1]
    private = (repo / "private").resolve()
    output = output.resolve()
    if not output.is_relative_to(private) or output == private or output.exists():
        raise ValueError("choose a new output directory inside the project's private folder")
    photo_root = photo_root.resolve(strict=True)
    entries = json.loads(manifest.read_text(encoding="utf-8"))
    if not isinstance(entries, list) or not entries:
        raise ValueError("provide a nonempty JSON array of reviewed annotations")

    groups = {}
    coverage = {split: dict.fromkeys(PARTS, 0) for split in SPLITS}
    counts = dict.fromkeys(SPLITS, 0)
    validated = []
    seen_paths = set()
    for index, entry in enumerate(entries, 1):
        if not isinstance(entry, dict):
            raise ValueError(f"entry {index}: expected an object")
        name, group, split = (entry.get(key) for key in ("image", "vehicle_group", "split"))
        if (
            not isinstance(name, str)
            or Path(name).is_absolute()
            or not isinstance(group, str)
            or not group.strip()
            or split not in SPLITS
        ):
            raise ValueError(f"entry {index}: expected a relative image, vehicle_group and split")
        path = (photo_root / name).resolve()
        if (
            not path.is_relative_to(photo_root)
            or path.suffix.lower() not in IMAGE_SUFFIXES
            or not path.is_file()
            or path in seen_paths
        ):
            raise ValueError(f"entry {index}: missing, duplicate or out-of-folder image")
        group = group.strip()
        if groups.setdefault(group, split) != split:
            raise ValueError(f"entry {index}: the same vehicle group crosses dataset splits")
        boxes = entry.get("boxes")
        labels = labels_for(boxes)
        for part in boxes:
            coverage[split][part] += 1
        counts[split] += 1
        seen_paths.add(path)
        validated.append((path, split, labels))

    for split, parts in coverage.items():
        missing = [part for part, count in parts.items() if count == 0]
        if missing:
            raise ValueError(f"{split}: no labeled examples for {', '.join(missing)}")

    output.parent.mkdir(parents=True, exist_ok=True)
    seen_pixels = set()
    with tempfile.TemporaryDirectory(dir=output.parent, prefix=".front-dataset-") as work:
        staged = Path(work) / "dataset"
        for split in SPLITS:
            (staged / "images" / split).mkdir(parents=True)
            (staged / "labels" / split).mkdir(parents=True)
        for index, (path, split, labels) in enumerate(validated, 1):
            with Image.open(path) as original:
                image = ImageOps.exif_transpose(original).convert("RGB")
                identity = hashlib.sha256(
                    f"{image.width}x{image.height}:".encode() + image.tobytes()
                ).digest()
                if identity in seen_pixels:
                    raise ValueError(f"entry {index}: duplicate image pixels")
                seen_pixels.add(identity)
                image.info.clear()
                image.save(staged / "images" / split / f"{index:06d}.jpg", quality=95)
            (staged / "labels" / split / f"{index:06d}.txt").write_text(
                labels, encoding="utf-8"
            )
        yaml = [f"path: {json.dumps(str(output), ensure_ascii=False)}"]
        yaml.extend(f"{split}: images/{split}" for split in SPLITS)
        yaml.append("names:")
        yaml.extend(f"  {index}: {part}" for index, part in enumerate(PARTS))
        (staged / "data.yaml").write_text("\n".join(yaml) + "\n", encoding="utf-8")
        report = {
            "images": counts,
            "vehicle_groups": {split: list(groups.values()).count(split) for split in SPLITS},
            "part_counts": coverage,
        }
        (staged / "summary.json").write_text(
            json.dumps(report, indent=2) + "\n", encoding="utf-8"
        )
        staged.rename(output)
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("manifest", type=Path)
    parser.add_argument("photo_root", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    try:
        print(json.dumps(prepare(args.manifest, args.photo_root, args.output), indent=2))
    except (OSError, ValueError) as error:
        parser.exit(2, f"Dataset rejected: {error}\n")


if __name__ == "__main__":
    main()

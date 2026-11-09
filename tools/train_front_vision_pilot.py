"""Train and evaluate a small five-part detector on a prepared local dataset."""
import argparse
import json
import random
from pathlib import Path

import numpy as np
from PIL import Image, ImageEnhance
import torch
from torch import nn
from torch.nn import functional as F
from torch.utils.data import DataLoader, Dataset

from prepare_front_vision_dataset import PARTS

SIZE = 128
N_PARTS = len(PARTS)
FLIPPED = (0, 3, 2, 1, 4)
THRESHOLDS = (.15, .25, .35, .45, .55, .65)


class FrontPhotos(Dataset):
    def __init__(self, root, split, size=SIZE):
        self.images = sorted((root / 'images' / split).glob('*.jpg'))
        self.labels = root / 'labels' / split
        self.training = split == 'train'
        self.size = size

    def __len__(self):
        return len(self.images)

    def __getitem__(self, index):
        path = self.images[index]
        with Image.open(path) as original:
            photo = original.convert('RGB').resize((self.size, self.size), Image.Resampling.BILINEAR)
        boxes = np.zeros((N_PARTS, 4), dtype=np.float32)
        for line in (self.labels / f'{path.stem}.txt').read_text().splitlines():
            part, *box = line.split()
            boxes[int(part)] = [float(v) for v in box]
        if self.training:
            photo, boxes = augment(photo, boxes)
        pixels = np.asarray(photo, dtype=np.float32).transpose(2, 0, 1) / 255
        return torch.from_numpy(pixels), torch.from_numpy(boxes)


def augment(photo, boxes):
    present = boxes[:, 2] > 0
    if random.random() < .5:
        photo = photo.transpose(Image.Transpose.FLIP_LEFT_RIGHT)
        boxes[present, 0] = 1 - boxes[present, 0]
        boxes = boxes[list(FLIPPED)]
        present = boxes[:, 2] > 0
    size = photo.width
    scale = random.uniform(.83, 1.12)
    shift = np.array([random.uniform(-.12, .12) for _ in range(2)])
    photo = photo.transform(
        photo.size,
        Image.Transform.AFFINE,
        (1 / scale, 0, size * (.5 - (.5 + shift[0]) / scale),
         0, 1 / scale, size * (.5 - (.5 + shift[1]) / scale)),
        Image.Resampling.BILINEAR,
        fillcolor=(108, 108, 108),
    )
    centers = (boxes[:, :2] - .5) * scale + .5 + shift
    half = boxes[:, 2:] * scale / 2
    low, high = (centers - half).clip(0, 1), (centers + half).clip(0, 1)
    sizes = high - low
    keep = present & np.all(sizes >= half, axis=1)
    boxes[keep, :2] = (low[keep] + high[keep]) / 2
    boxes[keep, 2:] = sizes[keep]
    boxes[~keep] = 0
    photo = ImageEnhance.Brightness(photo).enhance(random.uniform(.72, 1.23))
    photo = ImageEnhance.Color(photo).enhance(random.uniform(.66, 1.25))
    return photo, boxes


class Detector(nn.Module):
    def __init__(self):
        super().__init__()
        blocks = []
        for a, b, stride in [(3, 16, 2), (16, 24, 2), (24, 40, 2),
                             (40, 64, 1), (64, 64, 1), (64, 64, 1)]:
            blocks.extend([nn.Conv2d(a, b, 3, stride, 1, bias=False),
                           nn.BatchNorm2d(b), nn.ReLU()])
        self.features = nn.Sequential(*blocks)
        self.heatmap = nn.Conv2d(64, N_PARTS, 1)
        self.box = nn.Conv2d(64, N_PARTS * 4, 1)
        nn.init.constant_(self.heatmap.bias, -2.)

    def forward(self, image):
        features = self.features(image)
        return self.heatmap(features), self.box(features).unflatten(1, (N_PARTS, 4))


def loss(model, image, boxes, lamp_weight=1.):
    heat, raw = model(image)
    batch, part = (boxes[:, :, 2] > 0).nonzero(as_tuple=True)
    grid = heat.shape[-1]
    weights = heat.new_tensor([1., lamp_weight, 1., lamp_weight, 1.])
    target = torch.zeros_like(heat)
    dimensions = heat.new_zeros(())
    if len(part):
        box = boxes[batch, part]
        cell = (box[:, :2] * grid).floor().long().clamp(0, grid - 1)
        x, y = cell.unbind(dim=1)
        target[batch, part, y, x] = 1
        desired = torch.cat((box[:, :2] * grid - cell, box[:, 2:]), dim=1)
        prediction = raw[batch, part, :, y, x].sigmoid()
        box_loss = F.smooth_l1_loss(prediction, desired, reduction='none').mean(dim=1)
        if lamp_weight != 1.:
            # A few pixels of size error matter more for the smaller lamp boxes.
            relative_size = F.smooth_l1_loss(
                prediction[:, 2:].clamp(min=1e-5).log(),
                desired[:, 2:].clamp(min=1e-5).log(),
                reduction='none',
            ).mean(dim=1)
            box_loss = box_loss + .08 * relative_size
        dimensions = (box_loss * weights[part]).sum() / weights[part].sum()
    probability = heat.sigmoid()
    confidence = F.binary_cross_entropy_with_logits(heat, target, reduction='none')
    modulation = torch.where(target.bool(), (1 - probability) ** 2, probability ** 2)
    return (confidence * modulation * weights[None, :, None, None]).sum() / max(len(part), 1) + 8 * dimensions


def predict(model, image):
    heat, raw = model(image)
    scores, cells = heat.sigmoid().flatten(2).max(dim=2)
    rows = raw.flatten(3)
    value = rows.gather(3, cells[:, :, None, None].expand(-1, -1, 4, 1)).squeeze(3).sigmoid()
    grid = heat.shape[-1]
    centers = (value[:, :, :2] + torch.stack((cells % grid, cells // grid), dim=2)) / grid
    return scores, torch.cat((centers, value[:, :, 2:]), dim=2)


def evaluate(model, loader):
    scores, overlaps, present = [], [], []
    model.eval()
    with torch.inference_mode():
        for images, truth in loader:
            confidence, predicted = predict(model, images)
            a, b = predicted[..., 2:] / 2, truth[..., 2:] / 2
            lo = torch.maximum(predicted[..., :2] - a, truth[..., :2] - b)
            hi = torch.minimum(predicted[..., :2] + a, truth[..., :2] + b)
            intersection = (hi - lo).clamp(min=0).prod(dim=2)
            union = predicted[..., 2:].prod(dim=2) + truth[..., 2:].prod(dim=2) - intersection
            overlaps.append(intersection / union.clamp(min=1e-8))
            present.append(truth[..., 2] > 0)
            scores.append(confidence)
    return tuple(torch.cat(values) for values in (scores, overlaps, present))


def metrics(result, threshold):
    scores, overlaps, present = result
    predicted = scores >= threshold
    correct = predicted & present & (overlaps >= .5)
    tp, detections, actual = int(correct.sum()), int(predicted.sum()), int(present.sum())
    return {
        'true_positives': tp, 'predictions': detections, 'actual': actual,
        'precision': tp / max(1, detections), 'recall': tp / max(1, actual),
        'f1': 2 * tp / max(1, detections + actual),
        'mean_iou': float(overlaps[present].mean()) if actual else 0.,
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('dataset', type=Path)
    parser.add_argument('output', type=Path)
    parser.add_argument('--epochs', type=int, default=90)
    parser.add_argument('--image-size', type=int, choices=(128, 192, 256), default=SIZE)
    parser.add_argument('--lamp-weight', type=float, choices=(1., 2., 3.), default=1.)
    args = parser.parse_args()
    private = (Path(__file__).resolve().parents[1] / 'private').resolve()
    dataset, output = args.dataset.resolve(), args.output.resolve()
    if not dataset.is_relative_to(private) or not output.is_relative_to(private) or output == private:
        parser.error('dataset and model output must stay under private/')
    if args.epochs < 1:
        parser.error('epochs must be positive')
    random.seed(147)
    torch.manual_seed(147)
    torch.set_num_threads(4)
    model = Detector()
    train, val, test = [
        DataLoader(FrontPhotos(dataset, split, args.image_size), batch_size=8, shuffle=split == 'train')
        for split in ('train', 'val', 'test')
    ]
    if min(len(train.dataset), len(val.dataset), len(test.dataset)) == 0:
        parser.error('all three splits must contain photos')
    output.mkdir(parents=True, exist_ok=False)
    optimizer = torch.optim.AdamW(model.parameters(), lr=.002)
    schedule = torch.optim.lr_scheduler.CosineAnnealingLR(optimizer, args.epochs)
    best, threshold = (-1., -1.), THRESHOLDS[0]
    for epoch in range(args.epochs):
        model.train()
        for images, boxes in train:
            optimizer.zero_grad()
            cost = loss(model, images, boxes, args.lamp_weight)
            cost.backward()
            optimizer.step()
        schedule.step()
        result = evaluate(model, val)
        for candidate in THRESHOLDS:
            stats = metrics(result, candidate)
            score = (stats['f1'], stats['mean_iou'])
            if score > best:
                best, threshold = score, candidate
                torch.save(model.state_dict(), output / 'weights.pt')
        if epoch == 0 or (epoch + 1) % 10 == 0:
            print(f'epoch={epoch + 1} best_val_f1={best[0]:.3f} loss={float(cost.detach()):.3f}', flush=True)

    model.load_state_dict(torch.load(output / 'weights.pt', weights_only=True))
    result = evaluate(model, test)
    report = {
        'image_size': args.image_size,
        'lamp_weight': args.lamp_weight,
        'threshold_selected_on_validation': threshold,
        'best_validation_f1': best[0],
        'test': metrics(result, threshold),
        'test_by_part': {
            part: metrics(tuple(t[:, i] for t in result), threshold)
            for i, part in enumerate(PARTS)
        },
    }
    (output / 'evaluation.json').write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps(report, indent=2))


if __name__ == '__main__':
    main()

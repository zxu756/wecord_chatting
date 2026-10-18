// Cuts the subject out of a picture in the browser, for personal stickers
// (lib/features/stickers/sticker_cutout_web.dart).
//
// It uses the segmentation the camera's background blur already uses: the
// pinned MediaPipe vision bundle (mapped to "@mediapipe/tasks-vision" by the
// import map in web/index.html, the same version the blur loads) and the same
// selfie segmenter model. They are fetched the first time and cached by the
// browser. The picture is read, segmented and drawn in this page; nothing is
// uploaded.
//
// cutOut(bytes: Uint8Array) -> Promise<Uint8Array>
//   a PNG of the subject, cropped to it, with a soft edge and everything else
//   transparent. Rejects with Error('no_subject') when the model finds no
//   person, and with Error('unreadable') when the browser cannot open the
//   picture.
import { FilesetResolver, ImageSegmenter } from '@mediapipe/tasks-vision';

const WASM_URL =
  'https://cdn.jsdelivr.net/npm/@mediapipe/tasks-vision@0.10.14/wasm';
const MODEL_URL =
  'https://storage.googleapis.com/mediapipe-models/image_segmenter/selfie_segmenter/float16/latest/selfie_segmenter.tflite';

// The long side the segmentation runs on; stickers are 512 at most.
const MAX_EDGE = 1024;
// A person fills at least this share of the picture, or "no subject".
const MIN_COVERAGE = 0.01;

let segmenterPromise = null;

function segmenter() {
  if (!segmenterPromise) {
    segmenterPromise = (async () => {
      const fileset = await FilesetResolver.forVisionTasks(WASM_URL);
      const options = {
        baseOptions: { modelAssetPath: MODEL_URL },
        runningMode: 'IMAGE',
        outputCategoryMask: false,
        outputConfidenceMasks: true,
      };
      try {
        return await ImageSegmenter.createFromOptions(fileset, {
          ...options,
          baseOptions: { ...options.baseOptions, delegate: 'GPU' },
        });
      } catch (_) {
        // No WebGL: the CPU path is slower but works.
        return await ImageSegmenter.createFromOptions(fileset, options);
      }
    })().catch((error) => {
      segmenterPromise = null;
      throw error;
    });
  }
  return segmenterPromise;
}

function drawingSurface(width, height) {
  if (typeof OffscreenCanvas !== 'undefined') {
    return new OffscreenCanvas(width, height);
  }
  const canvas = document.createElement('canvas');
  canvas.width = width;
  canvas.height = height;
  return canvas;
}

async function openPicture(bytes) {
  try {
    return await createImageBitmap(new Blob([bytes]));
  } catch (_) {
    throw new Error('unreadable');
  }
}

function smoothstep(low, high, value) {
  const t = Math.min(1, Math.max(0, (value - low) / (high - low)));
  return t * t * (3 - 2 * t);
}

// The foreground confidence of each pixel, 0..1, at the picture's size.
function foregroundConfidence(result) {
  const masks = result.confidenceMasks;
  if (!masks || masks.length === 0) {
    throw new Error('failed');
  }
  // The selfie segmenter has one class, the person; with two the person is
  // the last.
  const mask = masks[masks.length - 1];
  return { values: mask.getAsFloat32Array(), width: mask.width, height: mask.height };
}

export async function cutOut(bytes) {
  const bitmap = await openPicture(bytes);
  try {
    const scale = Math.min(1, MAX_EDGE / Math.max(bitmap.width, bitmap.height));
    const width = Math.max(1, Math.round(bitmap.width * scale));
    const height = Math.max(1, Math.round(bitmap.height * scale));

    const canvas = drawingSurface(width, height);
    const context = canvas.getContext('2d', { willReadFrequently: true });
    context.drawImage(bitmap, 0, 0, width, height);
    const picture = context.getImageData(0, 0, width, height);

    const segmentation = await segmenter();
    const result = segmentation.segment(canvas);
    let mask;
    try {
      mask = foregroundConfidence(result);
    } finally {
      // The values are copied by getAsFloat32Array only until close().
      result.close?.();
    }

    // Soft edge: confidence 0.35..0.65 fades from clear to solid.
    const pixels = picture.data;
    let left = width;
    let top = height;
    let right = -1;
    let bottom = -1;
    let covered = 0;
    for (let y = 0; y < height; y++) {
      const maskY = Math.min(mask.height - 1, Math.floor((y * mask.height) / height));
      for (let x = 0; x < width; x++) {
        const maskX = Math.min(mask.width - 1, Math.floor((x * mask.width) / width));
        const alpha = smoothstep(0.35, 0.65, mask.values[maskY * mask.width + maskX]);
        const index = (y * width + x) * 4;
        pixels[index + 3] = Math.round(alpha * pixels[index + 3]);
        if (alpha > 0.5) {
          covered++;
          if (x < left) left = x;
          if (x > right) right = x;
          if (y < top) top = y;
          if (y > bottom) bottom = y;
        }
      }
    }
    if (covered / (width * height) < MIN_COVERAGE) {
      throw new Error('no_subject');
    }

    // Crop to the subject, with a little air around it.
    const pad = 4;
    left = Math.max(0, left - pad);
    top = Math.max(0, top - pad);
    right = Math.min(width - 1, right + pad);
    bottom = Math.min(height - 1, bottom + pad);
    const cropWidth = right - left + 1;
    const cropHeight = bottom - top + 1;
    context.putImageData(picture, 0, 0);
    const output = drawingSurface(cropWidth, cropHeight);
    output.getContext('2d').drawImage(
      canvas, left, top, cropWidth, cropHeight, 0, 0, cropWidth, cropHeight);

    const blob = output.convertToBlob
      ? await output.convertToBlob({ type: 'image/png' })
      : await new Promise((resolve, reject) =>
          output.toBlob((value) => (value ? resolve(value) : reject(new Error('failed'))), 'image/png'));
    return new Uint8Array(await blob.arrayBuffer());
  } finally {
    bitmap.close?.();
  }
}

import 'dart:math' as math;

import 'package:flutter/painting.dart';

/// [provider] decoded no larger than it takes to cover a [box] of logical
/// pixels on a screen with [devicePixelRatio].
///
/// A picture is decoded to its full size unless told otherwise: a photo
/// 2560 pixels long is ~20 MB in memory, to be drawn in a 250 pixel tile,
/// and the image cache (100 MB) holds five of them, so scrolling a chat of
/// photos decodes the same pictures again and again. [sourceWidth] and
/// [sourceHeight] are the picture's own size (a message knows it); without
/// them nothing is known about how far it can shrink and [provider] is
/// returned as it is.
///
/// The decoded picture keeps its proportions and covers the box in both
/// directions (for `BoxFit.cover`), and is never scaled up.
ImageProvider imageDecodedFor(
  ImageProvider provider, {
  required Size box,
  required double devicePixelRatio,
  required int? sourceWidth,
  required int? sourceHeight,
}) {
  if (sourceWidth == null ||
      sourceHeight == null ||
      sourceWidth <= 0 ||
      sourceHeight <= 0 ||
      !box.isFinite ||
      box.isEmpty ||
      devicePixelRatio <= 0) {
    return provider;
  }
  final cover = math.max(box.width / sourceWidth, box.height / sourceHeight);
  final width = (sourceWidth * cover * devicePixelRatio).ceil();
  if (width >= sourceWidth) {
    return provider;
  }
  return ResizeImage(provider, width: math.max(1, width));
}

/// [image] decoded for a square avatar of [size] logical pixels. Avatars are
/// stored as they were picked (a camera photo is millions of pixels), and
/// every avatar of a long member list would be decoded in full. The width
/// has room for a picture that is not square (it covers the avatar up to
/// 2:1) and the proportions are kept.
ImageProvider avatarImageFor(
  ImageProvider image, {
  required double size,
  required double devicePixelRatio,
}) {
  if (image is ResizeImage || size <= 0 || devicePixelRatio <= 0) {
    return image;
  }
  return ResizeImage(
    image,
    width: math.max(1, (size * devicePixelRatio * 2).ceil()),
  );
}

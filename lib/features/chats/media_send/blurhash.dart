import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// BlurHash (https://blurha.sh): a 20-30 character string describing a
/// blurry version of a picture. Messages carry one so the picture's place
/// shows its colours at once and the real picture fades in over it.
///
/// Pure Dart, no package: [encode] turns RGBA pixels into a hash,
/// [decode] turns a hash back into RGBA pixels, and [BlurHashView] draws it.
abstract final class BlurHash {
  static const _alphabet =
      '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz'
      '#\$%*+,-.:;=?@[]^_{|}~';

  /// The number of colour components to use for a picture of this shape:
  /// 4 along the long side and 3 along the short one.
  static (int, int) componentsFor(int width, int height) {
    if (width == height) {
      return (3, 3);
    }
    return width > height ? (4, 3) : (3, 4);
  }

  /// Hashes [rgba] (4 bytes per pixel, row by row). Keep the picture small
  /// (32 pixels on the long side is plenty): the cost grows with the
  /// pixel count.
  static String encode(
    Uint8List rgba, {
    required int width,
    required int height,
    int componentsX = 4,
    int componentsY = 3,
  }) {
    if (width <= 0 || height <= 0 || rgba.length < width * height * 4) {
      throw ArgumentError('The pixels do not match $width x $height');
    }
    if (componentsX < 1 ||
        componentsX > 9 ||
        componentsY < 1 ||
        componentsY > 9) {
      throw ArgumentError('Components must be between 1 and 9');
    }
    final factors = <List<double>>[];
    for (var y = 0; y < componentsY; y++) {
      for (var x = 0; x < componentsX; x++) {
        factors.add(_basisFactor(rgba, width, height, x, y));
      }
    }
    final dc = factors.first;
    final ac = factors.skip(1).toList();

    final hash = StringBuffer();
    hash.write(_encode83((componentsX - 1) + (componentsY - 1) * 9, 1));

    double maximumValue;
    if (ac.isNotEmpty) {
      var actualMaximum = 0.0;
      for (final factor in ac) {
        for (final value in factor) {
          actualMaximum = math.max(actualMaximum, value.abs());
        }
      }
      final quantised = (actualMaximum * 166 - 0.5).floor().clamp(0, 82);
      maximumValue = (quantised + 1) / 166;
      hash.write(_encode83(quantised, 1));
    } else {
      maximumValue = 1;
      hash.write(_encode83(0, 1));
    }

    hash.write(_encode83(_encodeDc(dc), 4));
    for (final factor in ac) {
      hash.write(_encode83(_encodeAc(factor, maximumValue), 2));
    }
    return hash.toString();
  }

  /// Whether [hash] is a well-formed BlurHash.
  static bool isValid(String? hash) {
    if (hash == null || hash.length < 6) {
      return false;
    }
    for (var i = 0; i < hash.length; i++) {
      if (!_alphabet.contains(hash[i])) {
        return false;
      }
    }
    final flag = _decode83(hash.substring(0, 1));
    final componentsY = flag ~/ 9 + 1;
    final componentsX = flag % 9 + 1;
    return hash.length == 4 + 2 * componentsX * componentsY;
  }

  /// RGBA pixels (opaque) of the blurry picture, [width] x [height].
  static Uint8List decode(
    String hash, {
    required int width,
    required int height,
    double punch = 1,
  }) {
    if (!isValid(hash)) {
      throw ArgumentError.value(hash, 'hash', 'Not a BlurHash');
    }
    final flag = _decode83(hash.substring(0, 1));
    final componentsY = flag ~/ 9 + 1;
    final componentsX = flag % 9 + 1;
    final maximumValue = (_decode83(hash.substring(1, 2)) + 1) / 166;

    final colors = <List<double>>[];
    for (var i = 0; i < componentsX * componentsY; i++) {
      if (i == 0) {
        colors.add(_decodeDc(_decode83(hash.substring(2, 6))));
      } else {
        colors.add(
          _decodeAc(
            _decode83(hash.substring(4 + i * 2, 6 + i * 2)),
            maximumValue * punch,
          ),
        );
      }
    }

    final pixels = Uint8List(width * height * 4);
    var offset = 0;
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        var r = 0.0;
        var g = 0.0;
        var b = 0.0;
        for (var j = 0; j < componentsY; j++) {
          for (var i = 0; i < componentsX; i++) {
            final basis =
                math.cos(math.pi * x * i / width) *
                math.cos(math.pi * y * j / height);
            final color = colors[i + j * componentsX];
            r += color[0] * basis;
            g += color[1] * basis;
            b += color[2] * basis;
          }
        }
        pixels[offset++] = _linearToSrgb(r);
        pixels[offset++] = _linearToSrgb(g);
        pixels[offset++] = _linearToSrgb(b);
        pixels[offset++] = 255;
      }
    }
    return pixels;
  }

  /// The picture's average colour, which is all the hash's first four
  /// characters after the header hold; null for an invalid hash.
  static Color? averageColor(String? hash) {
    if (!isValid(hash)) {
      return null;
    }
    final value = _decode83(hash!.substring(2, 6));
    return Color.fromARGB(255, value >> 16, (value >> 8) & 255, value & 255);
  }

  static List<double> _basisFactor(
    Uint8List rgba,
    int width,
    int height,
    int xComponent,
    int yComponent,
  ) {
    var r = 0.0;
    var g = 0.0;
    var b = 0.0;
    final normalisation = xComponent == 0 && yComponent == 0 ? 1.0 : 2.0;
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final basis =
            math.cos(math.pi * xComponent * x / width) *
            math.cos(math.pi * yComponent * y / height);
        final index = 4 * (x + y * width);
        r += basis * _srgbToLinear(rgba[index]);
        g += basis * _srgbToLinear(rgba[index + 1]);
        b += basis * _srgbToLinear(rgba[index + 2]);
      }
    }
    final scale = normalisation / (width * height);
    return [r * scale, g * scale, b * scale];
  }

  static int _encodeDc(List<double> value) {
    return (_linearToSrgb(value[0]) << 16) +
        (_linearToSrgb(value[1]) << 8) +
        _linearToSrgb(value[2]);
  }

  static int _encodeAc(List<double> value, double maximumValue) {
    int quantise(double v) {
      return (_signPow(v / maximumValue, 0.5) * 9 + 9.5).floor().clamp(0, 18);
    }

    return quantise(value[0]) * 19 * 19 +
        quantise(value[1]) * 19 +
        quantise(value[2]);
  }

  static List<double> _decodeDc(int value) {
    return [
      _srgbToLinear(value >> 16),
      _srgbToLinear((value >> 8) & 255),
      _srgbToLinear(value & 255),
    ];
  }

  static List<double> _decodeAc(int value, double maximumValue) {
    final quantR = value ~/ (19 * 19);
    final quantG = (value ~/ 19) % 19;
    final quantB = value % 19;
    double unquantise(int q) => _signPow((q - 9) / 9, 2) * maximumValue;
    return [unquantise(quantR), unquantise(quantG), unquantise(quantB)];
  }

  static double _signPow(double value, double exponent) {
    return math.pow(value.abs(), exponent).toDouble() * value.sign;
  }

  static double _srgbToLinear(int value) {
    final v = value / 255;
    return v <= 0.04045
        ? v / 12.92
        : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  }

  static int _linearToSrgb(double value) {
    final v = value.clamp(0.0, 1.0);
    if (v <= 0.0031308) {
      return (v * 12.92 * 255 + 0.5).toInt();
    }
    return ((1.055 * math.pow(v, 1 / 2.4) - 0.055) * 255 + 0.5).toInt();
  }

  static String _encode83(int value, int length) {
    final out = StringBuffer();
    for (var i = 1; i <= length; i++) {
      final digit = (value ~/ math.pow(83, length - i).toInt()) % 83;
      out.write(_alphabet[digit]);
    }
    return out.toString();
  }

  static int _decode83(String text) {
    var value = 0;
    for (var i = 0; i < text.length; i++) {
      value = value * 83 + _alphabet.indexOf(text[i]);
    }
    return value;
  }
}

/// Draws a BlurHash filling its box: the average colour at once, then the
/// blurred picture as soon as it is decoded. Without a (valid) hash it is
/// a flat [fallback] colour.
class BlurHashView extends StatefulWidget {
  const BlurHashView({required this.hash, required this.fallback, super.key});

  final String? hash;
  final Color fallback;

  @override
  State<BlurHashView> createState() => _BlurHashViewState();
}

class _BlurHashViewState extends State<BlurHashView> {
  static const _side = 32;
  static final _decoded = <String, ui.Image>{};

  ui.Image? _image;

  @override
  void initState() {
    super.initState();
    _decodeHash();
  }

  @override
  void didUpdateWidget(covariant BlurHashView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.hash != widget.hash) {
      _image = null;
      _decodeHash();
    }
  }

  void _decodeHash() {
    final hash = widget.hash;
    if (!BlurHash.isValid(hash)) {
      return;
    }
    final cached = _decoded[hash];
    if (cached != null) {
      _image = cached;
      return;
    }
    final pixels = BlurHash.decode(hash!, width: _side, height: _side);
    ui.decodeImageFromPixels(pixels, _side, _side, ui.PixelFormat.rgba8888, (
      image,
    ) {
      if (_decoded.length > 120) {
        _decoded.remove(_decoded.keys.first);
      }
      _decoded[hash] = image;
      if (mounted && widget.hash == hash) {
        setState(() => _image = image);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final average = BlurHash.averageColor(widget.hash) ?? widget.fallback;
    final image = _image;
    return ColoredBox(
      color: average,
      child: image == null
          ? const SizedBox.expand()
          : RawImage(
              image: image,
              fit: BoxFit.fill,
              filterQuality: FilterQuality.medium,
            ),
    );
  }
}

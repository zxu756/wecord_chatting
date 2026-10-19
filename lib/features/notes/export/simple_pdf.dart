import 'dart:convert';
import 'dart:typed_data';

/// One page of a [buildImagePdf] document: a JPEG that fills the page.
class PdfPageImage {
  const PdfPageImage({
    required this.jpeg,
    required this.pixelWidth,
    required this.pixelHeight,
  });

  final Uint8List jpeg;
  final int pixelWidth;
  final int pixelHeight;
}

/// The size of an A4 page in PDF points (1/72 inch).
const pdfA4Width = 595;
const pdfA4Height = 842;

/// A PDF made of full page pictures: one JPEG per A4 page.
///
/// Why pictures: a PDF with real text needs the fonts inside the file, and
/// the notes are read in Chinese as often as in English; a Chinese font is
/// megabytes and the phone's own fonts cannot be embedded. Drawing the pages
/// with the device's fonts and putting the pictures into the PDF keeps every
/// language right, at the price of text that cannot be selected.
///
/// The file is the plain structure of PDF 1.4: a catalog, a page tree, and
/// per page an image (DCTDecode, the JPEG as it is), a content stream that
/// draws it over the page, and the page object; then the cross-reference
/// table. [title] goes into the document information as UTF-16.
Uint8List buildImagePdf(List<PdfPageImage> pages, {String title = ''}) {
  if (pages.isEmpty) {
    throw ArgumentError('A PDF needs a page');
  }
  final out = BytesBuilder(copy: false);
  final offsets = <int>[];

  void write(String text) => out.add(latin1.encode(text));

  void startObject(int number) {
    offsets.add(out.length);
    write('$number 0 obj\n');
  }

  // Object numbers: 1 catalog, 2 page tree, 3 information, then per page
  // image, content and page (4 + 3 * i, 5 + 3 * i, 6 + 3 * i).
  write('%PDF-1.4\n');
  out.add(const [0x25, 0xE2, 0xE3, 0xCF, 0xD3, 0x0A]);

  startObject(1);
  write('<< /Type /Catalog /Pages 2 0 R >>\nendobj\n');

  startObject(2);
  final kids = [for (var i = 0; i < pages.length; i++) '${6 + 3 * i} 0 R'];
  write(
    '<< /Type /Pages /Kids [${kids.join(' ')}] /Count ${pages.length} >>\n'
    'endobj\n',
  );

  startObject(3);
  write('<< /Producer (WeCord)');
  if (title.trim().isNotEmpty) {
    write(' /Title <${_utf16Hex(title.trim())}>');
  }
  write(' >>\nendobj\n');

  for (var i = 0; i < pages.length; i++) {
    final page = pages[i];
    final image = 4 + 3 * i;
    final content = 5 + 3 * i;
    final pageObject = 6 + 3 * i;

    startObject(image);
    write(
      '<< /Type /XObject /Subtype /Image /Width ${page.pixelWidth} '
      '/Height ${page.pixelHeight} /ColorSpace /DeviceRGB '
      '/BitsPerComponent 8 /Filter /DCTDecode /Length ${page.jpeg.length} '
      '>>\nstream\n',
    );
    out.add(page.jpeg);
    write('\nendstream\nendobj\n');

    final draw = 'q $pdfA4Width 0 0 $pdfA4Height 0 0 cm /Im0 Do Q';
    startObject(content);
    write('<< /Length ${draw.length} >>\nstream\n$draw\nendstream\nendobj\n');

    startObject(pageObject);
    write(
      '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 $pdfA4Width $pdfA4Height] '
      '/Resources << /XObject << /Im0 $image 0 R >> >> '
      '/Contents $content 0 R >>\nendobj\n',
    );
  }

  final objectCount = 3 + 3 * pages.length;
  final xrefAt = out.length;
  write('xref\n0 ${objectCount + 1}\n0000000000 65535 f \n');
  for (final offset in offsets) {
    write('${offset.toString().padLeft(10, '0')} 00000 n \n');
  }
  write(
    'trailer\n<< /Size ${objectCount + 1} /Root 1 0 R /Info 3 0 R >>\n'
    'startxref\n$xrefAt\n%%EOF\n',
  );
  return out.takeBytes();
}

String _utf16Hex(String text) {
  final units = text.codeUnits;
  final buffer = StringBuffer('FEFF');
  for (final unit in units) {
    buffer.write(unit.toRadixString(16).padLeft(4, '0').toUpperCase());
  }
  return buffer.toString();
}

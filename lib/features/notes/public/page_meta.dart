// Sets what a browser (and a search engine) reads of the page: the title and
// whether it may be listed. Only the web has a page; elsewhere nothing.
export 'package:wecord/features/notes/public/page_meta_stub.dart'
    if (dart.library.js_interop) 'package:wecord/features/notes/public/page_meta_web.dart';

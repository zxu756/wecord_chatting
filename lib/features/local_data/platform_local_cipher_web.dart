import 'package:wecord/features/local_data/local_cipher.dart';
import 'package:wecord/features/local_data/web_crypto_local_cipher.dart';

LocalCipher createPlatformCipher() => WebCryptoLocalCipher();

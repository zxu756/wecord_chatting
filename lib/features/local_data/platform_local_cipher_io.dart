import 'package:wecord/features/local_data/aes_gcm_local_cipher.dart';
import 'package:wecord/features/local_data/local_cipher.dart';
import 'package:wecord/features/local_data/secure_storage_key_store.dart';

LocalCipher createPlatformCipher() => AesGcmLocalCipher(SecureStorageKeyStore());

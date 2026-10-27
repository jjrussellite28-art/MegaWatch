/// Trakt API constants.
///
/// The client ID and secret are hardcoded intentionally. In a mobile app these
/// can always be extracted from the binary, so there is no security benefit to
/// hiding them. The real protection is the OAuth flow — the keys alone are
/// useless without a user's explicit authorization.
library;

// MegaWatch: set your own Trakt app with
//   --dart-define=TRAKT_CLIENT_ID=... --dart-define=TRAKT_CLIENT_SECRET=...
// (the release workflow does this from the repository secrets of the same
// names). Without them the app falls back to the values it was forked with.
const String _traktIdDefine = String.fromEnvironment('TRAKT_CLIENT_ID');
const String _traktSecretDefine = String.fromEnvironment('TRAKT_CLIENT_SECRET');

const String kTraktClientId = _traktIdDefine != ''
    ? _traktIdDefine
    : '76697eeb2143258ec076134ed0a1d99fa075ef6e1e68263b00cd61e86540794b';

const String kTraktClientSecret = _traktSecretDefine != ''
    ? _traktSecretDefine
    : '74f0994f0783dfb470645685dbf39675f0102fd66f475579ae1de7b2ec2bd466';

const String kTraktApiBaseUrl = 'https://api.trakt.tv';
const String kTraktTokenUrl = '$kTraktApiBaseUrl/oauth/token';

const String kTraktDeviceCodeUrl = '$kTraktApiBaseUrl/oauth/device/code';
const String kTraktDeviceTokenUrl = '$kTraktApiBaseUrl/oauth/device/token';

const String kTraktApiVersion = '2';

/// Guesses which IPTV category names are NOT English, so they can be hidden
/// in one go (hidden categories are skipped everywhere — list, search, guide).
///
/// This is a name-based guess: IPTV providers label categories like
/// "FR | Sports", "[ES] Cine", "Arabic Movies" or write them in another
/// alphabet. It is deliberately conservative — a name only counts when it
/// clearly points at another language — and the app always shows the list
/// before anything is hidden. Nothing is deleted; it can all be shown again.
class IptvLanguageFilter {
  IptvLanguageFilter._();

  /// Letters from non-Latin alphabets (Greek, Cyrillic, Armenian, Hebrew,
  /// Arabic, Indic, Thai, Georgian, CJK, Hangul).
  static final RegExp _nonLatin = RegExp(
    r'[Ͱ-῿぀-ヿ㐀-鿿가-힯]',
  );

  /// "FR | News", "[ES] Cine", "DE: Sport", "AR - Movies", "(TR) Dizi"
  static final RegExp _prefix = RegExp(
    r'^[\s\[\(\{*#>•·•-]*([A-Za-z]{2,5})\s*[\]\)\}]?\s*(?:[|:/\\]|[-–—]\s|\s[-–—]|[\]\)\}])',
  );

  static const Set<String> _foreignCodes = {
    'AR', 'ARA', 'AE', 'SA', 'QA', 'KW', 'EG', 'MA', 'DZ', 'TN', 'IQ', 'LB', 'JO', 'SY', 'LY',
    'FR', 'FRA', 'BE', 'CH', 'LU',
    'ES', 'ESP', 'MX', 'LAT', 'LATAM', 'LA', 'CO', 'CL', 'PE', 'VE', 'EC', 'UY', 'PY', 'BO', 'CU', 'DO',
    'DE', 'GER', 'DEU', 'AT',
    'IT', 'ITA', 'PT', 'POR', 'BR', 'BRA',
    'TR', 'TUR', 'RU', 'RUS', 'UA', 'UKR', 'BY', 'PL', 'POL', 'NL', 'NLD', 'DUT',
    'SE', 'SWE', 'NO', 'NOR', 'DK', 'DEN', 'FI', 'FIN', 'IS',
    'GR', 'GRE', 'RO', 'ROM', 'HU', 'HUN', 'CZ', 'CZE', 'SK', 'SVK', 'BG', 'BUL',
    'RS', 'SRB', 'HR', 'CRO', 'SI', 'SLO', 'BA', 'MK', 'AL', 'ALB', 'ME', 'XK',
    'EE', 'LV', 'LT', 'KZ', 'AZ', 'AM', 'GE',
    'IN', 'IND', 'HI', 'PK', 'PAK', 'BD', 'LK', 'NP', 'AF', 'IR', 'IRN', 'IL', 'ISR',
    'CN', 'CHN', 'TW', 'HK', 'JP', 'JPN', 'KR', 'KOR', 'TH', 'THA', 'VN', 'VNM', 'ID', 'MY', 'PH',
    'NG', 'KE', 'ZA', 'ET', 'SO',
  };

  /// Whole words that name another language or a mostly non-English region.
  static final RegExp _words = RegExp(
    r'\b(arabic|arab|arabia|arabe|french|francais|français|france|spanish|espanol|español|spain|espana|españa|'
    r'german|deutsch|deutschland|germany|italian|italiano|italia|italy|portuguese|portugues|português|portugal|'
    r'brazil|brasil|brazilian|turkish|turkce|türkçe|turkey|turk|russian|russia|ukrainian|ukraine|polish|polska|poland|'
    r'dutch|nederland|netherlands|belgium|swedish|sweden|svenska|norwegian|norway|danish|denmark|finnish|finland|'
    r'greek|greece|romanian|romania|hungarian|hungary|czech|slovak|slovakia|bulgarian|bulgaria|serbian|serbia|'
    r'croatian|croatia|bosnian|bosnia|albanian|albania|macedonian|slovenian|hindi|indian|india|urdu|pakistan|pakistani|'
    r'bangla|bengali|bangladesh|tamil|telugu|malayalam|punjabi|kannada|marathi|gujarati|persian|farsi|iran|iranian|'
    r'afghan|kurdish|hebrew|israel|chinese|china|mandarin|cantonese|japanese|japan|korean|korea|thai|thailand|'
    r'vietnam|vietnamese|indonesia|indonesian|malay|malaysia|filipino|philippines|latino|latin|latam|mexico|'
    r'argentina|colombia|chile|peru|venezuela|african|nigeria|somali|swahili|amharic)\b',
    caseSensitive: false,
  );

  /// True when [name] clearly points at a language other than English.
  static bool looksNonEnglish(String name) {
    final n = name.trim();
    if (n.isEmpty) return false;
    if (_nonLatin.hasMatch(n)) return true;
    final m = _prefix.firstMatch(n);
    if (m != null && _foreignCodes.contains(m.group(1)!.toUpperCase())) {
      return true;
    }
    // A mixed name that also says English ("English / Arabic") is left alone.
    if (RegExp(r'\b(english|eng|usa|uk|us)\b', caseSensitive: false).hasMatch(n)) {
      return false;
    }
    return _words.hasMatch(n);
  }

  /// The names in [categories] that look non-English, in their original order.
  static List<String> findNonEnglish(Iterable<String> categories) => [
    for (final c in categories)
      if (looksNonEnglish(c)) c,
  ];
}

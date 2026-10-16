/// Pulls contact details out of OCR text from a business card.
class ContactCard {
  String name;
  String company;
  String title;
  List<String> phones;
  List<String> emails;
  String website;
  String address;

  ContactCard({
    this.name = '',
    this.company = '',
    this.title = '',
    List<String>? phones,
    List<String>? emails,
    this.website = '',
    this.address = '',
  })  : phones = phones ?? [],
        emails = emails ?? [];

  static final _email = RegExp(r'[\w.+-]+@[\w-]+\.[\w.-]+');
  static final _phone = RegExp(r'(\+?\d[\d\s\-().]{7,}\d)');
  static final _web = RegExp(r'((?:https?://)?(?:www\.)?[a-z0-9-]+\.[a-z]{2,}(?:\.[a-z]{2,})?(?:/\S*)?)', caseSensitive: false);
  static final _titleWords = RegExp(
      r'\b(manager|director|engineer|founder|ceo|cto|cfo|officer|head|lead|consultant|developer|designer|executive|president|partner|advocate|doctor|dr\.?|sales|marketing)\b',
      caseSensitive: false);
  static final _companyWords = RegExp(
      r'\b(ltd|limited|pvt|inc|llp|llc|corp|company|co\.|technologies|solutions|services|group|industries|enterprises|studio|labs)\b',
      caseSensitive: false);
  static final _addressWords = RegExp(
      r'\b(road|rd\.?|street|st\.?|nagar|sector|floor|block|lane|avenue|marg|city|india|pin|\d{6})\b',
      caseSensitive: false);

  factory ContactCard.parse(String text) {
    final c = ContactCard();
    final lines = text.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
    final rest = <String>[];
    for (final line in lines) {
      final emails = _email.allMatches(line).map((m) => m.group(0)!).toList();
      if (emails.isNotEmpty) {
        c.emails.addAll(emails);
        continue;
      }
      final phones = _phone
          .allMatches(line)
          .map((m) => m.group(0)!.trim())
          .where((x) => x.replaceAll(RegExp(r'\D'), '').length >= 8)
          .toList();
      if (phones.isNotEmpty) {
        c.phones.addAll(phones);
        continue;
      }
      final web = _web.firstMatch(line);
      if (web != null && c.website.isEmpty && !line.contains(' ')) {
        c.website = web.group(0)!;
        continue;
      }
      rest.add(line);
    }
    for (final line in rest) {
      if (c.title.isEmpty && _titleWords.hasMatch(line)) {
        c.title = line;
      } else if (c.company.isEmpty && _companyWords.hasMatch(line)) {
        c.company = line;
      } else if (_addressWords.hasMatch(line)) {
        c.address = c.address.isEmpty ? line : '${c.address}, $line';
      } else if (c.name.isEmpty &&
          RegExp(r"^[A-Za-z.'ऀ-ॿ]+(\s+[A-Za-z.'ऀ-ॿ]+){0,3}$").hasMatch(line) &&
          line.length <= 40) {
        c.name = line;
      }
    }
    if (c.company.isEmpty) {
      for (final line in rest) {
        if (line != c.name && line != c.title && !c.address.contains(line)) {
          c.company = line;
          break;
        }
      }
    }
    return c;
  }

  String _esc(String v) => v.replaceAll('\\', '\\\\').replaceAll(',', '\\,').replaceAll(';', '\\;');

  String toVCard() {
    final b = StringBuffer()
      ..writeln('BEGIN:VCARD')
      ..writeln('VERSION:3.0');
    final parts = name.trim().split(RegExp(r'\s+'));
    final last = parts.length > 1 ? parts.last : '';
    final first = parts.length > 1 ? parts.sublist(0, parts.length - 1).join(' ') : name.trim();
    b.writeln('N:${_esc(last)};${_esc(first)};;;');
    b.writeln('FN:${_esc(name.trim().isEmpty ? company : name.trim())}');
    if (company.isNotEmpty) b.writeln('ORG:${_esc(company)}');
    if (title.isNotEmpty) b.writeln('TITLE:${_esc(title)}');
    for (final ph in phones) {
      b.writeln('TEL;TYPE=CELL:${ph.replaceAll(RegExp(r'[^\d+]'), '')}');
    }
    for (final e in emails) {
      b.writeln('EMAIL;TYPE=WORK:$e');
    }
    if (website.isNotEmpty) b.writeln('URL:$website');
    if (address.isNotEmpty) b.writeln('ADR;TYPE=WORK:;;${_esc(address)};;;;');
    b.writeln('END:VCARD');
    return b.toString();
  }
}

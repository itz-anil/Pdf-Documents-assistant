import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import '../app/icons.dart';
import 'package:provider/provider.dart';

import '../app/theme.dart';
import '../core/business_card.dart';
import '../core/export_service.dart';
import '../core/library_store.dart';
import '../core/models.dart';
import '../widgets/common.dart';
import '../widgets/glass.dart';
import 'document_screen.dart';

/// Review the details read from a business card and save them as a contact.
class BusinessCardScreen extends StatefulWidget {
  final DocItem doc;
  const BusinessCardScreen({super.key, required this.doc});

  @override
  State<BusinessCardScreen> createState() => _BusinessCardScreenState();
}

class _BusinessCardScreenState extends State<BusinessCardScreen> {
  late final ContactCard _card;
  late final Map<String, TextEditingController> _c;

  @override
  void initState() {
    super.initState();
    _card = ContactCard.parse(widget.doc.fullText);
    _c = {
      'name': TextEditingController(text: _card.name),
      'title': TextEditingController(text: _card.title),
      'company': TextEditingController(text: _card.company),
      'phone': TextEditingController(text: _card.phones.join(', ')),
      'email': TextEditingController(text: _card.emails.join(', ')),
      'web': TextEditingController(text: _card.website),
      'address': TextEditingController(text: _card.address),
    };
  }

  @override
  void dispose() {
    for (final c in _c.values) {
      c.dispose();
    }
    super.dispose();
  }

  ContactCard _current() {
    List<String> split(String v) => v.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    return ContactCard(
      name: _c['name']!.text.trim(),
      title: _c['title']!.text.trim(),
      company: _c['company']!.text.trim(),
      phones: split(_c['phone']!.text),
      emails: split(_c['email']!.text),
      website: _c['web']!.text.trim(),
      address: _c['address']!.text.trim(),
    );
  }

  Future<File> _writeVcf() async {
    final store = context.read<LibraryStore>();
    final card = _current();
    final dir = await store.scratch('vcf');
    final name = safeFileName(card.name.isEmpty ? 'Contact' : card.name);
    final f = File(p.join(dir.path, '$name.vcf'));
    await f.writeAsString(card.toVCard(), flush: true);
    return f;
  }

  @override
  Widget build(BuildContext context) {
    final g = Glass.of(context);
    final store = context.read<LibraryStore>();
    Widget field(String key, String label, IconData icon, {TextInputType? type}) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextField(
          controller: _c[key],
          keyboardType: type,
          style: TextStyle(color: g.text),
          decoration: InputDecoration(
            labelText: label,
            prefixIcon: Padding(
              padding: const EdgeInsets.all(12),
              child: PhosphorIcon(icon, color: g.accent.primary, size: 20),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      body: GlassBackground(
        child: SafeArea(
          child: Column(
            children: [
              GlassTopBar(
                title: 'Business card',
                subtitle: 'Check the details, then save',
                actions: [
                  GlassIconButton(
                    icon: PhosphorIconsRegular.fileText,
                    tooltip: 'Open scan',
                    onTap: () => Navigator.of(context)
                        .pushReplacement(MaterialPageRoute(builder: (_) => DocumentScreen(doc: widget.doc))),
                  ),
                ],
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  children: [
                    if (widget.doc.pages.isNotEmpty)
                      Center(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(14),
                          child: Image.file(
                            store.processedFile(widget.doc, widget.doc.pages.first),
                            height: 170,
                            fit: BoxFit.contain,
                            cacheHeight: 500,
                          ),
                        ),
                      ),
                    const SizedBox(height: 18),
                    GlassPanel(
                      padding: const EdgeInsets.fromLTRB(14, 16, 14, 4),
                      child: Column(
                        children: [
                          field('name', 'Name', PhosphorIconsRegular.user),
                          field('title', 'Job title', PhosphorIconsRegular.briefcase),
                          field('company', 'Company', PhosphorIconsRegular.buildings),
                          field('phone', 'Phone (comma separated)', PhosphorIconsRegular.phone, type: TextInputType.phone),
                          field('email', 'Email', PhosphorIconsRegular.envelopeSimple, type: TextInputType.emailAddress),
                          field('web', 'Website', PhosphorIconsRegular.globe, type: TextInputType.url),
                          field('address', 'Address', PhosphorIconsRegular.mapPin),
                        ],
                      ),
                    ),
                    if (widget.doc.fullText.isEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text('No text could be read from this card — fill the details in by hand.',
                            style: TextStyle(color: g.muted)),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                child: Column(
                  children: [
                    GradientButton(
                      label: 'Save to Contacts',
                      icon: PhosphorIconsRegular.userPlus,
                      expand: true,
                      onTap: () async {
                        final f = await _writeVcf();
                        await ExportService.open(f.path);
                        if (context.mounted) toast(context, 'Opening Contacts…');
                      },
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: GlassButton(
                            label: 'Share vCard',
                            icon: PhosphorIconsRegular.shareNetwork,
                            onTap: () async => ExportService.share([(await _writeVcf()).path]),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: GlassButton(
                            label: 'Copy',
                            icon: PhosphorIconsRegular.copy,
                            onTap: () {
                              final c = _current();
                              final text = [
                                c.name,
                                c.title,
                                c.company,
                                ...c.phones,
                                ...c.emails,
                                c.website,
                                c.address,
                              ].where((e) => e.isNotEmpty).join('\n');
                              Clipboard.setData(ClipboardData(text: text));
                              toast(context, 'Contact details copied');
                            },
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import '../app/icons.dart';
import 'package:provider/provider.dart';

import '../app/theme.dart';
import '../core/library_store.dart';
import '../core/models.dart';
import '../core/settings.dart';
import '../widgets/common.dart';
import '../widgets/doc_tile.dart';
import '../widgets/glass.dart';
import 'doc_actions.dart';
import 'scan_flow.dart';

const _favorites = '__fav__';

class HomeScreen extends StatefulWidget {
  final VoidCallback onOpenSearch;
  const HomeScreen({super.key, required this.onOpenSearch});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String? _folder; // null = all, _favorites = favourites, else folder id
  final Set<String> _selected = {};

  bool get _selecting => _selected.isNotEmpty;

  void _toggle(DocItem d) {
    haptic(context);
    setState(() => _selected.contains(d.id) ? _selected.remove(d.id) : _selected.add(d.id));
  }

  List<DocItem> _selectedDocs(LibraryStore store) =>
      store.docs.where((d) => _selected.contains(d.id)).toList();

  @override
  Widget build(BuildContext context) {
    final store = context.watch<LibraryStore>();
    final settings = context.watch<SettingsStore>();
    final g = Glass.of(context);
    if (_folder != null && _folder != _favorites && !store.folders.any((f) => f.id == _folder)) {
      _folder = null;
    }
    final docs = store.query(
      folderId: _folder == _favorites ? null : _folder,
      favoritesOnly: _folder == _favorites,
      sort: settings.sort,
    );
    _selected.removeWhere((id) => store.byId(id) == null);
    final top = MediaQuery.of(context).padding.top;

    return PopScope(
      canPop: !_selecting,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) setState(_selected.clear);
      },
      child: CustomScrollView(
        physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
        slivers: [
          SliverToBoxAdapter(child: SizedBox(height: top + 8)),
          SliverToBoxAdapter(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: _selecting
                  ? _SelectionBar(
                      key: const ValueKey('sel'),
                      count: _selected.length,
                      onClose: () => setState(_selected.clear),
                      onSelectAll: () => setState(() => _selected.addAll(docs.map((d) => d.id))),
                      onShare: () => DocActions.zip(context, _selectedDocs(store)),
                      onMerge: _selected.length < 2
                          ? null
                          : () async {
                              final list = _selectedDocs(store);
                              final merged = await runBusy(context, 'Merging…', (_) => store.mergeDocs(list));
                              if (merged != null && context.mounted) {
                                setState(_selected.clear);
                                toast(context, 'Merged into “${merged.name}”');
                              }
                            },
                      onMove: () async {
                        await DocActions.moveToFolder(context, _selectedDocs(store));
                        if (mounted) setState(_selected.clear);
                      },
                      onDelete: () async {
                        if (await DocActions.delete(context, _selectedDocs(store)) && mounted) {
                          setState(_selected.clear);
                        }
                      },
                    )
                  : _Header(key: const ValueKey('head'), onSearch: widget.onOpenSearch),
            ),
          ),
          SliverToBoxAdapter(child: _QuickActions(folderId: _folder == _favorites ? null : _folder)),
          SliverToBoxAdapter(
            child: _FolderStrip(
              current: _folder,
              onSelect: (f) => setState(() => _folder = f),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 12, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _folder == null
                              ? 'All documents'
                              : _folder == _favorites
                                  ? 'Favourites'
                                  : store.folders.firstWhere((f) => f.id == _folder).name,
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: g.text),
                        ),
                        Text('${docs.length} item${docs.length == 1 ? '' : 's'}',
                            style: TextStyle(color: g.muted, fontSize: 12.5)),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Sort',
                    onPressed: () async {
                      final s = await pickOption<SortOrder>(
                        context,
                        title: 'Sort by',
                        options: SortOrder.values,
                        label: (o) => o.label,
                        selected: settings.sort,
                        icon: (o) => switch (o) {
                          SortOrder.newest => PhosphorIconsRegular.sortDescending,
                          SortOrder.oldest => PhosphorIconsRegular.sortAscending,
                          SortOrder.nameAZ => PhosphorIconsRegular.textAa,
                          SortOrder.nameZA => PhosphorIconsRegular.textAa,
                          SortOrder.largest => PhosphorIconsRegular.stack,
                        },
                      );
                      if (s != null) settings.setSort = s;
                    },
                    icon: PhosphorIcon(PhosphorIconsRegular.sortAscending, color: g.text),
                  ),
                  IconButton(
                    tooltip: settings.gridView ? 'List view' : 'Grid view',
                    onPressed: () => settings.setGridView = !settings.gridView,
                    icon: PhosphorIcon(
                      settings.gridView ? PhosphorIconsRegular.listBullets : PhosphorIconsRegular.squaresFour,
                      color: g.text,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (!store.loaded)
            const SliverToBoxAdapter(child: Center(child: CircularProgressIndicator()))
          else if (docs.isEmpty)
            SliverToBoxAdapter(
              child: EmptyState(
                icon: _folder == _favorites ? PhosphorIconsRegular.star : PhosphorIconsRegular.scan,
                title: _folder == _favorites
                    ? 'No favourites yet'
                    : _folder != null
                        ? 'This folder is empty'
                        : 'Your scans will live here',
                message: _folder == _favorites
                    ? 'Star a document to keep it close.'
                    : 'Tap Scan to capture documents, receipts, ID cards and more. Everything stays on your phone.',
                action: _folder == _favorites
                    ? null
                    : GradientButton(
                        label: 'Scan a document',
                        icon: PhosphorIconsRegular.scan,
                        onTap: () => ScanFlow.chooseAndScan(context, folderId: _folder),
                      ),
              ),
            )
          else if (settings.gridView)
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 0.74,
                ),
                delegate: SliverChildBuilderDelegate(
                  (_, i) {
                    final d = docs[i];
                    return FadeIn(
                      index: i,
                      child: DocGridTile(
                        store: store,
                        doc: d,
                        selecting: _selecting,
                        selected: _selected.contains(d.id),
                        onTap: () => _selecting ? _toggle(d) : DocActions.open(context, d),
                        onLongPress: () => _toggle(d),
                      ),
                    );
                  },
                  childCount: docs.length,
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: SliverList.separated(
                itemCount: docs.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (_, i) {
                  final d = docs[i];
                  return FadeIn(
                    index: i,
                    child: DocListTile(
                      store: store,
                      doc: d,
                      selecting: _selecting,
                      selected: _selected.contains(d.id),
                      onTap: () => _selecting ? _toggle(d) : DocActions.open(context, d),
                      onLongPress: () => _toggle(d),
                      onMore: () => DocActions.moreSheet(context, d),
                    ),
                  );
                },
              ),
            ),
          const SliverToBoxAdapter(child: SizedBox(height: 120)),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final VoidCallback onSearch;
  const _Header({super.key, required this.onSearch});

  @override
  Widget build(BuildContext context) {
    final g = Glass.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: g.accent.primary,
                  borderRadius: BorderRadius.circular(13),
                ),
                alignment: Alignment.center,
                child: PhosphorIcon(PhosphorIconsBold.scan, color: g.onAccent, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text('DocMind',
                    style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, letterSpacing: -0.6, color: g.text)),
              ),
            ],
          ),
          const SizedBox(height: 16),
          GlassPanel(
            radius: 18,
            onTap: onSearch,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                PhosphorIcon(PhosphorIconsRegular.magnifyingGlass, color: g.muted, size: 20),
                const SizedBox(width: 10),
                Text('Search names and text inside scans', style: TextStyle(color: g.muted, fontSize: 14.5)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SelectionBar extends StatelessWidget {
  final int count;
  final VoidCallback onClose;
  final VoidCallback onSelectAll;
  final VoidCallback onShare;
  final VoidCallback? onMerge;
  final VoidCallback onMove;
  final VoidCallback onDelete;
  const _SelectionBar({
    super.key,
    required this.count,
    required this.onClose,
    required this.onSelectAll,
    required this.onShare,
    required this.onMerge,
    required this.onMove,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final g = Glass.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
      child: GlassPanel(
        radius: 22,
        strong: true,
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
        child: Column(
          children: [
            Row(
              children: [
                GlassIconButton(icon: PhosphorIconsBold.x, tooltip: 'Cancel selection', onTap: onClose),
                const SizedBox(width: 12),
                Expanded(
                  child: Text('$count selected',
                      style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: g.text)),
                ),
                TextButton(onPressed: onSelectAll, child: const Text('Select all')),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _BarAction(icon: PhosphorIconsRegular.fileZip, label: 'ZIP', onTap: onShare),
                _BarAction(icon: PhosphorIconsRegular.unite, label: 'Merge', onTap: onMerge),
                _BarAction(icon: PhosphorIconsRegular.folderSimple, label: 'Move', onTap: onMove),
                _BarAction(icon: PhosphorIconsRegular.trash, label: 'Delete', onTap: onDelete, danger: true),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _BarAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool danger;
  const _BarAction({required this.icon, required this.label, this.onTap, this.danger = false});

  @override
  Widget build(BuildContext context) {
    final g = Glass.of(context);
    final c = danger ? g.danger : g.text;
    return Semantics(
      button: true,
      label: label,
      child: Pressable(
        onTap: onTap,
        child: Opacity(
          opacity: onTap == null ? 0.4 : 1,
          child: SizedBox(
            width: 70,
            height: 56,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                AppIcon(icon, color: c, size: 23),
                const SizedBox(height: 4),
                Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: c)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _QuickActions extends StatelessWidget {
  final String? folderId;
  const _QuickActions({this.folderId});

  @override
  Widget build(BuildContext context) {
    final g = Glass.of(context);
    final items = <(IconData, String, Future<void> Function())>[
      (PhosphorIconsRegular.fileText, 'Document', () => ScanFlow.scan(context, ScanMode.document, folderId: folderId)),
      (PhosphorIconsRegular.identificationCard, 'ID Card', () => ScanFlow.scan(context, ScanMode.idCard, folderId: folderId)),
      (PhosphorIconsRegular.bookOpen, 'Book', () => ScanFlow.scan(context, ScanMode.book, folderId: folderId)),
      (PhosphorIconsRegular.addressBook, 'Card', () => ScanFlow.scan(context, ScanMode.businessCard, folderId: folderId)),
      (PhosphorIconsRegular.receipt, 'Receipt', () => ScanFlow.scan(context, ScanMode.receipt, folderId: folderId)),
      (PhosphorIconsRegular.chalkboard, 'Board', () => ScanFlow.scan(context, ScanMode.whiteboard, folderId: folderId)),
      (PhosphorIconsRegular.qrCode, 'QR Code', () => ScanFlow.openQr(context)),
      (PhosphorIconsRegular.images, 'Photos', () => ScanFlow.importPhotos(context, folderId: folderId)),
      (PhosphorIconsRegular.filePdf, 'PDF', () => ScanFlow.importPdf(context, folderId: folderId)),
    ];
    return SizedBox(
      height: 104,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
        physics: const BouncingScrollPhysics(),
        itemCount: items.length,
        separatorBuilder: (_, _) => const SizedBox(width: 14),
        itemBuilder: (_, i) {
          final (icon, label, action) = items[i];
          return Semantics(
            button: true,
            label: label,
            child: Pressable(
              onTap: action,
              scale: 0.92,
              child: Column(
                children: [
                  IconBadge(icon, size: 56, filled: i == 0),
                  const SizedBox(height: 7),
                  Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: g.text)),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _FolderStrip extends StatelessWidget {
  final String? current;
  final ValueChanged<String?> onSelect;
  const _FolderStrip({required this.current, required this.onSelect});

  Future<void> _folderMenu(BuildContext context, Folder f) async {
    final store = context.read<LibraryStore>();
    final action = await pickOption<String>(
      context,
      title: f.name,
      options: const ['rename', 'color', 'delete'],
      label: (o) => switch (o) { 'rename' => 'Rename folder', 'color' => 'Change colour', _ => 'Delete folder' },
      icon: (o) => switch (o) {
        'rename' => PhosphorIconsRegular.pencilSimpleLine,
        'color' => PhosphorIconsRegular.palette,
        _ => PhosphorIconsRegular.trash,
      },
    );
    if (!context.mounted) return;
    if (action == 'rename') {
      final n = await promptText(context, title: 'Rename folder', initial: f.name);
      if (n != null && n.trim().isNotEmpty) store.renameFolder(f, n);
    } else if (action == 'color') {
      f.colorIndex = (f.colorIndex + 1) % folderColors.length;
      store.renameFolder(f, f.name);
    } else if (action == 'delete') {
      final ok = await confirm(context,
          title: 'Delete folder?', message: 'Documents inside stay in your library.', action: 'Delete folder');
      if (ok) {
        store.deleteFolder(f);
        onSelect(null);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<LibraryStore>();
    final g = Glass.of(context);
    return SizedBox(
      height: 58,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
        physics: const BouncingScrollPhysics(),
        children: [
          GlassChip(
            label: 'All',
            icon: PhosphorIconsRegular.files,
            selected: current == null,
            onTap: () => onSelect(null),
          ),
          const SizedBox(width: 8),
          GlassChip(
            label: 'Favourites',
            icon: PhosphorIconsRegular.star,
            selected: current == _favorites,
            onTap: () => onSelect(_favorites),
          ),
          for (final f in store.folders) ...[
            const SizedBox(width: 8),
            GestureDetector(
              onLongPress: () => _folderMenu(context, f),
              child: GlassChip(
                label: f.name,
                icon: PhosphorIconsRegular.folderSimple,
                selected: current == f.id,
                onTap: () => current == f.id ? _folderMenu(context, f) : onSelect(f.id),
              ),
            ),
          ],
          const SizedBox(width: 8),
          Semantics(
            button: true,
            label: 'New folder',
            child: Pressable(
              onTap: () async {
                final f = await DocActions.createFolder(context);
                if (f != null) onSelect(f.id);
              },
              child: Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: g.fill,
                  border: Border.all(color: g.border),
                ),
                alignment: Alignment.center,
                child: PhosphorIcon(PhosphorIconsBold.plus, size: 16, color: g.text),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';

class ShowcaseShell extends StatefulWidget {
  const ShowcaseShell({
    super.key,
    required this.home,
    required this.history,
    required this.pages,
  });
  final Widget home;
  final Widget history;
  final List<WidgetBuilder> pages;
  @override
  State<ShowcaseShell> createState() => _ShowcaseShellState();
}

class _ShowcaseShellState extends State<ShowcaseShell> {
  final _homeKey = GlobalKey();
  bool? _historyDocked;
  bool? _menuDocked;
  bool _sheetOpen = false;
  static const _names = ['Core', 'Knowledge', 'Nexus', 'Storage', 'Workflow'];
  static const _icons = [
    Icons.memory_outlined,
    Icons.auto_stories_outlined,
    Icons.hub_outlined,
    Icons.storage_outlined,
    Icons.account_tree_outlined,
  ];

  Future<void> _openFeature(int index, {required bool wide}) async {
    if (_sheetOpen) return;
    setState(() => _sheetOpen = true);
    final size = MediaQuery.sizeOf(context);
    try {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        showDragHandle: true,
        constraints: BoxConstraints(
          maxWidth: wide ? size.width - 480 : size.width,
        ),
        builder: (context) {
          final keyboard = MediaQuery.viewInsetsOf(context).bottom;
          return Padding(
            padding: EdgeInsets.only(bottom: keyboard),
            child: SizedBox(
              height: (MediaQuery.sizeOf(context).height - keyboard) * 0.85,
              child: Column(
                children: [
                  Row(
                    children: [
                      IconButton(
                        tooltip: 'Close feature',
                        icon: const Icon(Icons.arrow_back),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                      Expanded(
                        child: Text(
                          _names[index],
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ),
                    ],
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 880),
                        child: widget.pages[index](context),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    } finally {
      if (mounted) setState(() => _sheetOpen = false);
    }
  }

  Widget _menu({required bool wide, bool drawer = false}) => Column(
    children: [
      const ListTile(title: Text('Features')),
      for (final (index, name) in _names.take(widget.pages.length).indexed)
        ListTile(
          leading: Icon(_icons[index]),
          title: Text(name),
          enabled: !_sheetOpen,
          onTap: () {
            if (drawer) Navigator.of(context).pop();
            _openFeature(index, wide: wide);
          },
        ),
    ],
  );

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final wide =
          constraints.maxWidth >= 1100 &&
          constraints.maxWidth >= constraints.maxHeight * 1.2;
      final historyShown = wide && (_historyDocked ?? true);
      final menuShown = wide && (_menuDocked ?? true);
      return Scaffold(
        appBar: AppBar(
          title: const Text('Omnix'),
          leading: Builder(
            builder: (context) => IconButton(
              tooltip: 'Chat history',
              icon: const Icon(Icons.history),
              onPressed: () {
                if (wide) {
                  setState(() => _historyDocked = !historyShown);
                } else {
                  Scaffold.of(context).openDrawer();
                }
              },
            ),
          ),
          actions: [
            Builder(
              builder: (context) => IconButton(
                tooltip: 'Feature menu',
                icon: const Icon(Icons.apps),
                onPressed: () {
                  if (wide) {
                    setState(() => _menuDocked = !menuShown);
                  } else {
                    Scaffold.of(context).openEndDrawer();
                  }
                },
              ),
            ),
          ],
        ),
        drawer: wide ? null : Drawer(child: SafeArea(child: widget.history)),
        endDrawer: wide
            ? null
            : Drawer(child: SafeArea(child: _menu(wide: false, drawer: true))),
        body: Row(
          children: [
            if (historyShown) SizedBox(width: 260, child: widget.history),
            if (historyShown) const VerticalDivider(width: 1),
            Expanded(
              child: KeyedSubtree(key: _homeKey, child: widget.home),
            ),
            if (menuShown) const VerticalDivider(width: 1),
            if (menuShown) SizedBox(width: 220, child: _menu(wide: true)),
          ],
        ),
      );
    },
  );
}

@Preview(name: 'Wide home with side panels', size: Size(1366, 768))
@Preview(name: 'Compact home', size: Size(390, 844))
Widget showcasePreview() => MaterialApp(
  theme: ThemeData.dark(),
  home: ShowcaseShell(
    home: const Center(child: Text('Home conversation')),
    history: const Center(child: Text('Chat history')),
    pages: List.generate(
      5,
      (i) =>
          (_) => Center(child: Text('Feature ${i + 1}')),
    ),
  ),
);

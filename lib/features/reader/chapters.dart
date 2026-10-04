import 'package:flutter/material.dart';
import 'package:venera_next/components/appbar.dart';
import 'package:venera_next/components/gesture.dart';
import 'package:venera_next/components/scroll.dart';
import 'package:venera_next/features/comic_source/comic_source.dart';
import 'package:venera_next/features/local_comics/local_comics.dart';
import 'package:venera_next/features/reader/reader_page.dart';
import 'package:venera_next/foundation/context.dart';
import 'package:venera_next/foundation/translations.dart';
import 'package:venera_next/foundation/widget_utils.dart';

const _chapterTileExtent = 48.0;

class ReaderChaptersView extends StatefulWidget {
  const ReaderChaptersView(this.reader, {super.key});

  final ReaderState reader;

  @override
  State<ReaderChaptersView> createState() => ReaderChaptersViewState();
}

class ReaderChaptersViewState extends State<ReaderChaptersView> {
  bool desc = false;

  late final ScrollController _scrollController;

  late final List<MapEntry<String, String>> _chapters;

  var downloaded = <String>{};

  @override
  void initState() {
    super.initState();
    _chapters = widget.reader.widget.chapters!.allChapters.entries.toList(
      growable: false,
    );
    int epIndex = widget.reader.chapter - 2;
    _scrollController = ScrollController(
      initialScrollOffset: (epIndex * _chapterTileExtent + 52).clamp(
        0,
        double.infinity,
      ),
    );
    var local = LocalManager().find(widget.reader.cid, widget.reader.type);
    if (local != null) {
      downloaded = local.downloadedChapters.toSet();
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    var current = widget.reader.chapter - 1;
    return Scaffold(
      body: SmoothCustomScrollView(
        controller: _scrollController,
        slivers: [
          SliverAppbar(
            style: AppbarStyle.shadow,
            title: Text("Chapters".tl),
            actions: [
              Tooltip(
                message: "Click to change the order".tl,
                child: TextButton.icon(
                  icon: Icon(
                    !desc ? Icons.arrow_upward : Icons.arrow_downward,
                    size: 18,
                  ),
                  label: Text(!desc ? "Ascending".tl : "Descending".tl),
                  onPressed: () {
                    setState(() {
                      desc = !desc;
                    });
                  },
                ),
              ),
            ],
          ),
          SliverFixedExtentList(
            itemExtent: _chapterTileExtent,
            delegate: SliverChildBuilderDelegate((context, index) {
              if (desc) {
                index = _chapters.length - 1 - index;
              }
              final chapter = _chapters[index];
              return _ChapterListTile(
                onTap: () {
                  widget.reader.toChapter(index + 1);
                  Navigator.of(context).pop();
                },
                title: chapter.value,
                isActive: current == index,
                isDownloaded: downloaded.contains(chapter.key),
              );
            }, childCount: _chapters.length),
          ),
        ],
      ),
    );
  }
}

class ReaderGroupedChaptersView extends StatefulWidget {
  const ReaderGroupedChaptersView(this.reader, {super.key});

  final ReaderState reader;

  @override
  State<ReaderGroupedChaptersView> createState() =>
      ReaderGroupedChaptersViewState();
}

class ReaderGroupedChaptersViewState extends State<ReaderGroupedChaptersView>
    with SingleTickerProviderStateMixin {
  ComicChapters get chapters => widget.reader.widget.chapters!;

  late final TabController tabController;

  late final ScrollController _scrollController;

  late final String initialGroupName;

  late final List<_ChapterGroup> _groups;

  var downloaded = <String>{};

  @override
  void initState() {
    super.initState();
    _groups = [];
    var firstChapter = 1;
    for (final name in chapters.groups) {
      final entries = chapters.getGroup(name).entries.toList(growable: false);
      _groups.add(_ChapterGroup(name, entries, firstChapter));
      firstChapter += entries.length;
    }
    int index = 0;
    int epIndex = widget.reader.chapter - 1;
    while (epIndex >= _groups[index].chapters.length) {
      epIndex -= _groups[index].chapters.length;
      index++;
    }
    tabController = TabController(
      length: _groups.length,
      vsync: this,
      initialIndex: index,
    );
    initialGroupName = _groups[index].name;
    _scrollController = ScrollController(
      initialScrollOffset: (epIndex * _chapterTileExtent).clamp(
        0,
        double.infinity,
      ),
    );
    var local = LocalManager().find(widget.reader.cid, widget.reader.type);
    if (local != null) {
      downloaded = local.downloadedChapters.toSet();
    }
  }

  @override
  void dispose() {
    tabController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Appbar(title: Text("Chapters".tl)),
        AppTabBar(
          controller: tabController,
          tabs: _groups.map((group) => Tab(text: group.name)).toList(),
        ),
        Expanded(
          child: TabViewBody(
            controller: tabController,
            children: _groups.map(_buildGroup).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildGroup(_ChapterGroup group) {
    return SmoothCustomScrollView(
      controller: initialGroupName == group.name ? _scrollController : null,
      slivers: [
        SliverFixedExtentList(
          itemExtent: _chapterTileExtent,
          delegate: SliverChildBuilderDelegate((context, index) {
            final chapter = group.chapters[index];
            final i = group.firstChapter + index;
            return _ChapterListTile(
              onTap: () {
                widget.reader.toChapter(i);
                context.pop();
              },
              title: chapter.value,
              isActive: widget.reader.chapter == i,
              isDownloaded: downloaded.contains(chapter.key),
            );
          }, childCount: group.chapters.length),
        ),
      ],
    );
  }
}

class _ChapterGroup {
  const _ChapterGroup(this.name, this.chapters, this.firstChapter);

  final String name;
  final List<MapEntry<String, String>> chapters;
  final int firstChapter;
}

class _ChapterListTile extends StatelessWidget {
  const _ChapterListTile({
    required this.title,
    required this.isActive,
    required this.isDownloaded,
    required this.onTap,
  });

  final String title;

  final bool isActive;

  final bool isDownloaded;

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ClickInkWell(
      onTap: onTap,
      child: Container(
        height: _chapterTileExtent,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          border: Border(
            left: BorderSide(
              color: isActive
                  ? context.colorScheme.primary
                  : Colors.transparent,
              width: 4,
            ),
          ),
        ),
        child: Row(
          children: [
            Text(
              title,
              style: isActive
                  ? ts.withColor(context.colorScheme.primary).bold.s16
                  : ts.s16,
            ),
            const Spacer(),
            if (isDownloaded)
              Icon(
                Icons.download_done_rounded,
                color: context.colorScheme.secondary,
              ),
          ],
        ),
      ),
    );
  }
}

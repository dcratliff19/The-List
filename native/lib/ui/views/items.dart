part of '../workspace.dart';

extension _WorkspaceItemsView on _WorkspaceState {
  Widget itemsView(List<Entry> list, bool wide) {
    list = list.where(matches).toList();
    if (list.isEmpty) {
      return empty(
        query.isNotEmpty ? 'Nothing matches yet.' : 'An idea belongs here.',
        query.isNotEmpty
            ? 'Try a different word or clear your search.'
            : 'Save a link, write a note, or add a photo.',
        Icons.bookmark_border,
      );
    }
    return LayoutBuilder(
      builder: (context, s) {
        final cols = s.maxWidth > 1050
            ? 3
            : s.maxWidth > 580
            ? 2
            : 1;
        return Wrap(
          spacing: 18,
          runSpacing: 18,
          children: list
              .map(
                (e) => SizedBox(
                  width: (s.maxWidth - (cols - 1) * 18) / cols,
                  child: itemCard(e),
                ),
              )
              .toList(),
        );
      },
    );
  }

  Widget previewStatus(Entry entry, {bool compact = false}) => PreviewStatus(
    status: entry.text('previewStatus'),
    error: entry.text('previewError'),
    compact: compact,
    onRetry: store.canEdit(entry.project)
        ? () => act(() => media.preview(entry, force: true))
        : null,
  );

  Widget itemCard(Entry e) {
    final photo = e.text('photo');
    final hasPhoto = photo.isNotEmpty && store.blob(photo).existsSync();
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: e.kind == 'note'
          ? Color.lerp(surface, const Color(0xfffff3d7), .2)
          : surface,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(13),
        side: BorderSide(color: muted.withValues(alpha: .14)),
      ),
      child: InkWell(
        onTap: () => detail(e),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (hasPhoto)
              Image.file(
                store.blob(photo),
                height: 162,
                width: double.infinity,
                fit: BoxFit.cover,
              )
            else if (e.kind == 'link')
              Container(
                height: 123,
                padding: const EdgeInsets.all(23),
                color:
                    (domain(e).length.isEven
                            ? const Color(0xffccd8ce)
                            : const Color(0xffdbd6e9))
                        .withValues(alpha: .7),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        domain(e),
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w600,
                          color: Color(0xff4b5450),
                          letterSpacing: -1,
                        ),
                      ),
                    ),
                    Icon(Icons.north_east, size: 21, color: Color(0xff4b5450)),
                  ],
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(21, 14, 21, 19),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        e.kind == 'link'
                            ? Icons.link
                            : e.kind == 'photo'
                            ? Icons.photo_outlined
                            : Icons.notes,
                        size: 12,
                        color: muted,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          e.kind == 'link' ? domain(e) : e.kind.toUpperCase(),
                          style: TextStyle(
                            fontSize: 9,
                            letterSpacing: e.kind == 'link' ? 0 : 1.4,
                            color: muted,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () => store.canEdit(e.project)
                            ? store.update(e, {'favorite': !e.flag('favorite')})
                            : message('This project is read-only.'),
                        tooltip: e.flag('favorite')
                            ? 'Remove favorite'
                            : 'Favorite',
                        visualDensity: VisualDensity.compact,
                        icon: Icon(
                          e.flag('favorite')
                              ? Icons.star_rounded
                              : Icons.star_border_rounded,
                          size: 17,
                          color: e.flag('favorite') ? accent : muted,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    e.title.isEmpty ? e.text('previewTitle') : e.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      height: 1.4,
                      letterSpacing: -.3,
                    ),
                  ),
                  if (e.kind == 'link') previewStatus(e, compact: true),
                  if (e.kind == 'link' && e.priceLabel.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        e.priceLabel,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  if (e.text('body').isNotEmpty ||
                      e.text('previewDescription').isNotEmpty) ...[
                    const SizedBox(height: 11),
                    Text(
                      e.text('body').isNotEmpty
                          ? e.text('body')
                          : e.text('previewDescription'),
                      maxLines: e.kind == 'note' ? 7 : 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: muted, height: 1.8),
                    ),
                  ],
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      if (e.text('tags').isNotEmpty)
                        Flexible(
                          child: Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: e.tags.map(statusBadge).toList(),
                          ),
                        ),
                      const Spacer(),
                      Text(
                        e.text('created').length >= 10
                            ? e.text('created').substring(0, 10)
                            : '',
                        style: TextStyle(fontSize: 9, color: muted),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

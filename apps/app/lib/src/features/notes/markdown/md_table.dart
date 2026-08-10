/// A GFM table that scrolls inside its own box (DESIGN §29 D8, OPH-247).
///
/// Alignment comes from the parser, not from us: `TableSyntax` already reads
/// the `:---:` delimiter row and stamps `align="left|center|right"` on each
/// cell. The first coverage measurement reported alignment as MISSING and was
/// wrong — it looked for a CSS `text-align` the package never emits. That
/// mistake is why this file reads the attribute instead of re-parsing the row.
///
/// Built on Flutter's own [Table] rather than nested rows. Hand-rolled rows
/// were tried first and produced two layout failures in a row — infinite
/// height from `CrossAxisAlignment.stretch` inside a horizontal scroll view,
/// then a 496 px overflow once that was bounded — because column sizing and
/// equal-height rows are exactly the problem [Table] already solves.
library;

import 'package:flutter/material.dart';

import '../../../theme/tokens.dart';
import 'md_theme.dart';

/// A cell wider than this wraps instead of stretching the table across the
/// screen. Long prose in one column is common in READMEs.
const double kMdTableMaxCellWidth = 320;

class MdTable extends StatelessWidget {
  const MdTable({super.key, required this.header, required this.rows});

  /// Header cells, already built. Empty when the table has no head.
  final List<MdTableCell> header;
  final List<List<MdTableCell>> rows;

  @override
  Widget build(BuildContext context) {
    final styles = MdStyles.of(context);
    final columns = [
      header.length,
      ...rows.map((r) => r.length),
    ].fold(0, (a, b) => a > b ? a : b);
    if (columns == 0) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.symmetric(vertical: AwSpace.x2),
      decoration: BoxDecoration(
        borderRadius: const BorderRadius.all(Radius.circular(AwRadius.m)),
        border: Border.all(color: styles.hairline),
      ),
      clipBehavior: Clip.antiAlias,
      child: LayoutBuilder(
        builder: (context, constraints) {
          // D8: the TABLE scrolls, never the page. The minimum width keeps a
          // narrow table filling its container instead of huddling left.
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minWidth: constraints.hasBoundedWidth
                    ? constraints.maxWidth
                    : 0,
              ),
              child: Table(
                defaultColumnWidth: const IntrinsicColumnWidth(),
                defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                border: TableBorder.symmetric(
                  inside: BorderSide(color: styles.hairline),
                ),
                children: [
                  if (header.isNotEmpty)
                    _row(header, columns, styles, isHeader: true),
                  for (final row in rows) _row(row, columns, styles),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  TableRow _row(
    List<MdTableCell> cells,
    int columns,
    MdStyles styles, {
    bool isHeader = false,
  }) {
    return TableRow(
      decoration: isHeader
          ? BoxDecoration(color: styles.tableHeaderFill)
          : null,
      children: [
        for (var i = 0; i < columns; i++)
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AwSpace.x3,
              vertical: AwSpace.x2,
            ),
            child: Align(
              alignment: i < cells.length
                  ? cells[i].alignment
                  : Alignment.centerLeft,
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: kMdTableMaxCellWidth,
                ),
                child: DefaultTextStyle.merge(
                  style: isHeader
                      ? const TextStyle(fontWeight: FontWeight.w700)
                      : null,
                  // A ragged row (fewer cells than the widest) still needs a
                  // child per column or `Table` asserts.
                  child: i < cells.length
                      ? cells[i].content
                      : const SizedBox.shrink(),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// One cell: its content and the alignment the delimiter row asked for.
class MdTableCell {
  const MdTableCell({required this.content, this.align});

  final Widget content;

  /// `left` | `center` | `right`, verbatim from the parser's `align` attribute.
  final String? align;

  Alignment get alignment => switch (align) {
    'center' => Alignment.center,
    'right' => Alignment.centerRight,
    _ => Alignment.centerLeft,
  };
}

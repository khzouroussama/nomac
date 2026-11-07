# ADR 0254: the order of ibtool's warnings where ids collide is an equivalent difference

- Status: accepted
- Date: 2026-11-07

## Context

ibtool prints a document's warnings in the order of a Foundation hash table of their objects' ids
(docs/formats/nib.md). Where ids meet in the table, the order follows the order they entered it.
14 of the 85 surveyed documents that differed from Xcode's had the same warnings as ibtool in
another order, and no order of entering them fit: labels in one view, none deeper than another,
needed orders unrelated to the document's or their frames.

`warn-adjusts-order-doc` compiled the same document seven times, four labels whose ids collide in
seven buckets. ibtool printed four different orders in those runs, and its nib was the same every
time.

## Decision

nomac prints the warnings in the order of the table its ids enter in document order. `nib_compare.py`
counts warnings that differ only in their order as equivalent, not identical, when the files agree.
A different set of warnings stays a difference.

## Consequences

The nibs, which are what a build keeps, are not affected. A build log's warnings can come in another
order than Xcode's, as they can from one Xcode run to the next.

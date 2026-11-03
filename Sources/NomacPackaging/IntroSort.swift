/// libc++'s `std::sort` with a comparator of its own (LLVM's open-source `__introsort` as
/// Xcode 27.0's SDK ships it): introsort with median-of-three or ninther pivots, partitions that
/// gather equal elements, insertion sort below 24 elements and heap sort past `2 log2 n` levels.
/// It does not keep equal elements in order; the name indexes of `.symbols` files show its order
/// for symbols that share a name (`signing_experiments.py symbols`).
enum IntroSort {
    static func sort<Element>(_ elements: inout [Element], by less: @escaping (Element, Element) -> Bool) {
        guard elements.count > 1 else { return }
        var sorter = Sorter(elements: elements, less: less)
        sorter.introsort(0, elements.count, depth: 2 * (Int.bitWidth - 1 - elements.count.leadingZeroBitCount), leftmost: true)
        elements = sorter.elements
    }

    private struct Sorter<Element> {
        var elements: [Element]
        let less: (Element, Element) -> Bool

        func lt(_ i: Int, _ j: Int) -> Bool { less(elements[i], elements[j]) }

        mutating func swapAt(_ i: Int, _ j: Int) { elements.swapAt(i, j) }

        @discardableResult
        mutating func sort3(_ x: Int, _ y: Int, _ z: Int) -> Bool {
            if !lt(y, x) {
                if !lt(z, y) { return false }
                swapAt(y, z)
                if lt(y, x) { swapAt(x, y) }
                return true
            }
            if lt(z, y) {
                swapAt(x, z)
                return true
            }
            swapAt(x, y)
            if lt(z, y) { swapAt(y, z) }
            return true
        }

        mutating func sort4(_ x1: Int, _ x2: Int, _ x3: Int, _ x4: Int) {
            sort3(x1, x2, x3)
            if lt(x4, x3) {
                swapAt(x3, x4)
                if lt(x3, x2) {
                    swapAt(x2, x3)
                    if lt(x2, x1) { swapAt(x1, x2) }
                }
            }
        }

        mutating func sort5(_ x1: Int, _ x2: Int, _ x3: Int, _ x4: Int, _ x5: Int) {
            sort4(x1, x2, x3, x4)
            if lt(x5, x4) {
                swapAt(x4, x5)
                if lt(x4, x3) {
                    swapAt(x3, x4)
                    if lt(x3, x2) {
                        swapAt(x2, x3)
                        if lt(x2, x1) { swapAt(x1, x2) }
                    }
                }
            }
        }

        /// Shifts `elements[i]` left past the larger elements before it, down to `first` when
        /// `guarded`, else until an element that is not larger (one always exists).
        mutating func shift(_ i: Int, first: Int, guarded: Bool) {
            let value = elements[i]
            var hole = i, k = i - 1
            repeat {
                elements[hole] = elements[k]
                hole = k
                if guarded, hole == first { break }
                k -= 1
            } while less(value, elements[k])
            elements[hole] = value
        }

        mutating func insertionSort(_ first: Int, _ last: Int, guarded: Bool) {
            guard first < last else { return }
            for i in (first + 1)..<last where lt(i, i - 1) {
                shift(i, first: first, guarded: guarded)
            }
        }

        /// Sorts small ranges completely; larger ones until eight elements have moved. Returns
        /// whether the range is sorted.
        mutating func insertionSortIncomplete(_ first: Int, _ last: Int) -> Bool {
            switch last - first {
            case 0, 1: return true
            case 2:
                if lt(last - 1, first) { swapAt(first, last - 1) }
                return true
            case 3: sort3(first, first + 1, last - 1); return true
            case 4: sort4(first, first + 1, first + 2, last - 1); return true
            case 5: sort5(first, first + 1, first + 2, first + 3, last - 1); return true
            default: break
            }
            sort3(first, first + 1, first + 2)
            var moved = 0
            var i = first + 3
            while i != last {
                if lt(i, i - 1) {
                    shift(i, first: first, guarded: true)
                    moved += 1
                    if moved == 8 { return i + 1 == last }
                }
                i += 1
            }
            return true
        }

        /// Partitions around `elements[first]`, equal elements to the right; returns the pivot's
        /// position and whether the range was already partitioned.
        mutating func partitionEqualsOnRight(_ start: Int, _ end: Int) -> (Int, Bool) {
            let pivot = elements[start]
            var first = start, last = end
            repeat { first += 1 } while less(elements[first], pivot)
            if start == first - 1 {
                while first < last {
                    last -= 1
                    if less(elements[last], pivot) { break }
                }
            } else {
                repeat { last -= 1 } while !less(elements[last], pivot)
            }
            let alreadyPartitioned = first >= last
            while first < last {
                swapAt(first, last)
                repeat { first += 1 } while less(elements[first], pivot)
                repeat { last -= 1 } while !less(elements[last], pivot)
            }
            let pivotPosition = first - 1
            if start != pivotPosition { elements[start] = elements[pivotPosition] }
            elements[pivotPosition] = pivot
            return (pivotPosition, alreadyPartitioned)
        }

        /// Partitions around `elements[first]`, equal elements to the left; returns where the
        /// larger elements start.
        mutating func partitionEqualsOnLeft(_ start: Int, _ end: Int) -> Int {
            let pivot = elements[start]
            var first = start, last = end
            if less(pivot, elements[end - 1]) {
                repeat { first += 1 } while !less(pivot, elements[first])
            } else {
                first += 1
                while first < last, !less(pivot, elements[first]) { first += 1 }
            }
            if first < last {
                repeat { last -= 1 } while less(pivot, elements[last])
            }
            while first < last {
                swapAt(first, last)
                repeat { first += 1 } while !less(pivot, elements[first])
                repeat { last -= 1 } while less(pivot, elements[last])
            }
            let pivotPosition = first - 1
            if start != pivotPosition { elements[start] = elements[pivotPosition] }
            elements[pivotPosition] = pivot
            return first
        }

        mutating func introsort(_ start: Int, _ end: Int, depth: Int, leftmost: Bool) {
            var first = start, last = end, depth = depth, leftmost = leftmost
            while true {
                let length = last - first
                switch length {
                case 0, 1: return
                case 2:
                    if lt(last - 1, first) { swapAt(first, last - 1) }
                    return
                case 3: sort3(first, first + 1, last - 1); return
                case 4: sort4(first, first + 1, first + 2, last - 1); return
                case 5: sort5(first, first + 1, first + 2, first + 3, last - 1); return
                default: break
                }
                if length < 24 {
                    insertionSort(first, last, guarded: leftmost)
                    return
                }
                if depth == 0 {
                    heapSort(first, last)
                    return
                }
                depth -= 1
                let half = length / 2
                if length > 128 {
                    sort3(first, first + half, last - 1)
                    sort3(first + 1, first + half - 1, last - 2)
                    sort3(first + 2, first + half + 1, last - 3)
                    sort3(first + half - 1, first + half, first + half + 1)
                    swapAt(first, first + half)
                } else {
                    sort3(first + half, first, last - 1)
                }
                if !leftmost, !lt(first - 1, first) {
                    first = partitionEqualsOnLeft(first, last)
                    continue
                }
                let (pivot, alreadyPartitioned) = partitionEqualsOnRight(first, last)
                if alreadyPartitioned {
                    let leftSorted = insertionSortIncomplete(first, pivot)
                    if insertionSortIncomplete(pivot + 1, last) {
                        if leftSorted { return }
                        last = pivot
                        continue
                    } else if leftSorted {
                        first = pivot + 1
                        continue
                    }
                }
                introsort(first, pivot, depth: depth, leftmost: leftmost)
                leftmost = false
                first = pivot + 1
            }
        }

        /// `std::partial_sort(first, last, last)`: a heap, then repeated pops, for elements that
        /// are not arithmetic types.
        mutating func heapSort(_ first: Int, _ last: Int) {
            let count = last - first
            if count > 1 {
                for start in stride(from: (count - 2) / 2, through: 0, by: -1) {
                    siftDown(first, count, start)
                }
            }
            var size = count
            while size > 1 {
                popHeap(first, first + size, size)
                size -= 1
            }
        }

        mutating func siftDown(_ first: Int, _ length: Int, _ start: Int) {
            var start = start
            var child = start
            if length < 2 || (length - 2) / 2 < child { return }
            child = 2 * child + 1
            if child + 1 < length, lt(first + child, first + child + 1) { child += 1 }
            if lt(first + child, first + start) { return }
            let top = elements[first + start]
            repeat {
                elements[first + start] = elements[first + child]
                start = child
                if (length - 2) / 2 < child { break }
                child = 2 * child + 1
                if child + 1 < length, lt(first + child, first + child + 1) { child += 1 }
            } while !less(elements[first + child], top)
            elements[first + start] = top
        }

        mutating func popHeap(_ first: Int, _ last: Int, _ length: Int) {
            guard length > 1 else { return }
            let top = elements[first]
            var hole = first, child = 0, childIndex = first
            while true {
                childIndex += child + 1
                child = 2 * child + 1
                if child + 1 < length, lt(childIndex, childIndex + 1) {
                    childIndex += 1
                    child += 1
                }
                elements[hole] = elements[childIndex]
                hole = childIndex
                if child > (length - 2) / 2 { break }
            }
            let end = last - 1
            if hole == end {
                elements[hole] = top
            } else {
                elements[hole] = elements[end]
                elements[end] = top
                siftUp(first, hole + 1, hole + 1 - first)
            }
        }

        mutating func siftUp(_ first: Int, _ last: Int, _ length: Int) {
            guard length > 1 else { return }
            var length = (length - 2) / 2
            var position = first + length
            var last = last - 1
            if lt(position, last) {
                let value = elements[last]
                repeat {
                    elements[last] = elements[position]
                    last = position
                    if length == 0 { break }
                    length = (length - 1) / 2
                    position = first + length
                } while less(elements[position], value)
                elements[last] = value
            }
        }
    }
}

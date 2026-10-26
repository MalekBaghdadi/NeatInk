import '../../document/notebook_meta.dart';

/// A folder together with its depth in the tree (0 = top level).
class FolderDepth {
  const FolderDepth(this.folder, this.depth);
  final Folder folder;
  final int depth;
}

/// Read-only view of the folder hierarchy in a [LibraryIndex].
///
/// `library.json` is user data on disk, so this class never trusts it:
/// a folder whose parent no longer exists, or a set of folders whose parent
/// links form a cycle, is treated as sitting at the top level. That way no
/// folder (and no notebook inside one) can ever become unreachable.
class FolderTree {
  FolderTree(LibraryIndex library) : folders = library.folders {
    for (final f in folders) {
      _byId[f.id] = f;
    }
    for (final f in folders) {
      final p = f.parentId;
      _parent[f.id] = p != null && p != f.id && _byId.containsKey(p) ? p : null;
    }
    _breakCycles();
    for (final f in folders) {
      _children.putIfAbsent(_parent[f.id], () => []).add(f);
    }
    for (final list in _children.values) {
      list.sort(compareFolderNames);
    }
  }

  final List<Folder> folders;
  final Map<String, Folder> _byId = {};
  final Map<String, String?> _parent = {};
  final Map<String?, List<Folder>> _children = {};

  /// Walks up from every folder; the first folder seen twice on one walk is
  /// part of a cycle, and cutting its parent link breaks that cycle.
  void _breakCycles() {
    for (final f in folders) {
      final seen = <String>{};
      String? cur = f.id;
      while (cur != null) {
        if (!seen.add(cur)) {
          _parent[cur] = null;
          break;
        }
        cur = _parent[cur];
      }
    }
  }

  Folder? byId(String? id) => id == null ? null : _byId[id];

  bool contains(String? id) => id != null && _byId.containsKey(id);

  /// The effective parent of [id] (null = top level or unknown folder).
  String? parentOf(String id) => _parent[id];

  /// Direct subfolders of [parentId] (null = top level), sorted by name.
  List<Folder> childrenOf(String? parentId) =>
      List.unmodifiable(_children[parentId] ?? const <Folder>[]);

  bool hasChildren(String id) => _children[id]?.isNotEmpty ?? false;

  /// Ids of every folder below [id] (not including [id] itself).
  Set<String> descendantsOf(String id) {
    final result = <String>{};
    final stack = <String>[id];
    while (stack.isNotEmpty) {
      for (final child in _children[stack.removeLast()] ?? const <Folder>[]) {
        if (result.add(child.id)) stack.add(child.id);
      }
    }
    return result;
  }

  /// Folders from the top level down to [id] inclusive. Empty for the root
  /// or an unknown id.
  List<Folder> pathTo(String? id) {
    final path = <Folder>[];
    var cur = id;
    while (cur != null) {
      final f = _byId[cur];
      if (f == null) break;
      path.add(f);
      cur = _parent[cur];
    }
    return path.reversed.toList();
  }

  /// Whether [folderId] may be moved under [newParentId] (null = top level).
  /// A folder can't go into itself or into one of its own subfolders.
  bool canMove(String folderId, String? newParentId) {
    if (!contains(folderId)) return false;
    if (newParentId == null) return true;
    if (!contains(newParentId) || newParentId == folderId) return false;
    return !descendantsOf(folderId).contains(newParentId);
  }

  /// Every folder in depth-first display order (children sorted by name).
  /// Folders in [exclude] are skipped together with their subtrees.
  List<FolderDepth> flatten({Set<String> exclude = const {}}) {
    final out = <FolderDepth>[];
    void visit(String? parent, int depth) {
      for (final f in _children[parent] ?? const <Folder>[]) {
        if (exclude.contains(f.id)) continue;
        out.add(FolderDepth(f, depth));
        visit(f.id, depth + 1);
      }
    }

    visit(null, 0);
    return out;
  }
}

/// Case-insensitive, number-aware name order ("Week 2" before "Week 10").
int compareFolderNames(Folder a, Folder b) {
  final c = naturalCompare(a.name, b.name);
  return c != 0 ? c : a.id.compareTo(b.id);
}

/// Compares strings case-insensitively, treating runs of digits as numbers,
/// so "Notebook 9" sorts before "Notebook 10".
int naturalCompare(String a, String b) {
  final x = a.toLowerCase(), y = b.toLowerCase();
  var i = 0, j = 0;
  while (i < x.length && j < y.length) {
    final cx = x.codeUnitAt(i), cy = y.codeUnitAt(j);
    if (_isDigit(cx) && _isDigit(cy)) {
      final si = i, sj = j;
      while (i < x.length && _isDigit(x.codeUnitAt(i))) {
        i++;
      }
      while (j < y.length && _isDigit(y.codeUnitAt(j))) {
        j++;
      }
      // Compare digit runs by value without parsing (they can be long):
      // strip leading zeros, then the longer run is larger.
      final nx = _stripZeros(x.substring(si, i));
      final ny = _stripZeros(y.substring(sj, j));
      if (nx.length != ny.length) return nx.length - ny.length;
      final c = nx.compareTo(ny);
      if (c != 0) return c;
    } else {
      if (cx != cy) return cx - cy;
      i++;
      j++;
    }
  }
  final rest = (x.length - i) - (y.length - j);
  if (rest != 0) return rest;
  // Equal ignoring case: fall back to a case-sensitive order so the result
  // is stable.
  return a.compareTo(b);
}

bool _isDigit(int c) => c >= 0x30 && c <= 0x39;

String _stripZeros(String digits) {
  var k = 0;
  while (k < digits.length - 1 && digits.codeUnitAt(k) == 0x30) {
    k++;
  }
  return digits.substring(k);
}

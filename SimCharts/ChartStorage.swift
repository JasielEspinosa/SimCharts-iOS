import Foundation

/// One row of the "Downloaded Charts" tree.
struct TreeNode: Identifiable {
    let key: String
    let name: String
    let url: URL
    let isFile: Bool
    let children: [TreeNode]
    var id: String { key }
}

/// Narrows the tree to the files matching [query]: every space-separated word must appear (case-insensitive)
/// in the file name or in the names of its parent folders. Matching files keep their parent folders.
/// Returns new nodes (the input is not changed). A blank query returns the tree as it is.
func filterTree(_ nodes: [TreeNode], _ query: String) -> [TreeNode] {
    let words = query.split(whereSeparator: { $0.isWhitespace }).map { String($0) }
    if words.isEmpty { return nodes }

    func walk(_ list: [TreeNode], _ parents: String) -> [TreeNode] {
        var out: [TreeNode] = []
        for n in list {
            let text = parents + "\n" + n.name
            if n.isFile {
                if words.allSatisfy({ text.range(of: $0, options: .caseInsensitive) != nil }) { out.append(n) }
            } else {
                let kids = walk(n.children, text)
                if !kids.isEmpty {
                    out.append(TreeNode(key: n.key, name: n.name, url: n.url, isFile: false, children: kids))
                }
            }
        }
        return out
    }
    return walk(nodes, "")
}

func countFiles(_ nodes: [TreeNode]) -> Int {
    nodes.reduce(0) { $0 + ($1.isFile ? 1 : countFiles($1.children)) }
}

func countFiles(_ node: TreeNode) -> Int {
    node.isFile ? 1 : countFiles(node.children)
}

func folderKeys(_ nodes: [TreeNode]) -> Set<String> {
    var out = Set<String>()
    func walk(_ list: [TreeNode]) {
        for n in list where !n.isFile {
            out.insert(n.key)
            walk(n.children)
        }
    }
    walk(nodes)
    return out
}

/// The charts live in the app's Documents folder, which the Files app shows as "On My iPhone > SimCharts".
enum ChartStorage {
    static var root: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    static var cacheDir: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
    }

    @discardableResult
    static func ensureDir(_ parent: URL, _ name: String) throws -> URL {
        let dir = parent.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Deletes a file or a folder with everything inside it. Returns true if it is gone.
    static func delete(_ url: URL) -> Bool {
        do {
            try FileManager.default.removeItem(at: url)
            return true
        } catch {
            return !FileManager.default.fileExists(atPath: url.path)
        }
    }

    /// Country folders -> airport folders -> PDF files.
    static func scan(_ dir: URL, prefix: String = "", depth: Int = 0) -> [TreeNode] {
        if depth > 5 { return [] }
        let keys: [URLResourceKey] = [.isDirectoryKey]
        guard let items = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]) else { return [] }

        func isDir(_ u: URL) -> Bool { (try? u.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false }
        func byName(_ a: URL, _ b: URL) -> Bool { a.lastPathComponent.lowercased() < b.lastPathComponent.lowercased() }

        let dirs = items.filter { isDir($0) }.sorted(by: byName)
        let files = items.filter { !isDir($0) && $0.pathExtension.lowercased() == "pdf" }.sorted(by: byName)

        var result: [TreeNode] = []
        for d in dirs {
            let n = d.lastPathComponent
            let key = "\(prefix)/\(n)"
            result.append(TreeNode(key: key, name: n, url: d, isFile: false, children: scan(d, prefix: key, depth: depth + 1)))
        }
        for f in files {
            let n = f.lastPathComponent
            result.append(TreeNode(key: "\(prefix)/\(n)", name: n, url: f, isFile: true, children: []))
        }
        return result
    }
}

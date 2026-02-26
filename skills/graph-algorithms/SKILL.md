---
name: graph-algorithms
description: Directed graph representation, cycle detection, topological sorting, dagre-style layered layout, graph traversal (DFS/BFS), shortest path algorithms (Dijkstra/Bellman-Ford), strongly connected components (Tarjan's), crossing reduction heuristics, coordinate assignment, and widget tree to graph layout pipeline in Dart 3.x
---

# Graph Algorithms for Parser/Compiler Engineers in Dart

Comprehensive reference for implementing directed graph data structures and algorithms in Dart 3.x. Covers everything from basic graph representation through advanced layered graph layout (dagre-style), with emphasis on practical compiler and parser engineering use cases such as dependency resolution, widget tree layout, and IR graph visualization.

## Table of Contents

1. [Directed Graph Representation](#directed-graph-representation)
   - [Adjacency List](#adjacency-list)
   - [Edge List](#edge-list)
   - [Adjacency Matrix](#adjacency-matrix)
2. [Graph Traversal](#graph-traversal)
   - [Depth-First Search (DFS)](#depth-first-search-dfs)
   - [Breadth-First Search (BFS)](#breadth-first-search-bfs)
   - [Iterative Deepening DFS](#iterative-deepening-dfs)
3. [Cycle Detection](#cycle-detection)
   - [DFS-Based Cycle Detection](#dfs-based-cycle-detection)
   - [Kahn's Algorithm for Cycle Detection](#kahns-algorithm-for-cycle-detection)
4. [Topological Sorting](#topological-sorting)
   - [DFS Post-Order Topological Sort](#dfs-post-order-topological-sort)
   - [Kahn's BFS Topological Sort](#kahns-bfs-topological-sort)
5. [Shortest Path Algorithms](#shortest-path-algorithms)
   - [Dijkstra's Algorithm](#dijkstras-algorithm)
   - [Bellman-Ford Algorithm](#bellman-ford-algorithm)
6. [Connected Components](#connected-components)
   - [Weakly Connected Components](#weakly-connected-components)
   - [Strongly Connected Components (Tarjan's)](#strongly-connected-components-tarjans)
7. [Dagre-Style Layered Graph Layout](#dagre-style-layered-graph-layout)
   - [Overview of the Sugiyama Framework](#overview-of-the-sugiyama-framework)
   - [Layer Assignment](#layer-assignment)
   - [Crossing Reduction](#crossing-reduction)
   - [Coordinate Assignment](#coordinate-assignment)
8. [Practical Application: Widget Tree to Graph Layout](#practical-application-widget-tree-to-graph-layout)
9. [Best Practices](#best-practices)
10. [Anti-Patterns](#anti-patterns)
11. [Sources & References](#sources--references)

---

## Directed Graph Representation

Choosing the right graph representation is critical for algorithm performance. The three primary representations each have distinct trade-offs in memory usage, edge lookup time, and iteration efficiency.

### Adjacency List

The adjacency list is the most common representation for sparse graphs (which most compiler/parser graphs are). Each node maps to a list of its outgoing neighbors. This gives O(V + E) space and O(degree(v)) neighbor lookup.

For directed graphs in compiler engineering (dependency graphs, control flow graphs, widget trees), adjacency lists are almost always the correct choice because these graphs are typically sparse -- each node connects to a small number of other nodes relative to the total number of nodes.

```dart
/// Core directed graph using adjacency list representation.
///
/// Generic over node identifier type [T]. Supports weighted edges
/// via the [WeightedDirectedGraph] subclass.
class DirectedGraph<T> {
  final Map<T, Set<T>> _adjacency = {};

  /// All nodes in the graph, including isolated nodes with no edges.
  Set<T> get nodes => _adjacency.keys.toSet();

  /// Total number of edges in the graph.
  int get edgeCount => _adjacency.values.fold(0, (sum, s) => sum + s.length);

  /// Add a node without any edges. Idempotent.
  void addNode(T node) {
    _adjacency.putIfAbsent(node, () => {});
  }

  /// Add a directed edge from [source] to [target].
  /// Both nodes are created if they do not exist.
  void addEdge(T source, T target) {
    _adjacency.putIfAbsent(source, () => {}).add(target);
    _adjacency.putIfAbsent(target, () => {});
  }

  /// Remove a directed edge. Returns true if the edge existed.
  bool removeEdge(T source, T target) {
    return _adjacency[source]?.remove(target) ?? false;
  }

  /// Remove a node and all edges incident to it.
  void removeNode(T node) {
    _adjacency.remove(node);
    for (final neighbors in _adjacency.values) {
      neighbors.remove(node);
    }
  }

  /// Direct successors of [node].
  Set<T> successors(T node) => Set.unmodifiable(_adjacency[node] ?? {});

  /// Direct predecessors of [node] (O(V + E) scan).
  Set<T> predecessors(T node) {
    return _adjacency.entries
        .where((entry) => entry.value.contains(node))
        .map((entry) => entry.key)
        .toSet();
  }

  /// Whether an edge from [source] to [target] exists.
  bool hasEdge(T source, T target) {
    return _adjacency[source]?.contains(target) ?? false;
  }

  /// Whether the graph contains [node].
  bool hasNode(T node) => _adjacency.containsKey(node);

  /// In-degree of [node]: number of edges pointing to it.
  int inDegree(T node) {
    var count = 0;
    for (final neighbors in _adjacency.values) {
      if (neighbors.contains(node)) count++;
    }
    return count;
  }

  /// Out-degree of [node]: number of edges leaving it.
  int outDegree(T node) => _adjacency[node]?.length ?? 0;

  /// Returns a new graph with all edge directions reversed.
  DirectedGraph<T> reversed() {
    final result = DirectedGraph<T>();
    for (final node in nodes) {
      result.addNode(node);
    }
    for (final entry in _adjacency.entries) {
      for (final target in entry.value) {
        result.addEdge(target, entry.key);
      }
    }
    return result;
  }

  /// Returns a deep copy of this graph.
  DirectedGraph<T> copy() {
    final result = DirectedGraph<T>();
    for (final entry in _adjacency.entries) {
      result._adjacency[entry.key] = Set.of(entry.value);
    }
    return result;
  }

  @override
  String toString() {
    final buffer = StringBuffer('DirectedGraph(\n');
    for (final entry in _adjacency.entries) {
      buffer.writeln('  ${entry.key} -> ${entry.value.join(', ')}');
    }
    buffer.write(')');
    return buffer.toString();
  }
}
```

Key design decisions for the adjacency list implementation:

- **`Set<T>` for neighbors**: Prevents duplicate edges and gives O(1) `contains` checks. Use `List<T>` instead only if you need multigraph support (multiple edges between the same pair of nodes).
- **`putIfAbsent` in `addEdge`**: Ensures both source and target are always present in the node set, preventing orphan references.
- **`predecessors` is O(V + E)**: This is inherent to adjacency lists. If you frequently need predecessors, maintain a separate reverse adjacency map or use the `reversed()` method to precompute it.

### Edge List

The edge list representation stores edges as explicit objects. It is useful when edges carry metadata (weights, labels, types) or when you need to iterate over all edges frequently, as in Bellman-Ford or network flow algorithms.

```dart
/// A directed edge with optional weight and metadata.
class Edge<T> {
  final T source;
  final T target;
  final double weight;
  final Map<String, Object>? metadata;

  const Edge(
    this.source,
    this.target, {
    this.weight = 1.0,
    this.metadata,
  });

  @override
  bool operator ==(Object other) =>
      other is Edge<T> && source == other.source && target == other.target;

  @override
  int get hashCode => Object.hash(source, target);

  @override
  String toString() => 'Edge($source -> $target, w=$weight)';
}

/// Graph backed by an explicit edge list.
///
/// Preferred when edges carry rich metadata or when algorithms
/// iterate over all edges (e.g., Bellman-Ford).
class EdgeListGraph<T> {
  final Set<T> _nodes = {};
  final List<Edge<T>> _edges = [];

  Set<T> get nodes => Set.unmodifiable(_nodes);
  List<Edge<T>> get edges => List.unmodifiable(_edges);

  void addNode(T node) => _nodes.add(node);

  void addEdge(Edge<T> edge) {
    _nodes.add(edge.source);
    _nodes.add(edge.target);
    _edges.add(edge);
  }

  /// Convert to adjacency list representation for traversal algorithms.
  DirectedGraph<T> toAdjacencyList() {
    final graph = DirectedGraph<T>();
    for (final node in _nodes) {
      graph.addNode(node);
    }
    for (final edge in _edges) {
      graph.addEdge(edge.source, edge.target);
    }
    return graph;
  }

  /// All outgoing edges from [node].
  Iterable<Edge<T>> outEdges(T node) =>
      _edges.where((e) => e.source == node);

  /// All incoming edges to [node].
  Iterable<Edge<T>> inEdges(T node) =>
      _edges.where((e) => e.target == node);
}
```

### Adjacency Matrix

The adjacency matrix uses a 2D array where `matrix[i][j]` is non-zero if there is an edge from node `i` to node `j`. It provides O(1) edge lookup but requires O(V^2) space, making it suitable only for dense graphs or small node counts.

In compiler engineering, adjacency matrices are sometimes used for:
- Small fixed-size state machines in lexer generators
- Register interference graphs where density is high
- Floyd-Warshall all-pairs shortest path computation

For most parser/compiler graphs, the adjacency list is preferred.

---

## Graph Traversal

### Depth-First Search (DFS)

DFS explores as far as possible along each branch before backtracking. It is the foundation for cycle detection, topological sorting, and SCC algorithms. The iterative version avoids stack overflow on deep graphs.

```dart
/// Graph traversal algorithms as extension methods on [DirectedGraph].
extension GraphTraversal<T> on DirectedGraph<T> {
  /// Recursive DFS with pre-order and post-order callbacks.
  ///
  /// [onDiscover] fires when a node is first visited (pre-order).
  /// [onFinish] fires when all descendants are processed (post-order).
  /// Returns the set of visited nodes.
  Set<T> dfs(
    T start, {
    void Function(T node)? onDiscover,
    void Function(T node)? onFinish,
  }) {
    final visited = <T>{};

    void visit(T node) {
      if (visited.contains(node)) return;
      visited.add(node);
      onDiscover?.call(node);

      for (final neighbor in successors(node)) {
        visit(neighbor);
      }

      onFinish?.call(node);
    }

    visit(start);
    return visited;
  }

  /// Iterative DFS using an explicit stack.
  ///
  /// Preferred for large graphs where recursive DFS may overflow
  /// the call stack. Visit order may differ from recursive DFS
  /// due to neighbor iteration order on the stack.
  List<T> dfsIterative(T start) {
    final visited = <T>{};
    final result = <T>[];
    final stack = [start];

    while (stack.isNotEmpty) {
      final node = stack.removeLast();
      if (visited.contains(node)) continue;

      visited.add(node);
      result.add(node);

      // Push neighbors in reverse order so that the first neighbor
      // is processed first (matching recursive DFS behavior).
      for (final neighbor in successors(node).toList().reversed) {
        if (!visited.contains(neighbor)) {
          stack.add(neighbor);
        }
      }
    }

    return result;
  }

  /// BFS from [start], returning nodes in level-order.
  ///
  /// Also computes the distance (number of edges) from [start]
  /// to each reachable node. Useful for shortest path in
  /// unweighted graphs and for layer assignment in layout.
  (List<T> order, Map<T, int> distances) bfs(T start) {
    final visited = <T>{start};
    final queue = Queue<T>()..add(start);
    final order = <T>[];
    final distances = <T, int>{start: 0};

    while (queue.isNotEmpty) {
      final node = queue.removeFirst();
      order.add(node);

      for (final neighbor in successors(node)) {
        if (!visited.contains(neighbor)) {
          visited.add(neighbor);
          distances[neighbor] = distances[node]! + 1;
          queue.add(neighbor);
        }
      }
    }

    return (order, distances);
  }

  /// Iterative Deepening DFS (IDDFS).
  ///
  /// Combines the space efficiency of DFS with the shortest-path
  /// guarantee of BFS. Useful when the target depth is unknown
  /// and the branching factor is large.
  T? iddfs(T start, bool Function(T) isGoal, {int maxDepth = 100}) {
    for (var depth = 0; depth <= maxDepth; depth++) {
      final result = _depthLimitedDfs(start, isGoal, depth);
      if (result != null) return result;
    }
    return null;
  }

  T? _depthLimitedDfs(T node, bool Function(T) isGoal, int limit) {
    if (isGoal(node)) return node;
    if (limit <= 0) return null;

    for (final neighbor in successors(node)) {
      final result = _depthLimitedDfs(neighbor, isGoal, limit - 1);
      if (result != null) return result;
    }
    return null;
  }
}
```

### Breadth-First Search (BFS)

BFS explores all neighbors at the current depth before moving deeper. It naturally produces a level-order traversal, making it ideal for:
- Shortest path in unweighted graphs
- Layer assignment in Sugiyama-style layout
- Finding the minimum number of compilation passes

The BFS implementation is included in the extension above. The returned `distances` map can be used directly for longest-path layer assignment by running BFS on the reversed graph.

### Iterative Deepening DFS

IDDFS repeatedly runs depth-limited DFS with increasing depth limits. It has the space complexity of DFS (O(bd) where b is branching factor and d is depth) but finds the shallowest goal like BFS. This is useful in compiler optimization when searching for the shortest rewrite sequence in a term rewriting system.

---

## Cycle Detection

Cycles in directed graphs indicate circular dependencies (in package managers), infinite loops (in control flow graphs), or invalid orderings (in task scheduling). Two primary approaches exist.

### DFS-Based Cycle Detection

The DFS approach uses a three-color marking scheme:
- **White (unvisited)**: Node has not been explored.
- **Gray (in progress)**: Node is on the current DFS path (its descendants are still being explored).
- **Black (finished)**: Node and all its descendants have been fully explored.

A back edge (an edge from a gray node to another gray node) indicates a cycle.

```dart
/// Cycle detection and topological sort algorithms.
extension CycleDetection<T> on DirectedGraph<T> {
  /// Detect whether the graph contains any cycle using DFS.
  ///
  /// Returns `null` if the graph is acyclic, or a [List<T>]
  /// containing the nodes forming one cycle (in order).
  List<T>? findCycle() {
    final white = Set<T>.of(nodes); // unvisited
    final gray = <T>{}; // in current DFS path
    final parent = <T, T>{};

    List<T>? cycle;

    bool visit(T node) {
      white.remove(node);
      gray.add(node);

      for (final neighbor in successors(node)) {
        if (gray.contains(neighbor)) {
          // Back edge found: reconstruct cycle.
          cycle = _reconstructCycle(parent, node, neighbor);
          return true;
        }
        if (white.contains(neighbor)) {
          parent[neighbor] = node;
          if (visit(neighbor)) return true;
        }
      }

      gray.remove(node);
      return false;
    }

    for (final node in nodes) {
      if (white.contains(node)) {
        if (visit(node)) return cycle;
      }
    }

    return null;
  }

  List<T> _reconstructCycle(Map<T, T> parent, T from, T to) {
    final path = <T>[to];
    var current = from;
    while (current != to) {
      path.add(current);
      current = parent[current] as T;
    }
    path.add(to);
    return path.reversed.toList();
  }

  /// Check if the graph is a DAG (directed acyclic graph).
  bool get isAcyclic => findCycle() == null;
}
```

### Kahn's Algorithm for Cycle Detection

Kahn's algorithm simultaneously detects cycles and produces a topological sort. It works by repeatedly removing nodes with zero in-degree. If the algorithm terminates before all nodes are removed, the remaining nodes form one or more cycles.

This approach is often preferred in build systems because it naturally produces the build order while also detecting circular dependencies.

---

## Topological Sorting

A topological sort of a DAG is a linear ordering of nodes such that for every directed edge (u, v), node u appears before node v. This is fundamental for:
- Compilation order (compile dependencies before dependents)
- Task scheduling (execute prerequisites before dependent tasks)
- Widget tree rendering order
- Layer assignment in graph layout

### DFS Post-Order Topological Sort

The DFS approach collects nodes in post-order (when they are finished), then reverses the result. This is typically faster in practice and uses less auxiliary space than Kahn's.

```dart
extension TopologicalSort<T> on DirectedGraph<T> {
  /// Topological sort using DFS post-order reversal.
  ///
  /// Throws [StateError] if the graph contains a cycle.
  /// The returned list has the property that for every edge (u, v),
  /// u appears before v in the list.
  List<T> topologicalSortDfs() {
    final cycle = findCycle();
    if (cycle != null) {
      throw StateError('Graph contains a cycle: ${cycle.join(' -> ')}');
    }

    final visited = <T>{};
    final postOrder = <T>[];

    void visit(T node) {
      if (visited.contains(node)) return;
      visited.add(node);

      for (final neighbor in successors(node)) {
        visit(neighbor);
      }

      postOrder.add(node);
    }

    for (final node in nodes) {
      visit(node);
    }

    return postOrder.reversed.toList();
  }

  /// Topological sort using Kahn's algorithm (BFS-based).
  ///
  /// Returns `null` if the graph contains a cycle (not all nodes
  /// could be processed). Otherwise returns the topological ordering.
  ///
  /// This variant is preferred when you also need to detect cycles
  /// or want a deterministic ordering (use a priority queue instead
  /// of a plain queue for lexicographic order).
  List<T>? topologicalSortKahn() {
    // Compute in-degrees.
    final inDegrees = <T, int>{};
    for (final node in nodes) {
      inDegrees.putIfAbsent(node, () => 0);
      for (final neighbor in successors(node)) {
        inDegrees[neighbor] = (inDegrees[neighbor] ?? 0) + 1;
      }
    }

    // Initialize queue with zero in-degree nodes.
    final queue = Queue<T>();
    for (final entry in inDegrees.entries) {
      if (entry.value == 0) queue.add(entry.key);
    }

    final result = <T>[];

    while (queue.isNotEmpty) {
      final node = queue.removeFirst();
      result.add(node);

      for (final neighbor in successors(node)) {
        inDegrees[neighbor] = inDegrees[neighbor]! - 1;
        if (inDegrees[neighbor] == 0) {
          queue.add(neighbor);
        }
      }
    }

    // If not all nodes were processed, a cycle exists.
    if (result.length != nodes.length) return null;

    return result;
  }
}
```

### Kahn's BFS Topological Sort

Kahn's algorithm provides several advantages over the DFS approach:

1. **Integrated cycle detection**: If the output has fewer nodes than the graph, a cycle exists. No separate cycle detection pass is needed.
2. **Level-aware ordering**: By tracking when the queue drains between levels, you get a natural layering that can seed the layout algorithm.
3. **Parallelism hints**: All nodes dequeued in the same "round" can be processed in parallel, which is valuable for parallel compilation.
4. **Deterministic output**: Replace the `Queue` with a `PriorityQueue` to get lexicographically smallest topological order, useful for reproducible builds.

---

## Shortest Path Algorithms

### Dijkstra's Algorithm

Dijkstra's algorithm finds the shortest path from a single source to all other nodes in a graph with non-negative edge weights. In compiler engineering, this is used for:
- Minimum-cost register allocation
- Optimal instruction selection on weighted DAGs
- Finding the cheapest transformation path in optimization passes

The algorithm uses a priority queue (min-heap) to always process the nearest unvisited node. Time complexity is O((V + E) log V) with a binary heap.

```dart
/// Shortest path algorithms for weighted directed graphs.
class WeightedDirectedGraph<T> extends DirectedGraph<T> {
  final Map<(T, T), double> _weights = {};

  /// Add a weighted directed edge.
  void addWeightedEdge(T source, T target, double weight) {
    addEdge(source, target);
    _weights[(source, target)] = weight;
  }

  /// Get the weight of an edge, defaulting to 1.0 if unweighted.
  double weight(T source, T target) => _weights[(source, target)] ?? 1.0;

  /// Dijkstra's shortest path from [source] to all reachable nodes.
  ///
  /// Returns a record of (distances, predecessors) where:
  /// - distances[node] is the shortest distance from source to node
  /// - predecessors[node] is the previous node on the shortest path
  ///
  /// Throws [ArgumentError] if any edge weight is negative.
  ({Map<T, double> distances, Map<T, T?> predecessors}) dijkstra(T source) {
    // Validate no negative weights.
    for (final w in _weights.values) {
      if (w < 0) {
        throw ArgumentError(
          'Dijkstra does not support negative weights. Use Bellman-Ford.',
        );
      }
    }

    final distances = <T, double>{};
    final predecessors = <T, T?>{};
    final visited = <T>{};

    // Priority queue: (distance, node). Dart lacks a built-in
    // priority queue, so we use SplayTreeSet with a custom comparator.
    // For production, consider using package:collection's PriorityQueue.
    for (final node in nodes) {
      distances[node] = double.infinity;
      predecessors[node] = null;
    }
    distances[source] = 0;

    // Simple priority queue using a sorted set of (distance, node) pairs.
    final pq = SplayTreeSet<(double, T)>(
      (a, b) {
        final cmp = a.$1.compareTo(b.$1);
        if (cmp != 0) return cmp;
        return a.$2.hashCode.compareTo(b.$2.hashCode);
      },
    );
    pq.add((0, source));

    while (pq.isNotEmpty) {
      final (dist, node) = pq.first;
      pq.remove(pq.first);

      if (visited.contains(node)) continue;
      visited.add(node);

      for (final neighbor in successors(node)) {
        final edgeWeight = weight(node, neighbor);
        final newDist = dist + edgeWeight;

        if (newDist < distances[neighbor]!) {
          pq.remove((distances[neighbor]!, neighbor));
          distances[neighbor] = newDist;
          predecessors[neighbor] = node;
          pq.add((newDist, neighbor));
        }
      }
    }

    return (distances: distances, predecessors: predecessors);
  }

  /// Reconstruct the shortest path from [source] to [target].
  List<T> shortestPath(T source, T target) {
    final (:distances, :predecessors) = dijkstra(source);

    if (distances[target] == double.infinity) {
      return []; // No path exists.
    }

    final path = <T>[];
    T? current = target;
    while (current != null) {
      path.add(current);
      current = predecessors[current];
    }

    return path.reversed.toList();
  }

  /// Bellman-Ford shortest path from [source].
  ///
  /// Handles negative edge weights. Detects negative cycles.
  /// Time complexity: O(V * E).
  ///
  /// Returns null if a negative cycle is reachable from [source].
  ({Map<T, double> distances, Map<T, T?> predecessors})? bellmanFord(
    T source,
  ) {
    final distances = <T, double>{};
    final predecessors = <T, T?>{};

    for (final node in nodes) {
      distances[node] = double.infinity;
      predecessors[node] = null;
    }
    distances[source] = 0;

    final nodeList = nodes.toList();
    final edgeList = <(T, T)>[];
    for (final node in nodeList) {
      for (final neighbor in successors(node)) {
        edgeList.add((node, neighbor));
      }
    }

    // Relax all edges V-1 times.
    for (var i = 0; i < nodeList.length - 1; i++) {
      var changed = false;
      for (final (u, v) in edgeList) {
        final w = weight(u, v);
        if (distances[u]! + w < distances[v]!) {
          distances[v] = distances[u]! + w;
          predecessors[v] = u;
          changed = true;
        }
      }
      // Early termination if no relaxation occurred.
      if (!changed) break;
    }

    // Check for negative cycles.
    for (final (u, v) in edgeList) {
      final w = weight(u, v);
      if (distances[u]! + w < distances[v]!) {
        return null; // Negative cycle detected.
      }
    }

    return (distances: distances, predecessors: predecessors);
  }
}
```

### Bellman-Ford Algorithm

Bellman-Ford relaxes all edges V-1 times, where V is the number of vertices. It handles negative edge weights and can detect negative cycles. While slower than Dijkstra (O(VE) vs O((V+E) log V)), it is essential when:
- Edge weights can be negative (e.g., representing cost savings in optimization)
- You need to detect negative cycles (infinite optimization loops)
- The graph is dense and the overhead of a priority queue is not worthwhile

The implementation above includes an early termination optimization: if no distance was updated in a full pass, the algorithm stops early.

---

## Connected Components

### Weakly Connected Components

A weakly connected component is a maximal set of nodes such that there is a path between every pair when edge direction is ignored. Computed by running DFS/BFS on the undirected version of the graph.

In compiler engineering, weakly connected components help identify independent subgraphs that can be processed in parallel (e.g., separate module dependency trees).

### Strongly Connected Components (Tarjan's)

A strongly connected component (SCC) is a maximal set of nodes such that there is a directed path from every node to every other node in the set. Tarjan's algorithm finds all SCCs in a single DFS pass with O(V + E) time complexity.

SCCs are critical for:
- Detecting groups of mutually recursive functions
- Identifying cycles in dependency graphs (each non-trivial SCC is a cycle)
- Collapsing SCCs into single nodes to create a DAG (the condensation graph)
- Dataflow analysis: computing fixed points for mutually dependent equations

```dart
/// Tarjan's SCC algorithm and related component analysis.
extension StronglyConnectedComponents<T> on DirectedGraph<T> {
  /// Find all strongly connected components using Tarjan's algorithm.
  ///
  /// Returns a list of SCCs, each represented as a set of nodes.
  /// SCCs are returned in reverse topological order of the
  /// condensation graph (i.e., sink SCCs first).
  List<Set<T>> tarjanSCC() {
    var index = 0;
    final indices = <T, int>{};
    final lowlinks = <T, int>{};
    final onStack = <T>{};
    final stack = <T>[];
    final sccs = <Set<T>>[];

    void strongConnect(T node) {
      indices[node] = index;
      lowlinks[node] = index;
      index++;
      stack.add(node);
      onStack.add(node);

      for (final neighbor in successors(node)) {
        if (!indices.containsKey(neighbor)) {
          // Neighbor has not been visited; recurse.
          strongConnect(neighbor);
          lowlinks[node] = lowlinks[node]! < lowlinks[neighbor]!
              ? lowlinks[node]!
              : lowlinks[neighbor]!;
        } else if (onStack.contains(neighbor)) {
          // Neighbor is on the stack, so it is in the current SCC.
          lowlinks[node] = lowlinks[node]! < indices[neighbor]!
              ? lowlinks[node]!
              : indices[neighbor]!;
        }
      }

      // If node is a root node, pop the SCC from the stack.
      if (lowlinks[node] == indices[node]) {
        final scc = <T>{};
        T w;
        do {
          w = stack.removeLast();
          onStack.remove(w);
          scc.add(w);
        } while (w != node);
        sccs.add(scc);
      }
    }

    for (final node in nodes) {
      if (!indices.containsKey(node)) {
        strongConnect(node);
      }
    }

    return sccs;
  }

  /// Build the condensation graph: collapse each SCC into a single node.
  ///
  /// Returns a DAG where each node is a [Set<T>] representing an SCC.
  /// Useful for processing mutually recursive groups in order.
  DirectedGraph<Set<T>> condensation() {
    final sccs = tarjanSCC();
    final nodeToScc = <T, Set<T>>{};
    for (final scc in sccs) {
      for (final node in scc) {
        nodeToScc[node] = scc;
      }
    }

    final dag = DirectedGraph<Set<T>>();
    for (final scc in sccs) {
      dag.addNode(scc);
    }

    for (final scc in sccs) {
      for (final node in scc) {
        for (final neighbor in successors(node)) {
          final neighborScc = nodeToScc[neighbor]!;
          if (!identical(scc, neighborScc)) {
            dag.addEdge(scc, neighborScc);
          }
        }
      }
    }

    return dag;
  }

  /// Find all weakly connected components.
  ///
  /// Treats the graph as undirected for connectivity purposes.
  List<Set<T>> weaklyConnectedComponents() {
    final visited = <T>{};
    final components = <Set<T>>[];

    for (final start in nodes) {
      if (visited.contains(start)) continue;

      final component = <T>{};
      final queue = Queue<T>()..add(start);

      while (queue.isNotEmpty) {
        final node = queue.removeFirst();
        if (visited.contains(node)) continue;
        visited.add(node);
        component.add(node);

        // Follow edges in both directions.
        for (final neighbor in successors(node)) {
          if (!visited.contains(neighbor)) queue.add(neighbor);
        }
        for (final predecessor in predecessors(node)) {
          if (!visited.contains(predecessor)) queue.add(predecessor);
        }
      }

      components.add(component);
    }

    return components;
  }
}
```

Tarjan's algorithm maintains a `lowlink` value for each node, which represents the smallest index reachable from that node. When a node's `lowlink` equals its own index, it is the root of an SCC, and all nodes above it on the stack belong to that SCC.

---

## Dagre-Style Layered Graph Layout

The dagre layout algorithm implements the Sugiyama framework for drawing layered (hierarchical) directed graphs. This is the same algorithm used by dagre.js, Graphviz's `dot` engine, and tools for visualizing compiler IR, dependency graphs, and widget trees.

### Overview of the Sugiyama Framework

The Sugiyama framework consists of four phases:

1. **Cycle removal**: Reverse a minimal set of edges to make the graph acyclic.
2. **Layer assignment**: Assign each node to a horizontal layer (rank).
3. **Crossing reduction**: Order nodes within each layer to minimize edge crossings.
4. **Coordinate assignment**: Assign x and y coordinates to each node.

Each phase runs in sequence, and the output of one phase feeds into the next. The overall time complexity is typically O(V * E) for practical graphs, though worst-case crossing reduction is NP-hard.

### Layer Assignment

Layer assignment determines the vertical position (rank) of each node. The two primary methods are longest path and network simplex.

**Longest Path Algorithm**: Simple and fast. Assigns each node to a layer equal to the length of the longest path from any source node. This minimizes the total graph height but may produce wide layers.

**Network Simplex**: More sophisticated. Formulates layer assignment as a minimum-cost flow problem and uses the simplex method on the spanning tree. It produces tighter layouts by minimizing the total edge length (sum of `|layer(target) - layer(source)|` over all edges).

```dart
/// Dagre-style layered graph layout engine.
///
/// Implements the Sugiyama framework: cycle removal, layer assignment,
/// crossing reduction, and coordinate assignment.
class DagreLayout<T> {
  final DirectedGraph<T> graph;
  final double nodeWidth;
  final double nodeHeight;
  final double horizontalSpacing;
  final double verticalSpacing;

  DagreLayout(
    this.graph, {
    this.nodeWidth = 120,
    this.nodeHeight = 40,
    this.horizontalSpacing = 50,
    this.verticalSpacing = 80,
  });

  /// Computed layout positions for each node.
  late final Map<T, ({double x, double y})> positions;

  /// Layer assignment for each node.
  late final Map<T, int> layers;

  /// Ordered nodes within each layer (after crossing reduction).
  late final List<List<T>> layerOrder;

  /// Execute the full layout pipeline.
  void layout() {
    // Phase 1: Ensure the graph is a DAG (cycle removal).
    final dag = _removeCycles();

    // Phase 2: Assign layers using longest path.
    layers = _assignLayersLongestPath(dag);

    // Phase 3: Order nodes within layers to minimize crossings.
    layerOrder = _reduceCrossings(dag, layers);

    // Phase 4: Assign coordinates.
    positions = _assignCoordinates(layerOrder);
  }

  /// Phase 1: Remove cycles by reversing back edges found during DFS.
  DirectedGraph<T> _removeCycles() {
    final dag = graph.copy();
    final visited = <T>{};
    final inPath = <T>{};
    final backEdges = <(T, T)>[];

    void visit(T node) {
      visited.add(node);
      inPath.add(node);

      for (final neighbor in dag.successors(node)) {
        if (inPath.contains(neighbor)) {
          backEdges.add((node, neighbor));
        } else if (!visited.contains(neighbor)) {
          visit(neighbor);
        }
      }

      inPath.remove(node);
    }

    for (final node in dag.nodes) {
      if (!visited.contains(node)) visit(node);
    }

    // Reverse back edges to break cycles.
    for (final (source, target) in backEdges) {
      dag.removeEdge(source, target);
      dag.addEdge(target, source);
    }

    return dag;
  }

  /// Phase 2: Longest-path layer assignment.
  ///
  /// Source nodes (in-degree 0) are assigned to layer 0.
  /// Each other node is assigned to max(layer(predecessor)) + 1.
  /// This minimizes the height of the layout.
  Map<T, int> _assignLayersLongestPath(DirectedGraph<T> dag) {
    final layerMap = <T, int>{};
    final topoOrder = dag.topologicalSortDfs();

    for (final node in topoOrder) {
      var maxPredLayer = -1;
      for (final pred in dag.predecessors(node)) {
        final predLayer = layerMap[pred] ?? 0;
        if (predLayer > maxPredLayer) maxPredLayer = predLayer;
      }
      layerMap[node] = maxPredLayer + 1;
    }

    return layerMap;
  }

  /// Phase 3: Crossing reduction using the barycenter heuristic.
  ///
  /// Iteratively reorders nodes in each layer to minimize edge
  /// crossings with adjacent layers. Uses a two-pass sweep
  /// (top-down then bottom-up) repeated until convergence.
  List<List<T>> _reduceCrossings(
    DirectedGraph<T> dag,
    Map<T, int> layerMap,
  ) {
    // Build initial layer ordering.
    final maxLayer = layerMap.values.fold(0, (a, b) => a > b ? a : b);
    final order = List.generate(maxLayer + 1, (_) => <T>[]);
    for (final node in dag.topologicalSortDfs()) {
      order[layerMap[node]!].add(node);
    }

    // Barycenter sweep: repeat until no improvement.
    for (var iteration = 0; iteration < 24; iteration++) {
      var improved = false;

      // Top-down sweep.
      for (var layer = 1; layer <= maxLayer; layer++) {
        improved |= _barycenterSort(order, layer, dag, direction: -1);
      }

      // Bottom-up sweep.
      for (var layer = maxLayer - 1; layer >= 0; layer--) {
        improved |= _barycenterSort(order, layer, dag, direction: 1);
      }

      if (!improved) break;
    }

    return order;
  }

  /// Sort a single layer by barycenter of connected nodes in the
  /// adjacent layer.
  ///
  /// [direction] is -1 for looking at the layer above (predecessors)
  /// or +1 for looking at the layer below (successors).
  bool _barycenterSort(
    List<List<T>> order,
    int layer,
    DirectedGraph<T> dag, {
    required int direction,
  }) {
    final adjacentLayer = layer + direction;
    if (adjacentLayer < 0 || adjacentLayer >= order.length) return false;

    // Build position index for the adjacent layer.
    final posIndex = <T, int>{};
    for (var i = 0; i < order[adjacentLayer].length; i++) {
      posIndex[order[adjacentLayer][i]] = i;
    }

    // Compute barycenter for each node in the current layer.
    final barycenters = <T, double>{};
    for (final node in order[layer]) {
      final connected = direction == -1
          ? dag.predecessors(node)
          : dag.successors(node);

      final positions = connected
          .where(posIndex.containsKey)
          .map((n) => posIndex[n]!.toDouble())
          .toList();

      if (positions.isNotEmpty) {
        barycenters[node] =
            positions.reduce((a, b) => a + b) / positions.length;
      } else {
        // Keep current position for unconnected nodes.
        barycenters[node] = order[layer].indexOf(node).toDouble();
      }
    }

    final oldOrder = List<T>.from(order[layer]);
    order[layer].sort((a, b) =>
        (barycenters[a] ?? 0).compareTo(barycenters[b] ?? 0));

    // Check if order changed.
    for (var i = 0; i < oldOrder.length; i++) {
      if (oldOrder[i] != order[layer][i]) return true;
    }
    return false;
  }

  /// Phase 4: Assign (x, y) coordinates based on layer and position.
  ///
  /// Layers determine the y coordinate; position within a layer
  /// determines the x coordinate. Layers are centered horizontally.
  Map<T, ({double x, double y})> _assignCoordinates(List<List<T>> order) {
    final coords = <T, ({double x, double y})>{};

    // Find the widest layer for centering.
    final maxWidth = order.fold(0, (m, layer) => layer.length > m ? layer.length : m);
    final totalMaxWidth = maxWidth * (nodeWidth + horizontalSpacing) - horizontalSpacing;

    for (var layerIdx = 0; layerIdx < order.length; layerIdx++) {
      final layer = order[layerIdx];
      final layerWidth = layer.length * (nodeWidth + horizontalSpacing) - horizontalSpacing;
      final xOffset = (totalMaxWidth - layerWidth) / 2;

      for (var pos = 0; pos < layer.length; pos++) {
        final node = layer[pos];
        coords[node] = (
          x: xOffset + pos * (nodeWidth + horizontalSpacing) + nodeWidth / 2,
          y: layerIdx * (nodeHeight + verticalSpacing) + nodeHeight / 2,
        );
      }
    }

    return coords;
  }

  /// Count the number of edge crossings in the current layout.
  ///
  /// Two edges (u1, v1) and (u2, v2) cross if u1 and u2 are in the
  /// same layer, v1 and v2 are in the same layer, and their
  /// relative orders are reversed.
  int countCrossings() {
    var crossings = 0;

    for (var layer = 0; layer < layerOrder.length - 1; layer++) {
      final topLayer = layerOrder[layer];
      final bottomLayer = layerOrder[layer + 1];

      // Build position indices.
      final topPos = <T, int>{};
      for (var i = 0; i < topLayer.length; i++) {
        topPos[topLayer[i]] = i;
      }
      final bottomPos = <T, int>{};
      for (var i = 0; i < bottomLayer.length; i++) {
        bottomPos[bottomLayer[i]] = i;
      }

      // Collect all edges between these two layers.
      final edges = <(int, int)>[];
      for (final u in topLayer) {
        for (final v in graph.successors(u)) {
          if (bottomPos.containsKey(v)) {
            edges.add((topPos[u]!, bottomPos[v]!));
          }
        }
      }

      // Count inversions (crossings).
      for (var i = 0; i < edges.length; i++) {
        for (var j = i + 1; j < edges.length; j++) {
          final (u1, v1) = edges[i];
          final (u2, v2) = edges[j];
          if ((u1 - u2) * (v1 - v2) < 0) crossings++;
        }
      }
    }

    return crossings;
  }
}
```

### Layer Assignment

The longest-path algorithm implemented above is the simplest layer assignment strategy. It works by:

1. Finding a topological order of the DAG.
2. For each node in topological order, assigning it to one layer past the maximum layer of its predecessors.

The **network simplex** method is more complex but produces tighter layouts. It models the problem as a minimum-cost flow: minimize the sum of `(layer(v) - layer(u) - minLength(u,v))` over all edges `(u,v)`. The algorithm works on a feasible spanning tree and pivots edges in and out of the tree to reduce cost, similar to the simplex method in linear programming.

Network simplex layer assignment is implemented in dagre.js and Graphviz's `dot` layout. For most practical graphs with fewer than 10,000 nodes, the longest-path algorithm produces acceptable results and is much simpler to implement and debug.

### Crossing Reduction

Crossing reduction is the most computationally expensive phase. The general problem (minimizing crossings in a two-layer graph) is NP-complete, so heuristics are used.

**Barycenter Heuristic**: For each node in a layer, compute the average position of its neighbors in the adjacent layer. Sort nodes by this average. This is the method implemented above. It is simple and effective for most graphs.

**Median Heuristic**: Similar to barycenter, but uses the median position of neighbors instead of the mean. The median heuristic has a theoretical guarantee: it produces at most 3 times the optimal number of crossings. In practice, it often produces fewer crossings than barycenter on graphs with high-degree nodes, because the median is less sensitive to outlier positions.

To implement the median heuristic, replace the barycenter calculation with:

```
// Median calculation for a single node.
final positions = connectedPositions.toList()..sort();
if (positions.isEmpty) {
  median = currentPosition;
} else if (positions.length.isOdd) {
  median = positions[positions.length ~/ 2].toDouble();
} else {
  // Average of two middle values for even count.
  final mid = positions.length ~/ 2;
  median = (positions[mid - 1] + positions[mid]) / 2.0;
}
```

**Iterative sweeping**: Both heuristics are applied in alternating top-down and bottom-up sweeps until no improvement is found. The implementation above limits sweeps to 24 iterations, which is sufficient for convergence on most practical graphs.

### Coordinate Assignment

Coordinate assignment translates the abstract layer and position into pixel coordinates. The simple approach (implemented above) assigns evenly spaced positions within each layer and centers layers horizontally.

More sophisticated coordinate assignment algorithms include:

- **Brandes-Kopf**: Minimizes the total edge length while maintaining the ordering from crossing reduction. It processes four passes (upper-left, upper-right, lower-left, lower-right) and takes the median result.
- **Priority layout**: Gives higher priority to long edges (spanning multiple layers) to keep them straight, which improves readability.
- **Compact coordinate assignment**: Treats coordinate assignment as a quadratic programming problem to minimize the weighted sum of edge lengths.

For the common case of compiler IR visualization or widget tree layout, the simple even-spacing approach works well. When graphs have many long edges, Brandes-Kopf produces noticeably better results.

---

## Practical Application: Widget Tree to Graph to Layout

A common task in Flutter/Dart tooling is converting a widget tree into a visual graph layout. This pipeline demonstrates how all the algorithms in this document work together.

```dart
import 'dart:collection';

/// Represents a widget in the widget tree.
class WidgetNode {
  final String id;
  final String type;
  final Map<String, String> properties;
  final List<WidgetNode> children;

  const WidgetNode({
    required this.id,
    required this.type,
    this.properties = const {},
    this.children = const [],
  });

  @override
  String toString() => '$type($id)';

  @override
  bool operator ==(Object other) => other is WidgetNode && id == other.id;

  @override
  int get hashCode => id.hashCode;
}

/// Positioned node for rendering.
class LayoutNode {
  final WidgetNode widget;
  final double x;
  final double y;
  final double width;
  final double height;
  final int layer;

  const LayoutNode({
    required this.widget,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.layer,
  });

  @override
  String toString() => '${widget.type}@(${x.toInt()}, ${y.toInt()})';
}

/// Positioned edge for rendering.
class LayoutEdge {
  final LayoutNode from;
  final LayoutNode to;
  final List<({double x, double y})> waypoints;

  const LayoutEdge({
    required this.from,
    required this.to,
    this.waypoints = const [],
  });
}

/// Complete pipeline: widget tree -> graph -> layout.
class WidgetTreeLayoutEngine {
  final double nodeWidth;
  final double nodeHeight;
  final double hSpacing;
  final double vSpacing;

  WidgetTreeLayoutEngine({
    this.nodeWidth = 140,
    this.nodeHeight = 50,
    this.hSpacing = 40,
    this.vSpacing = 70,
  });

  /// Convert a widget tree into a positioned layout.
  ({List<LayoutNode> nodes, List<LayoutEdge> edges}) layoutTree(
    WidgetNode root,
  ) {
    // Step 1: Build directed graph from widget tree.
    final graph = DirectedGraph<WidgetNode>();
    _buildGraph(root, graph);

    // Step 2: Run dagre-style layout.
    final layout = DagreLayout<WidgetNode>(
      graph,
      nodeWidth: nodeWidth,
      nodeHeight: nodeHeight,
      horizontalSpacing: hSpacing,
      verticalSpacing: vSpacing,
    );
    layout.layout();

    // Step 3: Convert positions to LayoutNode objects.
    final layoutNodes = <WidgetNode, LayoutNode>{};
    for (final entry in layout.positions.entries) {
      final widget = entry.key;
      final pos = entry.value;
      final node = LayoutNode(
        widget: widget,
        x: pos.x - nodeWidth / 2,
        y: pos.y - nodeHeight / 2,
        width: nodeWidth,
        height: nodeHeight,
        layer: layout.layers[widget]!,
      );
      layoutNodes[widget] = node;
    }

    // Step 4: Build layout edges with connection points.
    final layoutEdges = <LayoutEdge>[];
    for (final widget in graph.nodes) {
      final fromNode = layoutNodes[widget]!;
      for (final child in graph.successors(widget)) {
        final toNode = layoutNodes[child]!;
        layoutEdges.add(LayoutEdge(
          from: fromNode,
          to: toNode,
          waypoints: [
            (x: fromNode.x + nodeWidth / 2, y: fromNode.y + nodeHeight),
            (x: toNode.x + nodeWidth / 2, y: toNode.y),
          ],
        ));
      }
    }

    return (nodes: layoutNodes.values.toList(), edges: layoutEdges);
  }

  /// Recursively build a graph from the widget tree.
  void _buildGraph(WidgetNode node, DirectedGraph<WidgetNode> graph) {
    graph.addNode(node);
    for (final child in node.children) {
      graph.addEdge(node, child);
      _buildGraph(child, graph);
    }
  }
}

// Example usage:
void main() {
  final tree = WidgetNode(
    id: 'scaffold',
    type: 'Scaffold',
    children: [
      WidgetNode(
        id: 'appbar',
        type: 'AppBar',
        children: [
          WidgetNode(id: 'title', type: 'Text', properties: {'text': 'Home'}),
        ],
      ),
      WidgetNode(
        id: 'body',
        type: 'Column',
        children: [
          WidgetNode(id: 'header', type: 'Text', properties: {'text': 'Hello'}),
          WidgetNode(
            id: 'list',
            type: 'ListView',
            children: [
              WidgetNode(id: 'item1', type: 'ListTile'),
              WidgetNode(id: 'item2', type: 'ListTile'),
              WidgetNode(id: 'item3', type: 'ListTile'),
            ],
          ),
          WidgetNode(id: 'footer', type: 'Text', properties: {'text': 'Footer'}),
        ],
      ),
    ],
  );

  final engine = WidgetTreeLayoutEngine();
  final (:nodes, :edges) = engine.layoutTree(tree);

  print('Layout Results:');
  print('===============');
  for (final node in nodes) {
    print('  $node (layer ${node.layer})');
  }
  print('\nEdges:');
  for (final edge in edges) {
    print('  ${edge.from.widget.type} -> ${edge.to.widget.type}');
  }
  print('\nCrossings: ${DagreLayout(DirectedGraph<WidgetNode>()).countCrossings}');
}
```

The pipeline follows these steps:

1. **Widget tree to graph**: Recursively walk the widget tree and add parent-to-child edges. Since widget trees are inherently acyclic (a child cannot be its own ancestor), no cycle removal is needed.
2. **Layer assignment**: The longest-path algorithm assigns each widget to a layer corresponding to its depth in the tree.
3. **Crossing reduction**: The barycenter heuristic orders sibling widgets to minimize crossing of parent-child edges.
4. **Coordinate assignment**: Each widget gets a pixel position for rendering.

This approach generalizes beyond trees. If your widget graph has shared children (e.g., a shared state widget referenced by multiple parents), the graph is a DAG rather than a tree, and the full dagre pipeline handles it correctly.

---

## Best Practices

### Graph Data Structure Selection

- **Use adjacency lists for sparse graphs** (most compiler/parser graphs). The O(V + E) space and O(degree) neighbor iteration are optimal.
- **Use edge lists when edges carry rich metadata** (weights, labels, source location information). Convert to adjacency list before running traversal algorithms.
- **Avoid adjacency matrices** unless the graph is dense or you need O(1) edge lookup. The O(V^2) space is wasteful for typical compiler graphs.
- **Make graph classes generic** over the node type `T`. This allows the same algorithms to work with string identifiers, integer IDs, or rich node objects.

### Algorithm Selection

- **For cycle detection in build systems**: Use Kahn's algorithm. It simultaneously detects cycles and produces the build order, avoiding a redundant second pass.
- **For topological sort in compilers**: Use DFS post-order. It is faster in practice and handles large graphs without the overhead of maintaining in-degree counts.
- **For shortest path with non-negative weights**: Use Dijkstra's. Never use Bellman-Ford unless negative weights are possible.
- **For SCC detection**: Use Tarjan's algorithm. It is a single-pass DFS, simpler to implement correctly than Kosaraju's two-pass approach.
- **For layout**: Start with longest-path layer assignment and barycenter crossing reduction. Only switch to network simplex or median heuristic if the layout quality is insufficient.

### Performance Optimization

- **Pre-compute reverse adjacency maps** if you frequently need predecessors. The `predecessors()` method on a plain adjacency list is O(V + E).
- **Use iterative DFS for deep graphs** to avoid stack overflow. Dart's default stack size can handle roughly 10,000-15,000 recursive calls.
- **Early termination in Bellman-Ford**: If no relaxation occurs in a full pass, stop immediately. This is already implemented above.
- **Limit crossing reduction iterations**: 20-30 iterations is sufficient for convergence on most practical graphs. Diminishing returns set in quickly.
- **Cache computed properties** (topological order, SCCs, layers) and invalidate when the graph is modified.

### Code Organization

- **Separate graph data structure from algorithms** using extension methods. This keeps the core `DirectedGraph` class focused on representation while algorithms are composable.
- **Use sealed classes for algorithm results** that can represent success or failure (e.g., topological sort succeeding or finding a cycle).
- **Provide both mutable and immutable graph interfaces**. Use immutable graphs for thread safety in parallel compilation.
- **Write graph equality based on node and edge sets**, not reference equality. Two graphs with the same nodes and edges should be equal.

### Testing Graph Algorithms

- **Test with known small graphs** where you can manually verify the correct output (e.g., a diamond graph, a chain, a single node, an empty graph).
- **Test edge cases**: empty graph, single node, self-loops, disconnected components, complete graph.
- **Property-based testing**: For topological sort, verify that for every edge (u, v), u appears before v in the output. For SCCs, verify that every pair of nodes in an SCC is mutually reachable.
- **Test performance with generated graphs**: Use random DAG generators to verify that algorithms scale as expected.

---

## Anti-Patterns

### Modifying a Graph During Traversal

Never add or remove nodes/edges while iterating over the graph. This causes `ConcurrentModificationError` in Dart or, worse, silently incorrect results.

```dart
// WRONG: Modifying during iteration.
for (final node in graph.nodes) {
  if (someCondition(node)) {
    graph.removeNode(node); // ConcurrentModificationError!
  }
}

// CORRECT: Collect first, then modify.
final toRemove = graph.nodes.where(someCondition).toList();
for (final node in toRemove) {
  graph.removeNode(node);
}
```

### Using Adjacency Matrix for Sparse Graphs

A compiler dependency graph with 10,000 modules and an average of 5 dependencies each has 50,000 edges. An adjacency matrix would use 10,000 x 10,000 = 100 million entries (most of which are zero). An adjacency list uses only 10,000 + 50,000 entries -- a 2000x improvement.

### Ignoring Self-Loops in Cycle Detection

Self-loops (edges from a node to itself) are cycles that some implementations miss. Always check for them explicitly or ensure your DFS properly handles the case where a successor is the current node.

### Running Dijkstra with Negative Weights

Dijkstra's algorithm does not work with negative edge weights. It may produce incorrect shortest paths or infinite loops. Always validate edge weights before running Dijkstra, or use Bellman-Ford for graphs that may have negative weights.

### Assuming Topological Sort is Unique

A DAG may have many valid topological orderings. Do not write code that depends on a specific ordering unless you explicitly enforce one (e.g., by using a priority queue in Kahn's algorithm for lexicographic order).

### Not Handling Disconnected Graphs

Many traversal algorithms start from a single source node and only visit the reachable component. For algorithms that must process the entire graph (topological sort, SCC), always iterate over all nodes and start a new traversal for each unvisited node.

```dart
// WRONG: Only processes one component.
final order = graph.dfs(someStartNode);

// CORRECT: Process all components.
final visited = <T>{};
for (final node in graph.nodes) {
  if (!visited.contains(node)) {
    visited.addAll(graph.dfs(node));
  }
}
```

### Quadratic Crossing Counting

The naive crossing counting algorithm (comparing all pairs of edges) is O(E^2). For large graphs, use the bilayer cross counting algorithm based on merge sort (O(E log V)) or the accumulator tree method. The naive approach is acceptable for graphs with fewer than a few hundred edges but becomes a bottleneck for larger graphs.

### Mutable Node Identity

If your node type `T` is a mutable class and its `hashCode` or `==` changes after insertion into the graph's `Map`/`Set`, the graph will silently corrupt. Always use immutable node identifiers or ensure that identity-relevant fields are final.

```dart
// WRONG: Mutable fields used in equality.
class MutableNode {
  String name; // Mutable!
  @override
  bool operator ==(Object other) => other is MutableNode && name == other.name;
  @override
  int get hashCode => name.hashCode;
}

// CORRECT: Immutable identity.
class ImmutableNode {
  final String id; // Final!
  String label; // Mutable display-only field, not used in equality.
  ImmutableNode(this.id, this.label);
  @override
  bool operator ==(Object other) => other is ImmutableNode && id == other.id;
  @override
  int get hashCode => id.hashCode;
}
```

### Forgetting to Insert Virtual Nodes for Long Edges

In dagre-style layout, edges that span multiple layers should have virtual (dummy) nodes inserted at each intermediate layer. Without these, crossing reduction cannot properly handle long edges, and edge routing will produce visually confusing overlapping lines.

```dart
// When edge (u, v) spans layers 0 to 3, insert virtual nodes:
// u (layer 0) -> v1 (layer 1) -> v2 (layer 2) -> v (layer 3)
// Each virtual node participates in crossing reduction for its layer.
```

---

## Sources & References

1. **Sugiyama, K., Tagawa, S., and Toda, M. (1981).** "Methods for Visual Understanding of Hierarchical System Structures." IEEE Transactions on Systems, Man, and Cybernetics, 11(2), 109-125. The foundational paper for layered graph drawing.
   - https://ieeexplore.ieee.org/document/4308636

2. **Gansner, E. R., Koutsofios, E., North, S. C., and Vo, K.-P. (1993).** "A Technique for Drawing Directed Graphs." IEEE Transactions on Software Engineering, 19(3), 214-230. Describes the algorithms used in Graphviz's `dot` layout engine, including network simplex layer assignment.
   - https://ieeexplore.ieee.org/document/221135

3. **dagre - Directed graph layout for JavaScript.** The dagre.js library implements the Sugiyama framework in JavaScript and is the basis for many graph visualization tools. Its source code is a practical reference for the algorithms described here.
   - https://github.com/dagrejs/dagre

4. **Dart `graphs` package on pub.dev.** Provides basic graph data structures and algorithms (topological sort, shortest path, SCCs) for Dart. Useful as a reference implementation or as a dependency for production code.
   - https://pub.dev/packages/graphs

5. **Tarjan, R. E. (1972).** "Depth-First Search and Linear Graph Algorithms." SIAM Journal on Computing, 1(2), 146-160. The original paper describing Tarjan's SCC algorithm and its linear time complexity proof.
   - https://epubs.siam.org/doi/10.1137/0201010

6. **Brandes, U. and Kopf, B. (2002).** "Fast and Simple Horizontal Coordinate Assignment." Proceedings of Graph Drawing (GD 2001), LNCS 2265, 31-44. Describes the Brandes-Kopf algorithm for coordinate assignment in layered graph drawing.
   - https://link.springer.com/chapter/10.1007/3-540-45848-4_3

7. **Introduction to Algorithms (CLRS), Cormen, Leiserson, Rivest, and Stein.** Chapters 20-26 cover graph algorithms including BFS, DFS, topological sort, SCCs, shortest paths, and network flow. The standard reference for algorithm correctness proofs and complexity analysis.
   - https://mitpress.mit.edu/books/introduction-algorithms-fourth-edition

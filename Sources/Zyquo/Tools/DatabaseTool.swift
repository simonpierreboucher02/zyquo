import Foundation
import GRDB
import Logging

// MARK: - DatabaseTool

/// Execute SQL queries against SQLite databases.
///
/// Risk level is determined per-query:
/// - SELECT/PRAGMA/EXPLAIN → SAFE
/// - INSERT/UPDATE/DELETE → DANGEROUS
/// - CREATE/DROP/ALTER → CRITICAL
///
/// The database path must be inside the workspace boundary.
///
/// Reference: CLAUDE.md Appendix A.11
public struct DatabaseTool: Tool, Sendable {
    public let name = "db.query"
    public let summary = "Execute SQL queries against a SQLite database"
    public let documentation = """
        Runs a SQL query on a local SQLite database file.
        SELECT queries are SAFE, INSERT/UPDATE/DELETE are DANGEROUS,
        CREATE/DROP/ALTER are CRITICAL.
        Database file must be inside the workspace.
        """
    public let defaultRisk: RiskLevel = .moderate
    public let isMutating = true

    public var inputSchema: ToolInputSchema {
        ToolInputSchema(
            properties: [
                "path": PropertySchema(
                    type: "string",
                    description: "Path to the SQLite database file (relative to workspace or absolute)"
                ),
                "query": PropertySchema(
                    type: "string",
                    description: "SQL query to execute"
                ),
            ],
            required: ["path", "query"]
        )
    }

    public init() {}

    // MARK: - Risk Classification

    /// Classify the risk of a SQL query based on the SQL verb.
    public static func classifyQueryRisk(_ query: String) -> RiskLevel {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()

        // Check for DDL statements (CRITICAL)
        let criticalPrefixes = ["CREATE ", "DROP ", "ALTER ", "TRUNCATE ", "RENAME "]
        for prefix in criticalPrefixes {
            if trimmed.hasPrefix(prefix) {
                return .critical
            }
        }

        // Check for DML mutation statements (DANGEROUS)
        let dangerousPrefixes = ["INSERT ", "UPDATE ", "DELETE ", "REPLACE ", "MERGE "]
        for prefix in dangerousPrefixes {
            if trimmed.hasPrefix(prefix) {
                return .dangerous
            }
        }

        // Read-only statements (SAFE)
        let safePrefixes = ["SELECT ", "PRAGMA ", "EXPLAIN ", "WITH "]
        for prefix in safePrefixes {
            if trimmed.hasPrefix(prefix) {
                return .safe
            }
        }

        // Unknown SQL → DANGEROUS by default
        return .dangerous
    }

    // MARK: - Execution

    public func execute(
        input: [String: JSONValue],
        context: ToolContext
    ) async throws -> ToolResult {
        let startTime = ContinuousClock.now

        // Parse path
        guard let pathStr = input["path"]?.stringValue, !pathStr.isEmpty else {
            throw ZyquoError.tool(ToolError(
                code: "tool.invalid_input",
                description: "Missing required 'path' parameter for db.query",
                remediation: "Provide a path to a SQLite database file"
            ))
        }

        // Parse query
        guard let query = input["query"]?.stringValue, !query.isEmpty else {
            throw ZyquoError.tool(ToolError(
                code: "tool.invalid_input",
                description: "Missing required 'query' parameter for db.query",
                remediation: "Provide a SQL query string"
            ))
        }

        // Resolve path
        let resolvedPath: String
        if pathStr.hasPrefix("/") {
            resolvedPath = pathStr
        } else {
            resolvedPath = context.workspaceRoot.appendingPathComponent(pathStr).path
        }

        // Workspace boundary check
        let guard_ = BoundaryGuard(workspaceRoot: context.workspaceRoot)
        let boundaryResult = guard_.validate(resolvedPath)
        switch boundaryResult {
        case .violation(let p, _):
            throw ZyquoError.workspace(.boundaryViolation(path: p))
        case .sensitive(let p, let reason):
            throw ZyquoError.workspace(WorkspaceError(
                code: "workspace.sensitive",
                description: "Sensitive path: \(p)",
                remediation: reason
            ))
        case .allowed:
            break
        }

        // Check file exists
        guard FileManager.default.fileExists(atPath: resolvedPath) else {
            throw ZyquoError.tool(ToolError(
                code: "tool.file_not_found",
                description: "Database file not found: \(resolvedPath)",
                remediation: "Check the path and ensure the SQLite file exists"
            ))
        }

        let risk = DatabaseTool.classifyQueryRisk(query)
        context.logger.info("db.query: \(risk.displayName) query on \(resolvedPath)")

        // Execute the query
        do {
            let dbQueue = try DatabaseQueue(path: resolvedPath)
            let elapsed: Int

            if risk == .safe {
                // Read-only query
                let rows = try await dbQueue.read { db -> [[String: JSONValue]] in
                    let rows = try Row.fetchAll(db, sql: query)
                    return rows.map { row in
                        var dict: [String: JSONValue] = [:]
                        for column in row.columnNames {
                            let value = row[column] as DatabaseValue
                            dict[column] = databaseValueToJSON(value)
                        }
                        return dict
                    }
                }

                elapsed = elapsedMs(since: startTime)
                let rowCount = rows.count
                let payload: JSONValue = .array(rows.map { .object($0) })
                let summaryText = "Query returned \(rowCount) row(s) from \(resolvedPath) (\(elapsed)ms)"

                return ToolResult(
                    summary: summaryText,
                    payload: payload,
                    durationMs: elapsed,
                    tokenHint: rowCount * 50 // rough estimate
                )
            } else {
                // Mutation query
                let changes = try await dbQueue.write { db -> Int in
                    try db.execute(sql: query)
                    return db.changesCount
                }

                elapsed = elapsedMs(since: startTime)
                let summaryText = "Query affected \(changes) row(s) in \(resolvedPath) (\(elapsed)ms)"

                return ToolResult(
                    summary: summaryText,
                    payload: .object([
                        "changes": .number(Double(changes)),
                        "query": .string(query),
                        "path": .string(resolvedPath),
                    ]),
                    durationMs: elapsed
                )
            }
        } catch {
            let elapsed = elapsedMs(since: startTime)
            throw ZyquoError.tool(ToolError(
                code: "tool.db_error",
                description: "Database error: \(error.localizedDescription)",
                remediation: "Check the SQL query syntax and database schema",
                underlying: error
            ))
        }
    }

    // MARK: - Helpers

    /// Convert a GRDB DatabaseValue to a JSONValue.
    private func databaseValueToJSON(_ value: DatabaseValue) -> JSONValue {
        switch value.storage {
        case .null:
            return .null
        case .int64(let i):
            return .number(Double(i))
        case .double(let d):
            return .number(d)
        case .string(let s):
            return .string(s)
        case .blob(let data):
            return .string("[blob, \(data.count) bytes]")
        }
    }

    private func elapsedMs(since start: ContinuousClock.Instant) -> Int {
        let elapsed = ContinuousClock.now - start
        return Int(elapsed.components.seconds * 1000
            + elapsed.components.attoseconds / 1_000_000_000_000_000)
    }
}

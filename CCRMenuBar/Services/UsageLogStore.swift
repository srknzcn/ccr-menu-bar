import Foundation
import SQLite3

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

struct UsageLogRecord {
    let context: ProxyUsageLogContext
    let completedAt: Date
    let statusCode: Int
    let outputTokens: Int
    let error: String?
    let responseBodyBytes: Int?
    let upstreamInputTokens: Int?
    let upstreamOutputTokens: Int?
}

struct StoredUsageEvent {
    let requestId: String
    let startedAt: Date
    let route: String
    let provider: String?
    let model: String?
    let requestModel: String?
    let inputTokens: Int
    let outputTokens: Int
    let statusCode: Int
}

enum UsageLogStore {
    private static let queue = DispatchQueue(label: "com.ccr.menubar.usage-log-store")
    static let didAppendNotification = Notification.Name("CCRMenuBarUsageLogStoreDidAppend")

    static var databaseURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude-code-router/ccr-menu-bar-usage.sqlite3")
    }

    static func bootstrap() {
        queue.async {
            let url = databaseURL
            try? FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )

            var db: OpaquePointer?
            guard sqlite3_open(url.path, &db) == SQLITE_OK, let db else {
                sqlite3_close(db)
                return
            }
            defer { sqlite3_close(db) }
            _ = ensureSchema(db)
        }
    }

    static func append(_ record: UsageLogRecord) {
        queue.async {
            if write(record) {
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: didAppendNotification, object: nil)
                }
            }
        }
    }

    static func fetchEvents() -> [StoredUsageEvent] {
        queue.sync {
            readEvents()
        }
    }

    private static func readEvents() -> [StoredUsageEvent] {
        let url = databaseURL
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }

        var db: OpaquePointer?
        guard sqlite3_open(url.path, &db) == SQLITE_OK, let db else {
            sqlite3_close(db)
            return []
        }
        defer { sqlite3_close(db) }

        guard ensureSchema(db) else { return [] }

        let sql = """
        SELECT request_id, started_at, route, provider, model, request_model,
               input_tokens_estimated, output_tokens_estimated, status_code
        FROM usage_events
        ORDER BY started_at ASC;
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            sqlite3_finalize(statement)
            return []
        }
        defer { sqlite3_finalize(statement) }

        var events: [StoredUsageEvent] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let requestId = text(statement, 0),
                  let startedAtString = text(statement, 1),
                  let startedAt = date(from: startedAtString),
                  let route = text(statement, 2) else {
                continue
            }

            events.append(StoredUsageEvent(
                requestId: requestId,
                startedAt: startedAt,
                route: route,
                provider: text(statement, 3),
                model: text(statement, 4),
                requestModel: text(statement, 5),
                inputTokens: Int(sqlite3_column_int64(statement, 6)),
                outputTokens: Int(sqlite3_column_int64(statement, 7)),
                statusCode: Int(sqlite3_column_int64(statement, 8))
            ))
        }

        return events
    }

    private static func write(_ record: UsageLogRecord) -> Bool {
        let url = databaseURL
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        var db: OpaquePointer?
        guard sqlite3_open(url.path, &db) == SQLITE_OK, let db else {
            sqlite3_close(db)
            return false
        }
        defer { sqlite3_close(db) }

        guard ensureSchema(db) else { return false }

        let startedAt = isoString(record.context.startedAt)
        let completedAt = isoString(record.completedAt)
        let day = dayString(record.context.startedAt)
        let durationMs = Int(record.completedAt.timeIntervalSince(record.context.startedAt) * 1000)
        let totalTokens = record.context.inputTokens + record.outputTokens

        let sql = """
        INSERT OR REPLACE INTO usage_events (
            request_id, day, started_at, completed_at, duration_ms,
            method, path, target_path, session, preset_id, preset, route,
            provider, model, request_model,
            input_tokens_estimated, output_tokens_estimated, total_tokens_estimated,
            upstream_input_tokens, upstream_output_tokens,
            status_code, error, response_body_bytes
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            sqlite3_finalize(statement)
            return false
        }
        defer { sqlite3_finalize(statement) }

        bindText(statement, 1, record.context.requestId)
        bindText(statement, 2, day)
        bindText(statement, 3, startedAt)
        bindText(statement, 4, completedAt)
        sqlite3_bind_int64(statement, 5, Int64(durationMs))
        bindText(statement, 6, record.context.method)
        bindText(statement, 7, record.context.path)
        bindText(statement, 8, record.context.targetPath)
        bindText(statement, 9, record.context.session)
        bindText(statement, 10, record.context.presetId)
        bindText(statement, 11, record.context.presetName)
        bindText(statement, 12, record.context.route)
        bindText(statement, 13, record.context.provider)
        bindText(statement, 14, record.context.model)
        bindText(statement, 15, record.context.requestModel)
        sqlite3_bind_int64(statement, 16, Int64(record.context.inputTokens))
        sqlite3_bind_int64(statement, 17, Int64(record.outputTokens))
        sqlite3_bind_int64(statement, 18, Int64(totalTokens))
        bindInt(statement, 19, record.upstreamInputTokens)
        bindInt(statement, 20, record.upstreamOutputTokens)
        sqlite3_bind_int64(statement, 21, Int64(record.statusCode))
        bindText(statement, 22, record.error)
        bindInt(statement, 23, record.responseBodyBytes)

        return sqlite3_step(statement) == SQLITE_DONE
    }

    private static func ensureSchema(_ db: OpaquePointer) -> Bool {
        let statements = [
            """
            CREATE TABLE IF NOT EXISTS usage_events (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                request_id TEXT NOT NULL UNIQUE,
                day TEXT NOT NULL,
                started_at TEXT NOT NULL,
                completed_at TEXT NOT NULL,
                duration_ms INTEGER NOT NULL,
                method TEXT NOT NULL,
                path TEXT NOT NULL,
                target_path TEXT NOT NULL,
                session TEXT,
                preset_id TEXT,
                preset TEXT NOT NULL,
                route TEXT NOT NULL,
                provider TEXT,
                model TEXT,
                request_model TEXT,
                input_tokens_estimated INTEGER NOT NULL,
                output_tokens_estimated INTEGER NOT NULL,
                total_tokens_estimated INTEGER NOT NULL,
                upstream_input_tokens INTEGER,
                upstream_output_tokens INTEGER,
                status_code INTEGER NOT NULL,
                error TEXT,
                response_body_bytes INTEGER,
                created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
            );
            """,
            "CREATE INDEX IF NOT EXISTS idx_usage_events_day ON usage_events(day);",
            "CREATE INDEX IF NOT EXISTS idx_usage_events_started_at ON usage_events(started_at);",
            "CREATE INDEX IF NOT EXISTS idx_usage_events_preset_day ON usage_events(preset, day);",
            "CREATE INDEX IF NOT EXISTS idx_usage_events_provider_day ON usage_events(provider, day);",
            "CREATE INDEX IF NOT EXISTS idx_usage_events_model_day ON usage_events(model, day);",
            "CREATE INDEX IF NOT EXISTS idx_usage_events_route_day ON usage_events(route, day);",
            "CREATE INDEX IF NOT EXISTS idx_usage_events_session_day ON usage_events(session, day);",
        ]

        for sql in statements {
            if sqlite3_exec(db, sql, nil, nil, nil) != SQLITE_OK {
                return false
            }
        }
        return true
    }

    private static func bindText(_ statement: OpaquePointer, _ index: Int32, _ value: String?) {
        guard let value else {
            sqlite3_bind_null(statement, index)
            return
        }
        sqlite3_bind_text(statement, index, value, -1, SQLITE_TRANSIENT)
    }

    private static func bindInt(_ statement: OpaquePointer, _ index: Int32, _ value: Int?) {
        guard let value else {
            sqlite3_bind_null(statement, index)
            return
        }
        sqlite3_bind_int64(statement, index, Int64(value))
    }

    private static func text(_ statement: OpaquePointer, _ index: Int32) -> String? {
        guard let value = sqlite3_column_text(statement, index) else { return nil }
        return String(cString: value)
    }

    private static func isoString(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    private static func date(from string: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: string) {
            return date
        }

        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: string)
    }

    private static func dayString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = .autoupdatingCurrent
        formatter.locale = .autoupdatingCurrent
        formatter.timeZone = .autoupdatingCurrent
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}

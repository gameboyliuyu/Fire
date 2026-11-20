//
//  DictBuilder.swift
//  Fire
//
//  进程内构建 dict.sqlite（替代原 TableBuilder 可执行文件）。
//

import Foundation

enum DictBuilder {
    static func build(
        wbPath: String,
        pyPath: String,
        dbPath: String,
        wbSpellPath: String?,
        pinyinSpellPath: String?,
        emojiPath: String? = nil,
        pyFreqPath: String? = nil
    ) -> Bool {
        guard FileManager.default.fileExists(atPath: wbPath) else {
            print("[DictBuilder] wb table not found: \(wbPath)")
            return false
        }
        guard FileManager.default.fileExists(atPath: pyPath) else {
            print("[DictBuilder] py table not found: \(pyPath)")
            return false
        }

        var db: OpaquePointer?
        guard sqlite3_open(dbPath, &db) == SQLITE_OK else {
            print("[DictBuilder] cannot open db: \(dbPath)")
            return false
        }
        defer { sqlite3_close(db) }

        // 构建期加速（仅临时 .ing 库）
        sqlite3_exec(db, "PRAGMA journal_mode=MEMORY", nil, nil, nil)
        sqlite3_exec(db, "PRAGMA synchronous=OFF", nil, nil, nil)

        guard DictTableImporter.importTable(db: db, txtPath: wbPath, tableName: "wb_dict") else {
            return false
        }
        guard DictTableImporter.importTable(db: db, txtPath: pyPath, tableName: "py_dict") else {
            return false
        }
        guard combineWbPy(db: db, emojiPath: emojiPath) else { return false }

        if let wbSpellPath, let pinyinSpellPath,
           FileManager.default.fileExists(atPath: wbSpellPath),
           FileManager.default.fileExists(atPath: pinyinSpellPath) {
            guard DictSpellingMerge.merge(db: db, wbSpellPath: wbSpellPath, pinyinSpellPath: pinyinSpellPath) else {
                return false
            }
        } else {
            print("[DictBuilder] spelling files missing, skip merge")
        }

        // 用系统编码对所有单字统一标定 is_gb2312（覆盖码表默认值）
        guard CharsetGB2312.updateDatabaseFlags(db: db) else {
            print("[DictBuilder] update GB2312 flags failed")
            return false
        }
        // emoji 不参与 GB2312 判定，强制保留可见（关闭生僻字时仍可出）
        if sqlite3_exec(db, "update wb_py_dict set is_gb2312 = 1 where type = 'emoji'", nil, nil, nil) != SQLITE_OK {
            print("[DictBuilder] reset emoji is_gb2312 failed: \(errmsg(db))")
            return false
        }
        // 词频：写入 freq 列并补入 jieba 高频词，供候选按频率排序
        if let pyFreqPath, FileManager.default.fileExists(atPath: pyFreqPath) {
            guard applyPinyinFrequency(db: db, path: pyFreqPath) else {
                print("[DictBuilder] applyPinyinFrequency failed")
                return false
            }
        } else {
            print("[DictBuilder] pinyin freq table not found, candidates fall back to alpha order")
        }

        print("[DictBuilder] build complete: \(dbPath)")
        return true
    }

    /// 读取 py_freq_table.txt（拼音<TAB>词<TAB>词频<TAB>五笔码），
    /// 1) UPDATE 现有 py 词条的 freq；2) INSERT 库中没有的高频词。
    private static func applyPinyinFrequency(db: OpaquePointer?, path: String) -> Bool {
        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else {
            print("[DictBuilder] cannot read freq table: \(path)")
            return false
        }
        guard let updateStmt = prepareStmt(db, """
            update wb_py_dict set freq = ?1 where type = 'py' and query = ?2 and text = ?3
            """) else { return false }
        defer { sqlite3_finalize(updateStmt) }
        // 补入词：wbcode 尽量用词表提供的（后缀合并词可能为空），空则跳过五笔码
        guard let insertStmt = prepareStmt(db, """
            insert into wb_py_dict(wbcode, text, type, query, freq, is_gb2312)
            values(?1, ?2, 'py', ?3, ?4, 1)
            """) else { return false }
        defer { sqlite3_finalize(insertStmt) }
        guard let checkStmt = prepareStmt(db, """
            select 1 from wb_py_dict where type = 'py' and query = ?1 and text = ?2 limit 1
            """) else { return false }
        defer { sqlite3_finalize(checkStmt) }

        sqlite3_exec(db, "BEGIN TRANSACTION", nil, nil, nil)
        var updated = 0, inserted = 0
        for line in content.split(whereSeparator: \.isNewline) {
            let cols = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard cols.count >= 3, let freq = Int32(cols[2]) else { continue }
            let py = cols[0], text = cols[1]
            let wbcode = cols.count >= 4 ? cols[3] : ""
            // 先查是否存在
            sqlite3_reset(checkStmt); sqlite3_clear_bindings(checkStmt)
            sqlite3_bind_text(checkStmt, 1, py, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(checkStmt, 2, text, -1, SQLITE_TRANSIENT)
            let exists = sqlite3_step(checkStmt) == SQLITE_ROW
            if exists {
                sqlite3_reset(updateStmt); sqlite3_clear_bindings(updateStmt)
                sqlite3_bind_int(updateStmt, 1, freq)
                sqlite3_bind_text(updateStmt, 2, py, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(updateStmt, 3, text, -1, SQLITE_TRANSIENT)
                if sqlite3_step(updateStmt) == SQLITE_DONE { updated += 1 }
            } else {
                sqlite3_reset(insertStmt); sqlite3_clear_bindings(insertStmt)
                sqlite3_bind_text(insertStmt, 1, wbcode, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(insertStmt, 2, text, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(insertStmt, 3, py, -1, SQLITE_TRANSIENT)
                sqlite3_bind_int(insertStmt, 4, freq)
                if sqlite3_step(insertStmt) == SQLITE_DONE { inserted += 1 }
            }
        }
        guard sqlite3_exec(db, "COMMIT", nil, nil, nil) == SQLITE_OK else {
            print("[DictBuilder] freq commit failed: \(errmsg(db))")
            sqlite3_exec(db, "ROLLBACK", nil, nil, nil)
            return false
        }
        print("[DictBuilder] freq applied: updated=\(updated) inserted=\(inserted)")
        return true
    }

    private static func prepareStmt(_ db: OpaquePointer?, _ sql: String) -> OpaquePointer? {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            print("[DictBuilder] prepare freq stmt failed: \(errmsg(db))")
            return nil
        }
        return stmt
    }

    /// 解析 emoji_table.txt：首列为关键词，后续每列为 emoji
    private static func loadEmojiMap(path: String?) -> [String: [String]] {
        guard let path, FileManager.default.fileExists(atPath: path) else {
            if let path {
                print("[DictBuilder] emoji table not found, skip: \(path)")
            } else {
                print("[DictBuilder] emoji path nil, skip")
            }
            return [:]
        }
        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else {
            print("[DictBuilder] cannot read emoji table: \(path)")
            return [:]
        }
        var map: [String: [String]] = [:]
        for line in content.split(whereSeparator: \.isNewline) {
            let fields = DictTableImporter.splitFields(String(line))
            guard fields.count >= 2 else { continue }
            let keyword = fields[0]
            let emojis = Array(fields.dropFirst())
            guard !emojis.isEmpty else { continue }
            map[keyword] = emojis
        }
        print("[DictBuilder] emoji map loaded: \(map.count) keywords")
        return map
    }

    private static func combineWbPy(db: OpaquePointer?, emojiPath: String?) -> Bool {
        let createTable = """
            create table wb_py_dict (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              wbcode text not null,
              text text not null,
              type text not null,
              query text not null,
              version text default null,
              spell text default null,
              pinyin text default null,
              freq integer default 0,
              is_gb2312 integer default 1
            );
            insert into sqlite_sequence(name, seq) values('wb_py_dict', 100000);
            """
        guard sqlite3_exec(db, createTable, nil, nil, nil) == SQLITE_OK else {
            print("[DictBuilder] create wb_py_dict failed: \(errmsg(db))")
            return false
        }

        let emojiMap = loadEmojiMap(path: emojiPath)
        var hitKeywords = Set<String>()
        var emojiRows = 0

        let insertSQL = """
            insert into wb_py_dict(wbcode, text, type, query, is_gb2312)
            values(?1, ?2, ?3, ?4, ?5)
            """
        var insertStmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, insertSQL, -1, &insertStmt, nil) == SQLITE_OK else {
            print("[DictBuilder] prepare insert failed: \(errmsg(db))")
            return false
        }
        defer { sqlite3_finalize(insertStmt) }

        func insertRow(wbcode: String, text: String, type: String, query: String, isGB2312: Int32 = 1) -> Bool {
            sqlite3_reset(insertStmt)
            sqlite3_clear_bindings(insertStmt)
            sqlite3_bind_text(insertStmt, 1, wbcode, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(insertStmt, 2, text, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(insertStmt, 3, type, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(insertStmt, 4, query, -1, SQLITE_TRANSIENT)
            sqlite3_bind_int(insertStmt, 5, isGB2312)
            return sqlite3_step(insertStmt) == SQLITE_DONE
        }

        func appendEmojis(after text: String, code: String) -> Bool {
            guard let emojis = emojiMap[text] else { return true }
            hitKeywords.insert(text)
            for emoji in emojis {
                guard insertRow(wbcode: code, text: emoji, type: "emoji", query: code, isGB2312: 1) else {
                    return false
                }
                emojiRows += 1
            }
            return true
        }

        sqlite3_exec(db, "BEGIN TRANSACTION", nil, nil, nil)

        // 1) 五笔：按 wb_dict.id 顺序写入，关键词后紧跟 emoji
        var wbSelect: OpaquePointer?
        let wbSQL = "select code, text from wb_dict order by id"
        guard sqlite3_prepare_v2(db, wbSQL, -1, &wbSelect, nil) == SQLITE_OK else {
            print("[DictBuilder] prepare wb select failed: \(errmsg(db))")
            sqlite3_exec(db, "ROLLBACK", nil, nil, nil)
            return false
        }
        while sqlite3_step(wbSelect) == SQLITE_ROW {
            guard let codeC = sqlite3_column_text(wbSelect, 0),
                  let textC = sqlite3_column_text(wbSelect, 1) else { continue }
            let code = String(cString: codeC)
            let text = String(cString: textC)
            guard insertRow(wbcode: code, text: text, type: "wb", query: code) else {
                print("[DictBuilder] insert wb failed: \(errmsg(db))")
                sqlite3_finalize(wbSelect)
                sqlite3_exec(db, "ROLLBACK", nil, nil, nil)
                return false
            }
            guard appendEmojis(after: text, code: code) else {
                print("[DictBuilder] insert wb emoji failed: \(errmsg(db))")
                sqlite3_finalize(wbSelect)
                sqlite3_exec(db, "ROLLBACK", nil, nil, nil)
                return false
            }
        }
        sqlite3_finalize(wbSelect)

        // 2) 拼音：与原 SQL 一致（py ∩ wb），按 py.id；每条后跟 emoji
        var pySelect: OpaquePointer?
        let pySQL = """
            select wb.code, py.text, py.code
            from py_dict py
            inner join wb_dict wb on py.text = wb.text
            order by py.id
            """
        guard sqlite3_prepare_v2(db, pySQL, -1, &pySelect, nil) == SQLITE_OK else {
            print("[DictBuilder] prepare py select failed: \(errmsg(db))")
            sqlite3_exec(db, "ROLLBACK", nil, nil, nil)
            return false
        }
        while sqlite3_step(pySelect) == SQLITE_ROW {
            guard let wbcodeC = sqlite3_column_text(pySelect, 0),
                  let textC = sqlite3_column_text(pySelect, 1),
                  let pycodeC = sqlite3_column_text(pySelect, 2) else { continue }
            let wbcode = String(cString: wbcodeC)
            let text = String(cString: textC)
            let pycode = String(cString: pycodeC)
            guard insertRow(wbcode: wbcode, text: text, type: "py", query: pycode) else {
                print("[DictBuilder] insert py failed: \(errmsg(db))")
                sqlite3_finalize(pySelect)
                sqlite3_exec(db, "ROLLBACK", nil, nil, nil)
                return false
            }
            guard appendEmojis(after: text, code: pycode) else {
                print("[DictBuilder] insert py emoji failed: \(errmsg(db))")
                sqlite3_finalize(pySelect)
                sqlite3_exec(db, "ROLLBACK", nil, nil, nil)
                return false
            }
        }
        sqlite3_finalize(pySelect)

        let indexSQL = """
            create index if not exists query_index on wb_py_dict(query);
            create index if not exists text_index on wb_py_dict(text);
            create index if not exists query_text_wbcode_index on wb_py_dict(query, text, wbcode);
            """
        guard sqlite3_exec(db, indexSQL, nil, nil, nil) == SQLITE_OK else {
            print("[DictBuilder] create index failed: \(errmsg(db))")
            sqlite3_exec(db, "ROLLBACK", nil, nil, nil)
            return false
        }

        guard sqlite3_exec(db, "COMMIT", nil, nil, nil) == SQLITE_OK else {
            print("[DictBuilder] commit wb_py_dict failed: \(errmsg(db))")
            return false
        }

        let missed = emojiMap.count - hitKeywords.count
        print("[DictBuilder] wb_py_dict combined; emoji rows=\(emojiRows), keywords hit=\(hitKeywords.count), missed=\(missed)")
        return true
    }

    private static func errmsg(_ db: OpaquePointer?) -> String {
        guard let db = db, let c = sqlite3_errmsg(db) else { return "unknown" }
        return String(cString: c)
    }
}

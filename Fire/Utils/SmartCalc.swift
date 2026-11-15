//
//  SmartCalc.swift
//  Fire
//
//  Created by enhance branch (2026): 内联计算器 / 大写金额 / 中文日期
//

import Foundation

enum SmartCalc {
    // MARK: - 表达式求值

    /// 仅允许数字、四则运算符、括号、小数点、百分号，防止注入
    private static let exprRegex = try! NSRegularExpression(pattern: "^[0-9+\\-*/().%\\s]+$")

    /// 求值算术表达式，如 "3+5*2" → 13
    /// 用纯 Swift 递归下降实现，全程 Double 运算：
    /// 不用 NSExpression（其整数除法会整除、且非法格式抛 ObjC 异常无法用 Swift catch 捕获）
    static func evaluate(_ expr: String) -> Double? {
        let trimmed = expr.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty,
              exprRegex.firstMatch(in: trimmed, range: NSRange(location: 0, length: trimmed.utf16.count)) != nil else {
            return nil
        }
        var parser = ExprParser(Array(trimmed))
        guard let value = parser.parseExpression(), parser.isAtEnd else { return nil }
        guard value.isFinite else { return nil } // 除以 0 的无穷大视为无效
        // 规整浮点误差：350*1.13 得到 395.49999999999994，固定 6 位小数归到 395.5
        return (value * 1e6).rounded() / 1e6
    }

    /// 递归下降解析器：expression = term (('+'|'-') term)*
    ///                 term      = factor (('*'|'/') factor)*
    ///                 factor    = number | '(' expression ')' | factor '%'
    private struct ExprParser {
        private let chars: [Character]
        private var pos = 0

        init(_ chars: [Character]) { self.chars = chars }
        var isAtEnd: Bool { pos >= chars.count }

        private var current: Character? { pos < chars.count ? chars[pos] : nil }

        private mutating func skipSpaces() {
            while pos < chars.count && chars[pos] == " " { pos += 1 }
        }

        mutating func parseExpression() -> Double? {
            var value = parseTerm() ?? 0
            while true {
                skipSpaces()
                guard let c = current else { break }
                if c == "+" || c == "-" {
                    pos += 1
                    guard let rhs = parseTerm() else { return nil }
                    value = (c == "+") ? value + rhs : value - rhs
                } else {
                    break
                }
            }
            return value
        }

        private mutating func parseTerm() -> Double? {
            var value = parseFactor() ?? 0
            while true {
                skipSpaces()
                guard let c = current else { break }
                if c == "*" || c == "/" {
                    pos += 1
                    guard let rhs = parseFactor() else { return nil }
                    if c == "*" {
                        value = value * rhs
                    } else {
                        if rhs == 0 { return nil } // 除零 → 无效
                        value = value / rhs
                    }
                } else {
                    break
                }
            }
            return value
        }

        private mutating func parseFactor() -> Double? {
            skipSpaces()
            guard let c = current else { return nil }
            var value: Double
            if c == "(" {
                pos += 1
                guard let inner = parseExpression() else { return nil }
                skipSpaces()
                guard current == ")" else { return nil }
                pos += 1
                value = inner
            } else if c.isNumber || c == "." {
                // 读一个数字字面量
                var buf = ""
                while pos < chars.count, chars[pos].isNumber || chars[pos] == "." {
                    buf.append(chars[pos]); pos += 1
                }
                guard let n = Double(buf) else { return nil }
                value = n
            } else {
                return nil
            }
            // 后缀百分号：50% → 50/100；允许连续 %（200%% → 0.02）
            while true {
                skipSpaces()
                guard current == "%" else { break }
                pos += 1
                value = value / 100
            }
            return value
        }
    }

    /// 格式化计算结果：整数不带小数点，最多保留 6 位小数并去尾零
    static func formatResult(_ value: Double) -> String {
        if value == value.rounded() && abs(value) < 1e15 {
            return String(format: "%.0f", value)
        }
        return String(format: "%.6f", value).replacingOccurrences(
            of: #"\.?0+$"#,
            with: "",
            options: .regularExpression
        )
    }

    // MARK: - 大写金额

    private static let cnDigits = ["零", "壹", "贰", "叁", "肆", "伍", "陆", "柒", "捌", "玖"]
    private static let smallUnits = ["", "拾", "佰", "仟"]
    private static let bigUnits = ["", "万", "亿", "万亿"]

    /// 判断字符串是否为金额形态（纯数字，最多两位小数）
    static func isAmount(_ s: String) -> Bool {
        return s.range(of: #"^\d+(\.\d{1,2})?$"#, options: .regularExpression) != nil
    }

    /// 数字转人民币大写金额："350" → "叁佰伍拾元整"，"350.56" → "叁佰伍拾元伍角陆分"
    static func uppercaseCurrency(_ s: String) -> String? {
        let trimmed = s.trimmingCharacters(in: .whitespaces)
        guard isAmount(trimmed) else { return nil }
        // 允许 "0.05" 这类纯小数；只拒绝 "0123" 这类多余前导零的整数
        if !trimmed.hasPrefix("0.") {
            let intPart = trimmed.split(separator: ".").first.map(String.init) ?? trimmed
            if intPart.count > 1 && intPart.hasPrefix("0") { return nil }
        }
        guard let value = Double(trimmed), value < 1e16 else { return nil }

        // 四舍五入到分
        let cents = Int((value * 100).rounded())
        if cents == 0 {
            return "零元整"
        }
        let yuanPart = cents / 100
        let jiao = (cents % 100) / 10
        let fen = cents % 10

        var result = ""
        if yuanPart > 0 {
            result += integerToCN(yuanPart) + "元"
        }
        if jiao > 0 {
            result += cnDigits[jiao] + "角"
        } else if yuanPart > 0 && fen > 0 {
            result += "零"
        }
        if fen > 0 {
            result += cnDigits[fen] + "分"
        }
        if jiao == 0 && fen == 0 {
            result += "整"
        }
        return result
    }

    /// 整数转中文数字（支持到万亿级）
    private static func integerToCN(_ number: Int) -> String {
        guard number > 0 else { return "零" }
        var groups: [Int] = [] // 从低位起，每 4 位一组
        var n = number
        while n > 0 {
            groups.append(n % 10000)
            n /= 10000
        }
        var parts: [String] = []
        for (i, group) in groups.enumerated().reversed() {
            if group == 0 { continue }
            var groupStr = fourDigitToCN(group)
            let bigUnit = bigUnits[i]
            // 低位组不足 4 位且前面有更高组，需要补零，如 10001 → 壹万零壹
            if i < groups.count - 1 && group < 1000 {
                groupStr = "零" + groupStr
            }
            parts.append(groupStr + bigUnit)
        }
        var result = parts.joined()
        while result.contains("零零") {
            result = result.replacingOccurrences(of: "零零", with: "零")
        }
        result = result.trimmingCharacters(in: CharacterSet(charactersIn: "零"))
        return result
    }

    private static func fourDigitToCN(_ num: Int) -> String {
        var result = ""
        var n = num
        var zeroPending = false
        var unitIndex = 0
        var leading = true
        while n > 0 {
            let digit = n % 10
            if digit == 0 {
                if !leading { zeroPending = true }
            } else {
                if zeroPending {
                    result = "零" + result
                    zeroPending = false
                }
                result = cnDigits[digit] + smallUnits[unitIndex] + result
                leading = false
            }
            n /= 10
            unitIndex += 1
        }
        return result.isEmpty ? "零" : result
    }

    // MARK: - 中文日期

    /// 判断是否为日期形态：2026-9-22 / 2026/09/22 / 2026.9.22
    static func isDateLike(_ s: String) -> Bool {
        return s.range(of: #"^\d{4}[-/.]\d{1,2}[-/.]\d{1,2}$"#, options: .regularExpression) != nil
    }

    /// "2026-9-22" → "二〇二六年九月二十二日"
    static func chineseDate(_ s: String) -> String? {
        let trimmed = s.trimmingCharacters(in: .whitespaces)
        guard isDateLike(trimmed) else { return nil }
        let parts = trimmed.split(whereSeparator: { "-/.".contains($0) }).compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        let (y, m, d) = (parts[0], parts[1], parts[2])
        guard (1...12).contains(m), (1...31).contains(d) else { return nil }

        // 年份用〇（小写圆圈零），数字本身cnDigits是壹贰叁，取模后映射需转小写
        let yearStr = String(y).map { cnDigitLower(Int(String($0))!) }.joined()
        let monthStr = cnMonth(m) + "月"
        let dayStr = cnDay(d) + "日"
        return yearStr + "年" + monthStr + dayStr
    }

    /// 小写数字（日期用）：〇一二三四五六七八九
    private static let lowerDigits = ["〇", "一", "二", "三", "四", "五", "六", "七", "八", "九"]
    private static func cnDigitLower(_ n: Int) -> String { lowerDigits[n] }

    private static func cnMonth(_ m: Int) -> String {
        if m <= 9 { return lowerDigits[m] }
        if m == 10 { return "十" }
        return "十" + lowerDigits[m - 10] // 十一、十二
    }

    private static func cnDay(_ d: Int) -> String {
        let tens = d / 10
        let ones = d % 10
        switch tens {
        case 0:
            return lowerDigits[ones]
        case 1:
            return ones == 0 ? "十" : "十" + lowerDigits[ones]
        default:
            return ones == 0 ? lowerDigits[tens] + "十" : lowerDigits[tens] + "十" + lowerDigits[ones]
        }
    }
}

//
//  SmartCalc.swift
//  Fire
//
//  Created by enhance branch (2026): 内联计算器 / 大写金额 / 中文日期
//

import Foundation

enum SmartCalc {
    // MARK: - 表达式求值

    /// 仅允许数字、四则运算符、括号、小数点、百分号，防止 NSExpression 注入
    private static let exprRegex = try! NSRegularExpression(pattern: "^[0-9+\\-*/().%\\s]+$")

    /// 求值算术表达式，如 "3+5*2" → 13
    static func evaluate(_ expr: String) -> Double? {
        let trimmed = expr.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty,
              exprRegex.firstMatch(in: trimmed, range: NSRange(location: 0, length: trimmed.utf16.count)) != nil else {
            return nil
        }
        // NSExpression 不认识 %，把 "50%" 预转换为 "(50/100)"
        let normalized = normalizePercent(trimmed)
        guard !normalized.isEmpty else { return nil }
        var expression: NSExpression
        do {
            expression = try NSExpression(format: normalized)
        } catch {
            return nil
        }
        guard let value = expression.expressionValue(with: nil, context: nil) as? Double else {
            return nil
        }
        guard value.isFinite else { return nil }
        return value
    }

    /// "50%" → "(50/100)"，连续百分号暂不支持
    private static func normalizePercent(_ expr: String) -> String {
        guard expr.contains("%") else { return expr }
        guard !expr.contains("%%") else { return "" }
        var result = ""
        var i = expr.startIndex
        while i < expr.endIndex {
            let c = expr[i]
            if c == "%" {
                // 向前找最近的数字字面量
                if let numStart = lastNumberStart(in: result) {
                    let number = String(result[numStart...])
                    result = String(result[..<numStart]) + "(\(number)/100)"
                } else {
                    return "" // 位置非法
                }
            } else {
                result.append(c)
            }
            i = expr.index(after: i)
        }
        return result
    }

    private static func lastNumberStart(in s: String) -> String.Index? {
        var idx = s.endIndex
        var started = false
        while idx > s.startIndex {
            let prev = s.index(before: idx)
            let c = s[prev]
            if c.isNumber || c == "." {
                idx = prev
                started = true
            } else {
                break
            }
        }
        return started ? idx : nil
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
        guard isAmount(trimmed), trimmed.hasPrefix("0") == false || trimmed == "0" else { return nil }
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
            if group == 0 {
                // 组为零，仅在中间补零由下一逻辑处理，此处跳过
                if i > 0, !parts.isEmpty, !parts.last!.hasSuffix("零"), groups[i - 1] != 0 {
                    // 保留跨组补零，如 100000100 → 壹亿零仟...（简化处理）
                }
                continue
            }
            var groupStr = fourDigitToCN(group)
            let bigUnit = bigUnits[i]
            // 低位组不足 4 位且前面有更高组，需要补零，如 10001 → 壹万零壹
            if i < groups.count - 1 && group < 1000 {
                groupStr = "零" + groupStr
            }
            parts.append(groupStr + bigUnit)
        }
        var result = parts.joined()
        // 清理多余的零
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
                if !leading {
                    zeroPending = true
                }
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

        let yearStr = String(y).map { cnDigits[Int(String($0))!] }.joined()
            .replacingOccurrences(of: "零", with: "〇")
        let monthStr = cnMonth(m) + "月"
        let dayStr = cnDay(d) + "日"
        return yearStr + "年" + monthStr + dayStr
    }

    private static func cnMonth(_ m: Int) -> String {
        if m <= 10 {
            return m == 10 ? "十" : cnDigits[m]
        }
        return m == 11 ? "十一" : "十二"
    }

    private static func cnDay(_ d: Int) -> String {
        let tens = d / 10
        let ones = d % 10
        switch tens {
        case 0:
            return cnDigits[ones]
        case 1:
            return ones == 0 ? "十" : "十" + cnDigits[ones]
        default:
            return ones == 0 ? cnDigits[tens] + "十" : cnDigits[tens] + "十" + cnDigits[ones]
        }
    }
}

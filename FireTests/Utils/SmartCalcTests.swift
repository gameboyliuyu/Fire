//
//  SmartCalcTests.swift
//  FireTests
//
//  Created by enhance branch (2026): 内联计算器/大写金额/中文日期 转换测试
//

import Testing
import Foundation
@testable import Fire

struct SmartCalcTests {
    // MARK: - 表达式求值

    @Test func evaluateBasics() {
        #expect(SmartCalc.evaluate("3+5*2") == 13)
        #expect(SmartCalc.evaluate("(1+2)*3") == 9)
        #expect(SmartCalc.evaluate("10/4") == 2.5)
        #expect(SmartCalc.evaluate("350*1.13") == 395.5)
    }

    @Test func evaluatePercent() {
        #expect(SmartCalc.evaluate("50%") == 0.5)
        #expect(SmartCalc.evaluate("200*50%") == 100)
    }

    @Test func evaluateRejectsInvalid() {
        #expect(SmartCalc.evaluate("") == nil)
        #expect(SmartCalc.evaluate("abc") == nil)
        #expect(SmartCalc.evaluate("3+;5") == nil)
        #expect(SmartCalc.evaluate("%") == nil)
        #expect(SmartCalc.evaluate("1/0") == nil) // 无穷大视为无效
    }

    @Test func formatResult() {
        #expect(SmartCalc.formatResult(13) == "13")
        #expect(SmartCalc.formatResult(2.5) == "2.5")
        #expect(SmartCalc.formatResult(1.0 / 3.0) == "0.333333")
    }

    // MARK: - 大写金额

    @Test func uppercaseCurrency() {
        #expect(SmartCalc.uppercaseCurrency("350") == "叁佰伍拾元整")
        #expect(SmartCalc.uppercaseCurrency("350.5") == "叁佰伍拾元伍角")
        #expect(SmartCalc.uppercaseCurrency("350.56") == "叁佰伍拾元伍角陆分")
        #expect(SmartCalc.uppercaseCurrency("0.05") == "伍分")
        #expect(SmartCalc.uppercaseCurrency("10") == "壹拾元整")
        #expect(SmartCalc.uppercaseCurrency("10001") == "壹万零壹元整")
    }

    @Test func uppercaseCurrencyRejectsInvalid() {
        #expect(SmartCalc.uppercaseCurrency("3+5") == nil)
        #expect(SmartCalc.uppercaseCurrency("1.234") == nil) // 超过两位小数
        #expect(SmartCalc.uppercaseCurrency("abc") == nil)
    }

    // MARK: - 中文日期

    @Test func chineseDate() {
        #expect(SmartCalc.chineseDate("2026-9-22") == "二〇二六年九月二十二日")
        #expect(SmartCalc.chineseDate("2026/09/22") == "二〇二六年九月二十二日")
        #expect(SmartCalc.chineseDate("2026.12.31") == "二〇二六年十二月三十一日")
        #expect(SmartCalc.chineseDate("2026-10-01") == "二〇二六年十月一日")
    }

    @Test func chineseDateRejectsInvalid() {
        #expect(SmartCalc.chineseDate("2026-13-01") == nil)
        #expect(SmartCalc.chineseDate("2026-9") == nil)
        #expect(SmartCalc.chineseDate("abc") == nil)
    }
}

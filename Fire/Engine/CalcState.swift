//
//  CalcState.swift
//  Fire
//
//  Created by enhance branch (2026): 内联计算器子状态
//  输入 "=" 进入：实时计算表达式、转大写金额、转中文日期
//

import Carbon
import Foundation

struct CalcState: InputState {
    var config: any EngineConfig

    /// 允许追加到表达式的字符集
    private static let allowedChars = CharacterSet(charactersIn: "0123456789+-*/().%")

    func didEnter(_ context: inout any InputContext) {
        context.origin = "="
        refresh(&context)
    }

    private func refresh(_ context: inout any InputContext) {
        let expr = String(context.origin.dropFirst())
        var candidates: [Candidate] = []
        if !expr.isEmpty {
            if let value = SmartCalc.evaluate(expr) {
                candidates.append(Candidate(
                    code: context.origin,
                    text: SmartCalc.formatResult(value),
                    type: .unknown,
                    label: "= \(expr) ="
                ))
            }
            if SmartCalc.isAmount(expr), let currency = SmartCalc.uppercaseCurrency(expr) {
                candidates.append(Candidate(
                    code: context.origin,
                    text: currency,
                    type: .unknown,
                    label: "大写金额"
                ))
            }
            if SmartCalc.isDateLike(expr), let date = SmartCalc.chineseDate(expr) {
                candidates.append(Candidate(
                    code: context.origin,
                    text: date,
                    type: .unknown,
                    label: "中文日期"
                ))
            }
        }
        if candidates.isEmpty {
            candidates = [Candidate(
                code: context.origin,
                text: "",
                type: .placeholder,
                label: "计算器：=3+5*2 / =350.56 / =2026-9-22，空格上屏，Esc 退出"
            )]
        }
        context.candidates = candidates
        context.hasNext = false
        context.curPage = 1
        context.selectedIndex = 0
    }

    mutating func handle(_ event: KeyInput, context: inout any InputContext) -> HandleResult {
        // 数字/运算符：追加到表达式
        if event.modifiers.isEmpty, let char = event.characters,
           char.rangeOfCharacter(from: Self.allowedChars.inverted) == nil,
           !char.isEmpty {
            context.origin += char
            refresh(&context)
            return .stay(true)
        }

        switch Int(event.keyCode) {
        case kVK_Delete:
            if context.origin.count > 1 {
                context.origin = String(context.origin.dropLast())
                refresh(&context)
                return .stay(true)
            }
            return .exit(true) // 只剩 "="，删除即退出
        case kVK_Space:
            // 空格上屏第一个候选（计算结果/金额/日期）
            if let first = context.candidates.first, first.type != .placeholder {
                context.commit(first.text)
            }
            return .exit(true)
        case kVK_Return:
            // 回车上屏原始输入
            context.commit(context.origin)
            return .exit(true)
        case kVK_Escape:
            return .exit(true)
        default:
            // 其它按键（字母等）：退出计算器，事件不消费，交还系统处理
            return .exit(false)
        }
    }

    func willExit(_ context: inout any InputContext) {
        context.origin = ""
        context.candidates = []
        context.curPage = 1
        context.hasNext = false
        context.selectedIndex = 0
    }
}

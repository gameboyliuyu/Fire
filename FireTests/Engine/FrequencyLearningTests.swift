//
//  FrequencyLearningTests.swift
//  FireTests
//
//  词频学习（同意点选入库）测试：
//  - 只统计从候选栏上屏的中文词
//  - 满阈值后提示，按 ⌃⌥= 同意才入库
//  - 系统不猜打字流水，不产垃圾词
//

import Testing
@testable import Fire

struct FrequencyLearningTests {
    /// 选中候选一次（模拟按数字键 1 上屏）
    private func pick(_ root: RootState, _ context: inout any InputContext, text: String) {
        context.origin = "a"
        context.candidates = [TestFixtures.candidate(text, code: "a")]
        _ = root.handle(Key.digit(1), context: &context)
    }

    @Test func disabled_doesNotLearn() {
        var config = MockEngineConfig()
        config.enableFrequencyLearning = false
        let (root, _, dict, _) = TestFixtures.makeRootState(config: config)
        var context: any InputContext = MockInputContext()
        for _ in 0..<5 { pick(root, &context, text: "舆情") }
        #expect(dict.addedUserTexts.isEmpty)
    }

    @Test func thresholdReached_showsPromptButDoesNotStoreYet() {
        var config = MockEngineConfig()
        config.enableFrequencyLearning = true
        config.frequencyThreshold = 3
        let (root, _, dict, mockContext) = TestFixtures.makeRootState(config: config)
        var context: any InputContext = mockContext
        for _ in 0..<3 { pick(root, &context, text: "舆情") }
        // 满阈值只提示，绝不自动入库
        #expect(dict.addedUserTexts.isEmpty)
        #expect(mockContext.messages.contains { $0.contains("舆情") && $0.contains("存入") })
    }

    @Test func acceptShortcut_storesWord() {
        var config = MockEngineConfig()
        config.enableFrequencyLearning = true
        config.frequencyThreshold = 2
        let (root, _, dict, _) = TestFixtures.makeRootState(config: config)
        var context: any InputContext = MockInputContext()
        dict.wubiCodes["舆情"] = "wfng"
        for _ in 0..<2 { pick(root, &context, text: "舆情") }

        let accept = Key.ctrlOptionEqual()
        _ = root.handle(accept, context: &context)

        #expect(dict.addedUserTexts.count == 1)
        #expect(dict.addedUserTexts.first?.text == "舆情")
        #expect(dict.addedUserTexts.first?.origin == "wfng")
    }

    @Test func acceptShortcut_withoutPending_doesNothing() {
        var config = MockEngineConfig()
        config.enableFrequencyLearning = true
        let (root, _, dict, _) = TestFixtures.makeRootState(config: config)
        var context: any InputContext = MockInputContext()
        let accept = Key.ctrlOptionEqual()
        _ = root.handle(accept, context: &context)
        #expect(dict.addedUserTexts.isEmpty)
    }

    @Test func ignoredWord_doesNotPromptAgain() {
        var config = MockEngineConfig()
        config.enableFrequencyLearning = true
        config.frequencyThreshold = 2
        let (root, _, dict, mockContext) = TestFixtures.makeRootState(config: config)
        var context: any InputContext = MockInputContext()
        // 舆情满阈值弹出提示，但用户不按同意，继续打别的词 → 视为忽略
        for _ in 0..<2 { pick(root, &context, text: "舆情") }
        pick(root, &context, text: "文件")
        mockContext.messages.removeAll()
        for _ in 0..<3 { pick(root, &context, text: "舆情") }
        #expect(!mockContext.messages.contains { $0.contains("舆情") && $0.contains("存入") })
        #expect(dict.addedUserTexts.isEmpty)
    }

    @Test func blockedWord_isNeverLearned() {
        var config = MockEngineConfig()
        config.enableFrequencyLearning = true
        config.frequencyThreshold = 2
        let (root, _, dict, _) = TestFixtures.makeRootState(config: config)
        var context: any InputContext = MockInputContext()
        dict.blockedTexts.insert("舆情")
        for _ in 0..<4 { pick(root, &context, text: "舆情") }
        #expect(dict.addedUserTexts.isEmpty)
    }
}

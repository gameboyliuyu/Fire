//
//  EngineDictManager.swift
//  Fire
//
//  Created by qwertyyb on 2026/8/3.
//

protocol EngineDictManager {
    func query(_ origin: String, page: Int) -> (candidates: [Candidate], hasNext: Bool)
    
    func queryWubiCode(_ text: String) -> String?
    
    func setCandidateToFirst(_ origin: String, candidate: Candidate)
    
    // 屏蔽候选词
    func blockCandidate(_ candidate: Candidate)
    
    func isBlocked(_ text: String) -> Bool
    
    func unblockText(_ text: String)
    
    // 添加用户词
    func addUserText(origin: String, text: String)

    // 查询是否已存在同文本用户词（自动造词去重用）
    func isUserWord(_ text: String) -> Bool

    // 查询文本是否已存在于词库（wb/py/user 任意类型）：已存在的词无需提示入库
    func hasText(_ text: String) -> Bool
}

// 默认实现：无用户词库能力的实现方返回 false
extension EngineDictManager {
    func isUserWord(_ text: String) -> Bool { false }
    func hasText(_ text: String) -> Bool { false }
}

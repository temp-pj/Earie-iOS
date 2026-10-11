//
//  RoundData.swift
//  Models
//
//  Created by 송지혁 on 5/3/26.
//

import Foundation

public struct RoundData: Equatable, Sendable, Decodable {
    public let roundNumber: Int
    public let totalRounds: Int
    public let answerLength: Int
    public let letterCards: [String]
    
    public init(roundNumber: Int, totalRounds: Int, letterCards: [String], answerLength: Int) {
        self.roundNumber = roundNumber
        self.totalRounds = totalRounds
        self.answerLength = answerLength
        self.letterCards = letterCards
    }
}

//
//  HesabeModels.swift
//  HesabeSwiftDemo
//
//  Created by Mohammed Salman on 29/03/20.
//  Copyright © 2020 Mohammed Salman. All rights reserved.
//

import Foundation

struct PaymentRequest: Codable {
    
    private var merchantCode:String
    var amount:String = "0"
    private(set) var responseUrl:String
    private(set) var failureUrl:String
    var variable1:String?
    var variable2:String?
    var variable3:String?
    var variable4:String?
    var variable5:String?
    private var paymentType:String = "0"
    private var version:String = "2.0"
    
    init?(code: String, responseUrl: String, failureUrl: String, type: String = "0") {
        
        guard !code.isEmpty && code.rangeOfCharacter(from: CharacterSet.decimalDigits.inverted) == nil
            else {
            debugPrint("Error: Failed to set merchant code.")
            return nil
        }
        
        guard !type.isEmpty && type.rangeOfCharacter(from: CharacterSet.decimalDigits.inverted) == nil && type >= "0" && type <= "2" else {
            debugPrint("Error: Failed to set payment type")
            return nil
        }

        self.merchantCode = code
        self.responseUrl  = responseUrl
        self.failureUrl  = failureUrl
        self.paymentType  = type
    }
    
    enum CodingKeys: String, CodingKey {
        case merchantCode, amount, responseUrl, variable1, variable2, variable3, variable4, variable5, paymentType, version, failureUrl
    }
}

struct PaymentToken: Codable {
    var status: Bool
    var code: Int
    var message: String
    var response: HesabeToken
    
    enum CodingKeys: String, CodingKey {
        case status, code, message, response
    }
    
    struct HesabeToken: Codable {
        var data: String
        
        enum CodingKeys: String, CodingKey {
            case data
        }
    }
}

struct PaymentResponse: Codable {
    var status: Bool
    var code: Int
    var message: String
    var response: ResponseDetail
    
    enum CodingKeys: String, CodingKey {
        case status, code, message, response
    }
    
    struct ResponseDetail: Codable {
        var resultCode:String
        var amount:Float
        var paymentToken:String
        var paymentId:String
        var paidOn:String
        var variable1:String?
        var variable2:String?
        var variable3:String?
        var variable4:String?
        var variable5:String?
        var method:Int
        var administrativeCharge:String
        
        enum CodingKeys: String, CodingKey {
            case resultCode, amount, paymentToken, paymentId, paidOn, variable1, variable2, variable3, variable4, variable5, method, administrativeCharge
        }
    }
}

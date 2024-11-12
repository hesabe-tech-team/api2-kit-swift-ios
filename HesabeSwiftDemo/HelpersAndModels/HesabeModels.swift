//
//  HesabeModels.swift
//  HesabeSwiftDemo
//
//  Created by Mohammed Salman on 29/03/20.
//  Copyright © 2020 Mohammed Salman. All rights reserved.
//

import Foundation

struct PaymentRequest: Codable {
    
    private var merchantCode: String
    private var responseUrl: String
    private var failureUrl: String
    private var paymentType: String
    private var version: String = "2.0"
    var amount: String
    var orderReferenceNumber: String?
    var variable1: String?
    var variable2: String?
    var variable3: String?
    var variable4: String?
    var variable5: String?
    var subscription: String?

    
    init?(amount: String, payment type: String = "0") {
        
        guard !MERCHANT_CODE.isEmpty && MERCHANT_CODE.rangeOfCharacter(from: CharacterSet.decimalDigits.inverted) == nil else
        {
            debugPrint("Hesabe Error: Failed to set merchant code.")
            return nil
        }
        
        guard !type.isEmpty && type.rangeOfCharacter(from: CharacterSet.decimalDigits.inverted) == nil && type >= "0" && type <= "2" else {
            debugPrint("Hesabe Error: Failed to set payment type")
            return nil
        }
        
        guard !amount.isEmpty && amount >= "0" else {
            debugPrint("Hesabe Error: The payment amount is not valid")
            return nil
        }
        
        self.merchantCode = MERCHANT_CODE
        self.responseUrl  = RESPONSE_URL
        self.failureUrl  = FAILURE_URL
        self.amount = amount
        self.paymentType  = type
        self.subscription = "0"
    }
    
    enum CodingKeys: String, CodingKey {
        case merchantCode, amount, responseUrl, orderReferenceNumber, variable1, variable2, variable3, variable4, variable5, paymentType, version, failureUrl, subscription
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
        var resultCode: String
        var amount: String // Since "amount" seems to be a numeric value in the JSON, it should be a Float
        var paymentToken: String
        var paymentId: String?  // Optional because it may not always be present
        var paidOn: String? // Optional, based on the JSON
        var orderReferenceNumber: String?
        var variable1: String? // Optional to handle `null` values in JSON
        var variable2: String? // Optional to handle `null` values in JSON
        var variable3: String? // Optional to handle `null` values in JSON
        var variable4: String? // Optional to handle `null` values in JSON
        var variable5: String? // Optional to handle `null` values in JSON
        var method: Int // Method seems to always be a number, so it's not optional
        var administrativeCharge: String // A String to hold the administrative charge value

        var customer: Customer? // Optional, as `customer` can be null

        enum CodingKeys: String, CodingKey {
            case resultCode, amount, paymentToken, paymentId, paidOn, orderReferenceNumber, variable1, variable2, variable3, variable4, variable5, method, administrativeCharge, customer
        }

        struct Customer: Codable {
            var name: String?
            var email: String?
            var mobile: String?
            var nameOnCard: String?
            var cardNumber: String?
            var cardType: String?

            enum CodingKeys: String, CodingKey {
                case name = "Name"
                case email = "Email"
                case mobile = "Mobile"
                case nameOnCard = "NameOnCard"
                case cardNumber = "CardNumber"
                case cardType = "CardType"
            }
        }
    }
}

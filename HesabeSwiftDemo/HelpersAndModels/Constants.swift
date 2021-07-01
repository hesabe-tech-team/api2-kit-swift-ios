//
//  Constants.swift
//  HesabeSwiftDemo
//
//  Created by Mohammed Salman on 15/04/20.
//  Copyright © 2020 Mohammed Salman. All rights reserved.
//

import Foundation

// Get these URL from `https://developer.hesabe.com/` -> Environments
// Replace `https://sandbox.hesabe.com` with Test URL or Production URL.
let CHECKOUT_URL = "https://sandbox.hesabe.com/checkout"
let PAYMENT_URL = "https://sandbox.hesabe.com/payment?data="

// Get below values from Merchant Panel, Profile section
let ACCESS_CODE = "c333729b-d060-4b74-a49d-7686a8353481"
let MERCHANT_KEY = "PkW64zMe5NVdrlPVNnjo2Jy9nOb7v1Xg"
let MERCHANT_IV = "5NVdrlPVNnjo2Jy9"
let MERCHANT_CODE = "842217"

// This URL are defined by you to get the response from Payment Gateway
let RESPONSE_URL = "http://success.hesbstaging.com"
let FAILURE_URL = "http://failure.hesbstaging.com"

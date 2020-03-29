//
//  HesabeGatewayVC.swift
//  HesabeSwiftDemo
//
//  Created by Mohammed Salman on 29/03/20.
//  Copyright © 2020 Mohammed Salman. All rights reserved.
//

import UIKit
import WebKit
import Alamofire

protocol HesabeGatewayVCDelegate: class {
    func updatePaymentStaus(data: PaymentResponse)
}

class HesabeGatewayVC: UIViewController {
    
    weak var delegate: HesabeGatewayVCDelegate?
    
    /// The base URL used for Payment Gateway
    let hesabeURL = "http://api.hesbstck.com";
    
    /// The URL to used to fetch payment token
    var checkoutUrl: String {
        return hesabeURL + "/checkout"
    }
    
    /// The URL to used fto load payment Gateway
    var paymentUrl: String {
        return hesabeURL + "/payment?data="
    }
    
    /// The header  to pass while accessing payment token
    let headers = ["accessCode": "2a3789f5-edd1-416d-a472-4357794d6a8c"]
    
    /// Get these values from Merchant Panel, Profile section
    /// - Parameters:
    ///   - key: Merchant Key
    ///   - iv: Merchant IV
    let AES = HesabeCrypt(key: "OGzgrmqyDEnlALQRNvzPv8NJ4BwWM019", iv: "DEnlALQRNvzPv8NJ")
    
    /// The view to load the payment gateway
    var webView: WKWebView!
    
    /// The property stores the data to be sent while requesting paayment token
    var paymentData: PaymentData?

    override func viewDidLoad() {
        super.viewDidLoad()
        self.checkoutRequest()
    }
    
    /// Create request for Payment Token
    func checkoutRequest() {
        let requestDataJson = try! JSONEncoder().encode(paymentData)
        guard let encryptedData = AES?.encrypt(data: requestDataJson) else { return }
        let parameters = ["data": encryptedData]
        Alamofire.request(URL(string:checkoutUrl)!, method: .post, parameters: parameters,headers: headers).responseString { response in
            switch response.result {
            case .success:
                guard let result = response.result.value else { return }
                self.checkoutResponse(response: result)
            case .failure(let error):
                print(error)
            }
        }
    }
    
    /// Update Payment Token response
    func checkoutResponse(response encrypted: String) {
        let decryptResponse = AES?.decryptedResponse(data: encrypted)
        guard let jsonData = decryptResponse?.data(using: .utf8) else { return }
        let result = try? JSONDecoder().decode(PaymentToken.self, from: jsonData)
        if result?.code == 200 {
            let token = result?.response.data
            self.redirectToPayment(with: token!)
        }
    }
    
    /// Redirect to payment gateway to complete the process
    func redirectToPayment(with token: String) {
        let url = paymentUrl + token
        let request = URLRequest(url: URL(string: url)!)
        self.webView.load(request);
    }

}

extension HesabeGatewayVC: WKNavigationDelegate, WKUIDelegate {
    
    override func loadView() {
        super.loadView()
        let webConfiguration = WKWebViewConfiguration()
        webView = WKWebView(frame: .zero, configuration: webConfiguration)
        webView.navigationDelegate = self
        webView.uiDelegate = self
        view = webView
    }
    
    /**
     The gateway URL are handle here. On load on every new url in gateway, the method is being called and passes through some checks.
     The `decisionHandler()` allows the method to proceed further or stop processing.
     Here, If the response URL being called then we are extraction the data from that url and proceed to update response.
     */
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        
        guard let url = navigationAction.request.url else {
            decisionHandler(.allow)
            return
        }
        
        /// Process the response after the transaction is complete. To use this method, make sure your SuccessUrl or FailureUrl points to this method in which you'll receive a "data" paramas a GET request. Then you can process it accordingly.
        if url.absoluteString.contains("\(paymentData!.responseUrl)/?data") {
            decisionHandler(.cancel)
            let result = url.absoluteString.components(separatedBy: "=")
            self.paymentResponse(response: result[1])
        } else {
            print(url)
            decisionHandler(.allow)
        }
    }
    
    /// Update Payment response after completion
    func paymentResponse(response encrypted: String) {
        let decryptResponse = AES?.decryptedResponse(data: encrypted)
        guard let jsonData = decryptResponse?.data(using: .utf8) else { return }
        let result = (try? JSONDecoder().decode(PaymentResponse.self, from: jsonData))!
        self.dismiss(animated: true) {
            self.delegate?.updatePaymentStaus(data: result)
        }
    }
}

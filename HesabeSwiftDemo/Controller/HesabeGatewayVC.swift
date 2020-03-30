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

class HesabeGatewayVC: UIViewController {
    
    weak var delegate: HesabeGatewayVCDelegate?
    
    /// The base URL used for Payment Gateway
    let hesabeURL = "http://api.hesbstck.com";
    
    /// The header  to pass while accessing payment token
    let accessCode = "2a3789f5-edd1-416d-a472-4357794d6a8c"
    let merchantKey = "OGzgrmqyDEnlALQRNvzPv8NJ4BwWM019"
    let merchantIV = "DEnlALQRNvzPv8NJ"
    
    private var headers: HTTPHeaders {
        return ["accessCode": self.accessCode]
    }
    
    private var AES: HesabeCrypt! {
        return HesabeCrypt(key: self.merchantKey, iv: self.merchantIV)
    }
    
    /// The URL to used to fetch payment token
    private var checkoutUrl: String {
        return hesabeURL + "/checkout"
    }
    
    /// The URL to used to load payment Gateway
    private var paymentUrl: String {
        return hesabeURL + "/payment?data="
    }
    
    /// The view to load the payment gateway
    var webView: WKWebView!
    
    /// The property stores the data to be sent while requesting payment token
    /// for eg - var paymentRequest = PaymentRequest(code: "1351719857300", responseUrl: "http://api.hesbstaging.com", failureUrl: "http://api.hesbstaging.com")
    var paymentRequest: PaymentRequest?

    override func viewDidLoad() {
        super.viewDidLoad()
        self.checkout(paymentRequest: paymentRequest!)
    }
}

// MARK: - Function
extension HesabeGatewayVC {
    
    /// Create request for Payment Token
    func checkout(paymentRequest: PaymentRequest) {
        let paymentRequestJson = try! JSONEncoder().encode(paymentRequest)
        guard let paymentRequestEncrypted = AES?.encrypt(data: paymentRequestJson) else { return }
        let parameters = ["data": paymentRequestEncrypted]
        Alamofire.request(URL(string:checkoutUrl)!, method: .post, parameters: parameters, headers: headers).responseString { response in
            switch response.result {
            case .success:
                guard let encryptedResponse = response.result.value else { return }
                self.checkoutResponse(response: encryptedResponse)
            case .failure(let error):
                print(error)
            }
        }
    }
    
    /// Update Payment Token response
    func checkoutResponse(response encryptedResponse: String) {
        let decryptedResponse = AES?.decrypt(data: encryptedResponse)
        guard let responseJson = decryptedResponse?.data(using: .utf8) else { return }
        let result = try? JSONDecoder().decode(PaymentToken.self, from: responseJson)
        if result?.code == 200, let token = result?.response.data {
            self.redirectToPayment(with: token)
        }
    }
    
    /// Redirect to payment gateway to complete the process
    func redirectToPayment(with token: String) {
        let url = paymentUrl + token
        let request = URLRequest(url: URL(string: url)!)
        self.webView.load(request);
    }
    
}

// MARK: - WKWebView
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
     The gateway URL are handled here. On load of every new url in gateway, the method is being called.
     The `decisionHandler()` allows the method to proceed further or stop processing.
     Here, If the response URL is being called, the process is being stopped to extract the data from that url and proceed to update response.
     */
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        
        guard let url = navigationAction.request.url else {
            decisionHandler(.allow)
            return
        }
        
        /// Process the response after the transaction is complete. To use this method, make sure your SuccessUrl or FailureUrl points to this method in which you'll receive a "data" paramas a GET request. Then you can process it accordingly.
        if url.absoluteString.contains("\(paymentRequest!.responseUrl)/?data") {
            decisionHandler(.cancel)
            let urlComponents = url.absoluteString.components(separatedBy: "=")
            let encryptedResponse = urlComponents[1]
            self.paymentResponse(response: encryptedResponse)
        } else {
            print(url)
            decisionHandler(.allow)
        }
    }
    
    /// Updates Payment response post completion
    func paymentResponse(response encryptedResponse: String) {
        let decryptedResponse = AES?.decrypt(data: encryptedResponse)
        guard let responseJson = decryptedResponse?.data(using: .utf8) else { return }
        let paymentRespone = (try? JSONDecoder().decode(PaymentResponse.self, from: responseJson))!
        self.dismiss(animated: true) {
            self.delegate?.paymentRespone(response: paymentRespone)
        }
    }
}

// MARK: - Protocol and Delegate
protocol HesabeGatewayVCDelegate: class {
    func paymentRespone(response: PaymentResponse)
}

extension ViewController: HesabeGatewayVCDelegate {
    func paymentRespone(response paymentResponse: PaymentResponse) {
        self.hesabeResponse(paymentResponse: paymentResponse)
    }
}

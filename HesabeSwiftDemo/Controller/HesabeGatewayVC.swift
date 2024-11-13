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
    private var AES = HesabeCrypt()
    
    private var headers: HTTPHeaders {
        return ["accessCode": ACCESS_CODE]
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
        print("Checkout started")
        
        // Encode the paymentRequest to JSON
        let paymentRequestJson: Data
        do {
            paymentRequestJson = try JSONEncoder().encode(paymentRequest)
            print("Payment Request JSON: \(String(data: paymentRequestJson, encoding: .utf8) ?? "Invalid JSON")")
        } catch {
            print("Failed to encode payment request: \(error.localizedDescription)")
            return
        }
        
        // Encrypt the paymentRequest JSON
        guard let paymentRequestEncrypted = AES?.encrypt(data: paymentRequestJson) else {
            print("Encryption failed")
            return
        }
        
        // Log the encrypted data (be cautious with logging sensitive information)
        print("Encrypted Payment Request: \(paymentRequestEncrypted)")

        // Set up parameters for the request
        let parameters = ["data": paymentRequestEncrypted]
        print("Request Parameters: \(parameters)")

        // Make the Alamofire request
        Alamofire.request(URL(string: CHECKOUT_URL)!, method: .post, parameters: parameters, headers: headers).responseString { response in
            
            // Log the full response for debugging
            print("Response received:")
            print("Response Status Code: \(response.response?.statusCode ?? -1)") // Log status code
            print("Response Headers: \(String(describing: response.response?.allHeaderFields))") // Log headers
            
            switch response.result {
            case .success:
                // Log the successful response
                guard let encryptedResponse = response.result.value else {
                    print("No response data received")
                    return
                }
                
                // Log the encrypted response (this will need decryption to be useful)
                print("Encrypted Response: \(encryptedResponse)")
                
                // Handle the response by passing it to checkoutResponse
                self.checkoutResponse(response: encryptedResponse)
                
            case .failure(let error):
                // Log the error details
                print("Request failed with error: \(error.localizedDescription)")
                
                // Check if the error is an AFError (Alamofire specific error)
                if let afError = error as? AFError {
                    // Log the underlying error if available
                    if let underlyingError = afError.underlyingError {
                        print("Underlying error: \(underlyingError.localizedDescription)")
                    }
                } else if let nsError = error as? NSError {
                    // Log the underlying error in case it's an NSError
                    if let underlyingError = nsError.userInfo[NSUnderlyingErrorKey] as? NSError {
                        print("Underlying error: \(underlyingError.localizedDescription)")
                    }
                } else {
                    // If the error is not an AFError or NSError, just log it
                    print("Unknown error type: \(error)")
                }
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
        let url = PAYMENT_URL + token
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
        if url.absoluteString.contains("\(RESPONSE_URL)/?data") || url.absoluteString.contains("\(FAILURE_URL)/?data") {
            decisionHandler(.cancel)
            let urlComponents = url.absoluteString.components(separatedBy: "=")
            let encryptedResponse = urlComponents[1]
            self.paymentResponse(response: encryptedResponse)
        } else {
            print(url)
            decisionHandler(.allow)
        }
    }
    
    func paymentResponse(response encryptedResponse: String) {
        // Decrypt the response safely
        guard let decryptedResponse = AES?.decrypt(data: encryptedResponse) else {
            print("Decryption failed.")
            return
        }
        
        // Clean the decrypted response string (optional, depending on your JSON format)
        var cleanResponse = decryptedResponse
        cleanResponse = cleanResponse.replacingOccurrences(of: ":null", with: ":\"null\"")
        cleanResponse = cleanResponse.replacingOccurrences(of: "null,", with: "\"null\",")
        
        // Convert the cleaned response to Data
        guard let responseData = cleanResponse.data(using: .utf8) else {
            return
        }

        do {
            // Attempt to decode the response into a PaymentResponse object
            let paymentResponse = try JSONDecoder().decode(PaymentResponse.self, from: responseData)
            
            // Successfully decoded the payment response
            self.dismiss(animated: true) {
                self.delegate?.paymentResponse(response: paymentResponse)
            }

        } catch {
            // Handle error during decoding
            
            // If the first decoding attempt failed, try cleaning the string further and decoding again
            let newResponseString = decryptedResponse.components(separatedBy: "}}").first?.appending("}}")
            guard let newResponseData = newResponseString?.data(using: .utf8) else {
                return
            }
            
            do {
                let paymentResponse = try JSONDecoder().decode(PaymentResponse.self, from: newResponseData)
                self.dismiss(animated: true) {
                    self.delegate?.paymentResponse(response: paymentResponse)
                }
            } catch {
                // If the second attempt also fails, log the error and return
                print("Error decoding response on second attempt: \(error)")
            }
        }
    }





}

// MARK: - Protocol and Delegate
protocol HesabeGatewayVCDelegate: class {
    func paymentResponse(response: PaymentResponse)
}

extension ViewController: HesabeGatewayVCDelegate {
    func paymentResponse(response paymentResponse: PaymentResponse) {
        self.hesabeResponse(paymentResponse: paymentResponse)
    }
}

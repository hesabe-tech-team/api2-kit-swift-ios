//
//  ViewController.swift
//  HesabeSwiftDemo
//
//  Created by Mohammed Salman on 29/03/20.
//  Copyright © 2020 Mohammed Salman. All rights reserved.
//

import UIKit

class ViewController: UIViewController {
    
    @IBOutlet weak var statusLabel: UILabel!

    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view.
    }
    
    @IBAction func payClick(_ sender: UIButton) {
        statusLabel.text = ""
        
        // Determine if it's a subscription request or an individual payment.
        let isSubscription = true // Change this based on your business logic.
        
        // Individual payment request
        var paymentRequest: PaymentRequest?
        
        if isSubscription {
            // Subscription request - pass necessary subscription details
            paymentRequest = PaymentRequest(amount: "6.62", paymentType: "0", isSubscription: true, name: "John Doe", mobileNumber: "98076104", email: "bcelebi@hesabe.com")
        } else {
            // Individual payment request - no subscription, no extra details
            paymentRequest = PaymentRequest(amount: "6.62", paymentType: "0", isSubscription: false) // Pass `isSubscription` here
        }
        
        
        // Use guard to safely unwrap the paymentRequest and make it mutable
        guard var validPaymentRequest = paymentRequest else {
            debugPrint("Failed to create a valid PaymentRequest")
            return
        }
        
        // Now you can modify the properties of validPaymentRequest
        validPaymentRequest.orderReferenceNumber = "12XXXXXX" // Optional field for both types of requests
        
        // Present the payment gateway with the prepared payment request
        self.presentHesabeGateway(paymentRequest: validPaymentRequest)
        }

    
    func presentHesabeGateway(paymentRequest: PaymentRequest) {
        let vc = HesabeGatewayVC()
        vc.paymentRequest = paymentRequest
        vc.modalPresentationStyle = .overFullScreen // to avoid dafault popover presentation
        vc.delegate = self
        self.present(vc, animated: true, completion: nil)
    }
    
    func hesabeResponse(paymentResponse: PaymentResponse) {
        let data = paymentResponse.response
        statusLabel.text = data.resultCode + " - #" + data.orderReferenceNumber!
    }
    
}

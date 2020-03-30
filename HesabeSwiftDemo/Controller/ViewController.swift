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
        var paymentRequest = PaymentRequest(code: "1351719857300",
                                      responseUrl: "http://api.hesbstaging.com",
                                      failureUrl: "http://api.hesbstaging.com")
        paymentRequest?.amount = "7.5"
        self.presentHesabeGateway(paymentRequest: paymentRequest!)
    }
    
    func presentHesabeGateway(paymentRequest: PaymentRequest) {
        let vc = HesabeGatewayVC()
        vc.paymentRequest = paymentRequest
        vc.modalPresentationStyle = .overFullScreen // to avoid dafault popover presentation
        vc.delegate = self
        self.present(vc, animated: true, completion: nil)
    }
    
    func hesabeResponse(paymentResponse: PaymentResponse) {
        statusLabel.text = paymentResponse.response.resultCode
    }
    
}

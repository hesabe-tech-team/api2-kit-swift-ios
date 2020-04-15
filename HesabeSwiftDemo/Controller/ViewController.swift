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
        var paymentRequest = PaymentRequest(amount: "1")
        paymentRequest?.orderReferenceNumber = "12XXXXXX" // optional
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
        let data = paymentResponse.response
        statusLabel.text = data.resultCode + " - #" + data.orderReferenceNumber!
    }
    
}

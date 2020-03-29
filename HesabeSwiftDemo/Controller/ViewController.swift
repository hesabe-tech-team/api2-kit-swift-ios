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
        let vc = HesabeGatewayVC()
        var paymentData = PaymentData(code: "1351719857300",
                                      responseUrl: "http://api.hesbstaging.com",
                                      failureUrl: "http://api.hesbstaging.com")
        paymentData?.amount = "7.5"
        vc.paymentData = paymentData
        vc.modalPresentationStyle = .fullScreen
        vc.delegate = self
        present(vc, animated: true, completion: nil)
    }
    
}

extension ViewController: HesabeGatewayVCDelegate {
    
    func updatePaymentStaus(data: PaymentResponse) {
        statusLabel.text = data.response.resultCode
    }
}

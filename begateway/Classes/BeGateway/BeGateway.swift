//
//  BegetWayApi.swift
//  begateway.framework
//
//  Created by admin on 29.10.2021.
//

import UIKit
import PassKit

public enum FieldsToValidate {
    case cardNumber, cardHolder, cardDate, cardCVC
}

public class BeGateway {
    public static let instance = BeGateway()

    public var options: BeGatewayOptions?
    public var request: BeGatewayRequest?
    var completionHandler: ((BeGatewayCard) -> Void)?
    var failureHandler:((String) -> Void)?

    var paymentSuccess: (() -> Void)?
    var paymentFailed:((String) -> Void)?

    private var amount : String?
    private var currencyCode: String?
    var delegatePK : ApplePaymentModule?
    var paymentToken = ""

    var delegate: PaymentBasicProtocol?

    private var storeCards: Array<StoreCard> = []

    public var cards: Array<BeGatewayCard> {
        get {
            return StoreCard.to(items: self.storeCards)
        }
    }

    private init() {
        //
    }

    public func setup(with settings: BeGatewayOptions) -> BeGateway {
        self.options = settings
        self.loadSavedCard()
        return self
    }

    public func setup(pubKey: String) -> BeGateway {
        self.options = BeGatewayOptions(clientPubKey: pubKey)
        self.loadSavedCard()
        return self
    }

    private func loadSavedCard() {
        if let items = StoreCard.readFromUserDefaults(){
            self.storeCards = items
        }

        //        StoreCard.clearUserDefaults()
    }

    public func paymentWasSucceded() {
        if delegate != nil {
            delegate?.processPaymentSuccess()
        }
    }

    public func paymentFinishedWith(error : String) {
        if delegate != nil {
            delegate?.outError(error: error)
        }
    }

    private func initRequest(request: BeGatewayRequest, completionHandler: ((BeGatewayCard) -> Void)?, failureHandler:((String) -> Void)?)
    {
        self.request = request
        self.completionHandler = completionHandler
        self.failureHandler = failureHandler

        guard let _ = self.options else {
            fatalError("Error - Options is nll")
        }

        guard let _ = self.request else {
            fatalError("Error - Request is nll")
        }
    }

    public func removeAllCards() {
        _ = StoreCard.clearUserDefaults()
        self.storeCards.removeAll()
    }

    public func paymentError() {

    }

    public func pay(rootController: UIViewController, request: BeGatewayRequest, completionHandler: ((BeGatewayCard) -> Void)?, failureHandler:((String) -> Void)?) {

        self.initRequest(request: request, completionHandler: completionHandler, failureHandler: failureHandler)

        let bundle = Bundle(for: type(of: self))

        //                for test
        //        let controller = WebViewController.loadFromNib(bundle)
        //        controller.url = "https://demo-gateway.begateway.com/process/114115979-61f987f750"
        //        rootController.present(controller, animated: true, completion: nil)
        //        return

        //        for test
        //        let controller = InitialViewController.loadFromNib(bundle)
        //        self.presentController(controller, rootController: rootController, sizes: [.fullscreen])
        //        return

        //        clear all saved cards for test
        //        self.removeAllCards()

        if let card = StoreCard.getActiveCard() {
            print("Active card is \(card.first1)**********\(card.last4)")

            let controller = InitialViewController.loadFromNib(bundle)
            self.presentController(controller, rootController: rootController, sizes: [.fixed(300.0)])
        } else {
            let controller = PaymentViewController.loadFromNib(bundle)
            self.presentController(controller, rootController: rootController, sizes: [.fullscreen])
        }
    }



    private func presentController(_ controller: UIViewController, rootController: UIViewController, sizes: [SheetSize] = [.intrinsic]) {
        let options = SheetOptions(
            useInlineMode: false
        )

        let sheetController = SheetViewController(
            controller: UINavigationController(rootViewController: controller),
            sizes: sizes,
            options: options)

        //            sheetController.animateIn(to: rootController.view, in: rootController)
        rootController.present(sheetController, animated: true, completion: nil)
    }

    public func getStatus(token : String, completionHandler: ((CheckoutsResponseStatusV2?) -> Void)?, failureHandler:((String) -> Void)?) {
        if let options = BeGateway.instance.options {
            BeGatewaySourceApi(options: options).checkStatus(token: token, completionHandler: { result in
                completionHandler?(result)
            }, failureHandler: failureHandler)
        }
    }


    public func getToken(request: BeGatewayRequest, completionHandler: ((String) -> Void)?, failureHandler:((String) -> Void)?) {
        if let options = BeGateway.instance.options, !request.isEmpty {
            let apiInstance = BeGatewaySourceApi(options: options)
            apiInstance.checkout(request: request, completionHandler: { result in
                if let token = result?.checkout?.token {
                    print("Token for operation is \"\(token)\"")
                    self.paymentToken = token
                    completionHandler?(token)
                    apiInstance.checkStatus(token: token, completionHandler: { statusResult in
                        if let company = statusResult?.checkout?.company?.name {
                            UserDefaults.standard.set(company, forKey: "CompanyName")
                        } else {
                            print("There is no information about the company")
                        }
                    }, failureHandler: { error in
                        print("Error checking status: \(error)")
                    })

                } else {
                    failureHandler?("Error: token is null")
                }
            }, failureHandler: { error in
                failureHandler?(error)
            })
        }
    }


    private func stringFromType(type : PKPaymentMethodType) -> String {
        switch type {
        case .unknown:
            return "unknown"
        case .debit:
            return "debit"
        case .credit:
            return "credit"
        case .prepaid:
            return "prepaid"
        case .store:
            return "store"
        case .eMoney:
            return "eMoney"
        @unknown default:
            return "unknown"
        }
    }
    private func requestFromAppleToken(appleToken : PKPayment) -> RequestPaymentAppleV2? {

        let paymentData = appleToken.token.paymentData
        let paymentMethodS = appleToken.token.paymentMethod

        let paymentMethod = PaymentMethod(displayName: paymentMethodS.displayName ?? "unknown", network: paymentMethodS.network?.rawValue ?? "unknown network", type: stringFromType(type: paymentMethodS.type))
        
        if let paymentDataStruct = getPaymentFromData(data: paymentData) {
            let token = AppleTokenRequestV2(paymentData: paymentDataStruct, paymentMethod: paymentMethod, transactionIdentifier: appleToken.token.transactionIdentifier)
            return RequestPaymentAppleV2(request: RequestPaymentAppleV2Request(token: token), token: self.paymentToken, contract: false)
        }

        return nil


    }

    private func getPaymentFromData(data: Data) -> PaymentData?{
        do{
          let packet = try JSONDecoder().decode(PaymentData.self, from: data)
          return packet
        }catch let error as NSError{
            print(String(describing: error))
            print(error.localizedDescription)
        }

        return nil
    }

    func appleTokenReceived(payment: PKPayment, completionHandler: @escaping((ResponsePaymentV2Response) -> Void), failureHandler: @escaping((String) -> Void)) {
        if let requestApple = requestFromAppleToken(appleToken: payment) {
            if let options = BeGateway.instance.options {
                BeGatewaySourceApi.init(options: options).sendApplePayment(uploadDataModel: requestApple) { result in
                    if let response = result?.response {
                        completionHandler(response)
                    } else {
                        failureHandler("ApplePay payment error")
                    }
                } failureHandler: { errorString in
                    failureHandler(errorString)
                }
            }
        }
    }

    public func payWithAppleByToken(token : String, rootController: UIViewController, completionHandler: (() -> Void)?, failureHandler:((String) -> Void)?) {
        self.getStatus(token: token) { info in
            self.paymentToken = info?.checkout?.token ?? ""
            guard let rAmount = info?.checkout?.order?.amount, let rCurrency = info?.checkout?.order?.currency else { return }
            
            let amount = CurrencyHelper.getAmount(amount: rAmount, currency: rCurrency)
            self.applePayRequest(checkoutResponse: info!, currencyCode: rCurrency, amount: amount, rootController: rootController, completionHandler: completionHandler, failureHandler: failureHandler)
        } failureHandler: { stringError in
            if (failureHandler != nil) {
                failureHandler!(stringError)
            }
        }
    }
    
    public func payWithApplePay(requestBE : BeGatewayRequest, rootController: UIViewController, completionHandler: (() -> Void)?, failureHandler:((String) -> Void)?) {
        self.getToken(request: requestBE) { token in
            self.payWithAppleByToken(token: token, rootController: rootController, completionHandler: completionHandler, failureHandler: failureHandler)
        } failureHandler: { error in
            if (failureHandler != nil) {
                failureHandler!(error)
            }
        }
    }
 
    public func payWithAppleBy(appleToken : PKPayment, paymentToken : String, completionHandler: (() -> Void)?, failureHandler:((String) -> Void)?) {
        self.paymentToken = paymentToken

        if let requestApple = requestFromAppleToken(appleToken: appleToken) {
            if let options = BeGateway.instance.options {
                BeGatewaySourceApi.init(options: options).sendApplePayment(uploadDataModel: requestApple) { response in
                    let status: String = response?.response?.status ?? "failed"

                    if status == "successful" {
                        if let compl = completionHandler {
                            compl()
                        }
                    } else {
                        let message = response?.response?.message ?? "Error during payment"
                        if let failure = failureHandler {
                            failure(message)
                        }
                    }
                } failureHandler: { errorString in
                    if let failure = failureHandler {
                        failure(errorString)
                    }
                }
            }
        } else {
            if let failure = failureHandler {
                failure("error converting data")
            }
        }
    }

    private func applePayRequest(checkoutResponse: CheckoutsResponseStatusV2, currencyCode : String, amount : NSDecimalNumber, rootController: UIViewController, completionHandler: (() -> Void)?, failureHandler:((String) -> Void)?) {
      
        let requestPK = PKPaymentRequest()
        let description = checkoutResponse.checkout?.order?.orderDescription
        requestPK.merchantIdentifier = ""
        if self.options != nil {
            if self.options?.merchantID != nil {
                requestPK.merchantIdentifier = self.options?.merchantID ?? ""
            }
        }

        if #available(iOS 12.0, *) {
            requestPK.supportedNetworks = [.visa, .masterCard, .amex, .maestro, .discover, .chinaUnionPay]
        } else if #available(iOS 14.5, *) {
            requestPK.supportedNetworks = [.visa, .masterCard, .mir, .amex, .maestro, .discover, .chinaUnionPay, .JCB]
        } else if #available(iOS 11.0, *) {
            requestPK.supportedNetworks = [.visa, .masterCard, .amex, .discover, .chinaUnionPay]
        }
        
        requestPK.merchantCapabilities = .capability3DS
        requestPK.countryCode = "BY"
        requestPK.currencyCode = currencyCode
        requestPK.paymentSummaryItems = [PKPaymentSummaryItem(label: description ?? "", amount: amount)]

        if self.delegatePK == nil {
            self.delegatePK = ApplePaymentModule(link: self)
        }

        if let controller = PKPaymentAuthorizationViewController(paymentRequest: requestPK) {
            controller.delegate = self.delegatePK
            rootController.present(controller, animated: true, completion: nil)

        }
       
        guard let delegate = delegatePK else { return }
        delegate.failureCallback = { stringError in
            if (failureHandler != nil) {
                failureHandler!(stringError)
            }

        }
        delegate.successCallback = {
            if (completionHandler != nil) {
                completionHandler!()
            }
        }
    }

    public func payByCardTokenInBackground(rootController: UIViewController, request: BeGatewayRequest, completionHandler: ((BeGatewayCard) -> Void)?, failureHandler:((String) -> Void)?) {

        self.initRequest(request: request, completionHandler: completionHandler, failureHandler: failureHandler)

        let controller = PayByCardTokenViewController()
        controller.cardToken = request.card?.cardToken
        controller.payWithCardToken()
    }

    public func payByToken(token: String, card : BeGatewayRequestCard, rootController: UIViewController, completionHandler: ((BeGatewayCard) -> Void)?, failureHandler:((String) -> Void)?) {

        let request = BeGatewayRequest.init(amount: 1.0, currency: "U", requestDescription: "", trackingID: "", card: card) //Payment token validation
        self.initRequest(request: request, completionHandler: completionHandler, failureHandler: failureHandler)

        let bundle = Bundle(for: type(of: self))

        let controller = PaymentViewController.loadFromNib(bundle)
        controller.tokenForRequest = token
        self.presentController(controller, rootController: rootController, sizes: [.fullscreen])
    }

    public func fieldsToValidate() -> [FieldsToValidate] {
        var array : [FieldsToValidate] = []

        if self.options?.isToogleCardNumber == false {
            array.append(FieldsToValidate.cardNumber)
        }

        if self.options?.isToogleCVC == false {
            array.append(FieldsToValidate.cardCVC)
        }

        if self.options?.isToogleExpiryDate == false {
            array.append(FieldsToValidate.cardDate)
        }

        if self.options?.isToogleCardHolderName == false {
            array.append(FieldsToValidate.cardHolder)
        }

        return array
    }
}

extension BeGateway {
    public static func test() {
        print("Test from API")
    }
}

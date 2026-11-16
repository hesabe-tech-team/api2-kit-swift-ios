# Hesabe iOS SDK: KNET, cards and Apple Pay with no keys in the app

The SDK takes one payment session from your server and does the rest: it shows the
payment, follows the customer through KNET, 3-D Secure or Apple Pay, asks Hesabe how the
payment ended, and returns that to your app.

Your merchant keys stay on your server. The app holds the session's `data` string, which
opens one payment and cannot create another. The SDK does no encryption.

`Sources/` is the Swift package. [`web/apple-pay.html`](web/apple-pay.html) is the page
behind the Apple Pay button.

Status, November 2026: every Hesabe call the SDK makes was run against the sandbox. The
package is compiled and unit tested by GitHub Actions. It has not been run on a device
yet.

## What you need before starting

1. A Hesabe merchant account with its keys from Merchant Panel, Profile, Merchant Keys:
   merchant code, access code, secret key (32 characters), IV key (16 characters). They go
   on your server, never in the app.
2. A server endpoint that calls Hesabe's Checkout API. Step 1 describes it.
3. For the Apple Pay button: Apple Pay enabled on your account (email support@hesabe.com)
   and the address of the hosted button page.
4. Xcode 16 or later. The SDK supports iOS 15 and later.

## Step 1. Create the session on your server

Your server sends the usual Checkout API request, encrypted with your keys, to
`POST https://api.hesabe.com/checkout` (`https://sandbox.hesabe.com/checkout` for the
sandbox). This is the payload before encryption:

```json
{
  "merchantCode": "842217",
  "amount": "1.000",
  "currency": "KWD",
  "paymentType": 0,
  "orderReferenceNumber": "ORDER-1001",
  "responseUrl": "https://example.com/hesabe/return",
  "failureUrl": "https://example.com/hesabe/return",
  "version": "2.0"
}
```

- `paymentType` is `0`. The app chooses the method, so one session serves every method.
- `responseUrl` and `failureUrl` are the same two URLs for every payment. Nothing has to
  exist at them: the SDK stops the navigation before it loads.
- `amount` is a string with exactly three decimals.

Hesabe answers with a `token` and `response.data`. Return `response.data` to the app. It
is a hex string of about 190 characters.

Check: open `https://sandbox.hesabe.com/payment?data=` followed by that string in a
browser. Hesabe's payment page appears.

## Step 2. Add the package

In Xcode, choose File, Add Package Dependencies, enter this repository's URL, and add the
`HesabeUI` product to your app target.

Check: `import HesabeUI` compiles.

## Step 3. Configure the SDK

```swift
import HesabeUI

let configuration = HesabeConfiguration(
    environment: .sandbox,
    returnURLs: ReturnURLs(URL(string: "https://example.com/hesabe/return")!),
    merchantDisplayName: "Example Store"
)
```

`returnURLs` are the `responseUrl` and `failureUrl` from Step 1. The SDK ends the payment
when Hesabe navigates to either.

## Step 4. Present the checkout

```swift
let session = try HesabeSession(data: dataFromYourServer)
let sheet = HesabeCheckoutSheet(configuration: configuration)

switch await sheet.present(session, methods: [.knet, .card], from: self) {
case .paid(let transaction):
    showReceipt(transaction.orderReference)
case .failed, .canceled, .notStarted:
    offerToPayAgain()
case .pending, .unconfirmed:
    showOrderIsBeingChecked()
}
```

In SwiftUI:

```swift
.hesabeCheckout(session: $session, configuration: configuration, methods: [.knet, .card]) { result in
    handle(result)
}
```

`methods` decides what the customer sees:

| `methods` | The customer sees |
|---|---|
| one method, `[.knet]` | That method's page directly. |
| several, `[.knet, .card, .amex]` | A native list of those enabled on your account, then the chosen method's page. |
| none | Hesabe's own page with every enabled method. |

A payment method is Hesabe's payment type id: `.knet` is 1, `.card` is 2 (MPGS), `.amex`
is 7, `.googlePay` is 16. Any other id works as `PaymentMethod(rawValue: 18)`.

Check: on the sandbox, pay with KNET test card `8888880000000001`, expiry `09/30`, PIN
`1234`. The sheet shows "Payment complete" and returns `.paid`.

### The six results

| Result | Meaning | What the app does |
|---|---|---|
| `.paid` | Hesabe confirms the payment. | Show the receipt. |
| `.failed` | Hesabe recorded the attempt and it did not go through. | Offer to pay again with a new session. |
| `.pending` | Hesabe has the payment and has not settled it. | Do not charge again. Check later. |
| `.canceled` | The customer closed the payment and Hesabe has no transaction. | Nothing was charged. |
| `.unconfirmed` | The flow ended and Hesabe could not be asked. | The customer may have been charged. Check from your server. |
| `.notStarted` | The session was refused or the page never loaded. | Nothing was charged. Create a new session. |

## Step 5. Add the Apple Pay button

```swift
HesabeApplePayButton(
    session: session,
    configuration: configuration,
    method: .applePayKNETDebit,
    type: .buy,
    style: .automatic,
    cornerRadius: 8
) { result in
    handle(result)
}
```

Set `applePayPageURL` in the configuration to the hosted button page:

```swift
configuration.applePayPageURL = URL(string: "https://example.com/apple-pay.html")!
```

- `method` is the Apple Pay payment type on your account: `11` KNET debit, `13` KNET
  international, `9` MPGS.
- `type` is the wording (`plain`, `buy`, `checkout`, `book`, `subscribe`, `donate`,
  `order`). `style` is `automatic`, `black`, `white` or `whiteOutline`.
- Closing the Apple Pay sheet is not a result. The button stays ready.

### Why the button is a web view

Apple Pay through Hesabe starts from a web page on a domain registered with Apple, and
WebKit refuses to start it from a page inside the app. So the button is WebKit's own
Apple Pay button, drawn by [`web/apple-pay.html`](web/apple-pay.html) in a web view the
size of the button. The page is the same file for every payment and holds no keys. The
payment's settings travel in the URL fragment, which browsers never send to a server.

An earlier version of this page took a production payment in September 2026, from a
merchant's own domain and with an embedded session. It has not been run with a plain
session, or from a page hosted by Hesabe, yet.

## Step 6. Settle payments the app never saw finish

A customer can pay in a banking app and never come back, and iOS can close the app during
3-D Secure. The SDK writes each session token down before the payment page opens. Call
this once at launch:

```swift
let settled = await HesabeClient(environment: .sandbox).recoverPayments()
```

It returns the payments that have since been paid or failed.

## How the SDK works

| File | What it does |
|---|---|
| `Hesabe/HesabeSession.swift` | Holds the session's `data`. Unwraps an embedded session. |
| `Hesabe/HesabeClient.swift` | The three keyless calls: session details, payment page address, outcome. |
| `HesabeUI/HesabeCheckoutSheet.swift` | Reads the session, shows the method list and the page, settles the result. |
| `HesabeUI/PaymentWebViewController.swift` | Hesabe's page in a web view: bank app hand-off, 3-D Secure popups, return detection. |
| `HesabeUI/HesabeApplePayButton.swift` | The Apple Pay button and its loading, processing and retry states. |
| `Hesabe/HesabePendingPayments.swift` | The tokens of payments in flight, kept across launches. |

The Hesabe calls, as run on the sandbox in November 2026:

| Call | Answer |
|---|---|
| `GET api/checkout-details?data=<data>` | The session's token, amount, currency and enabled payment types. |
| `GET payment?data=<data>` | Hesabe's page with every method. |
| `GET payment?data=<data>&paymentType=1` | A redirect straight to KNET. |
| `GET api/transaction/enquire/<token>` | The transaction once one exists; 404 "Transaction not found" before. |

### Things that matter

- The result comes from `api/transaction/enquire`, never from the redirect. Reaching
  `responseUrl` proves nothing, and the Apple Pay sheet says "Done" before Hesabe answers.
- The result is for the screen. Release the order from your server, which asks Hesabe's
  Transaction Enquiry itself or acts on the webhook by looking the payment up.
- A session is single use. After any result except `.notStarted`, the next attempt needs
  a new session.
- Send `response.data` to the app, not `token`. The payment page does not open with the
  token.
- The SDK injects no script into its web views. WebKit turns Apple Pay off in a web view
  the app has injected script into.
- Amounts are shown as Hesabe reports them, never computed on the device.

## If something goes wrong

- `.notStarted(.rejected("Failed to decrypt data parameter"))`: the string is not
  `response.data`, the session was already used, or it was created on the other
  environment.
- `.notStarted(.configuration("none of the requested payment methods is enabled..."))`:
  the methods you passed are not enabled on the account. Ask Hesabe to enable them.
- The sheet stays on your own return page: `returnURLs` does not match the `responseUrl`
  your server sent.
- `.unconfirmed(.noTransaction)` after the customer returned: Hesabe had not recorded the
  payment within ten seconds. Look it up from your server.
- The Apple Pay button shows "Try again": the message beside it says why. The usual
  causes are a missing `applePayPageURL` and an Apple Pay type that is not enabled.
- KNET opens and nothing happens after the bank app: the bank app did not return. The
  payment is settled by Step 6 at the next launch.

## Licence

MIT

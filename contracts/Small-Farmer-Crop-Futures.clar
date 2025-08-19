(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-not-found (err u101))
(define-constant err-unauthorized (err u102))
(define-constant err-insufficient-funds (err u103))
(define-constant err-contract-expired (err u104))
(define-constant err-already-delivered (err u105))
(define-constant err-invalid-quantity (err u106))
(define-constant err-invalid-price (err u107))
(define-constant err-already-registered (err u108))
(define-constant err-not-registered (err u109))

(define-data-var contract-id-nonce uint u0)
(define-data-var platform-fee-rate uint u250)

(define-map farmers
    principal
    {
        registered: bool,
        farm-name: (string-utf8 100),
        location: (string-utf8 100),
        reputation-score: uint,
    }
)

(define-map crop-contracts
    uint
    {
        farmer: principal,
        buyer: (optional principal),
        crop-type: (string-utf8 50),
        quantity: uint,
        price-per-unit: uint,
        total-amount: uint,
        delivery-date: uint,
        created-at: uint,
        status: (string-ascii 20),
        escrow-amount: uint,
        quality-grade: (string-ascii 10),
    }
)

(define-map contract-payments
    uint
    {
        total-paid: uint,
        farmer-paid: uint,
        platform-fee: uint,
        escrow-released: bool,
    }
)

(define-public (register-farmer
        (farm-name (string-utf8 100))
        (location (string-utf8 100))
    )
    (let (
            (farmer tx-sender)
            (existing-farmer (map-get? farmers farmer))
        )
        (asserts! (is-none existing-farmer) err-already-registered)
        (ok (map-set farmers farmer {
            registered: true,
            farm-name: farm-name,
            location: location,
            reputation-score: u100,
        }))
    )
)

(define-public (create-crop-contract
        (crop-type (string-utf8 50))
        (quantity uint)
        (price-per-unit uint)
        (delivery-date uint)
        (quality-grade (string-ascii 10))
    )
    (let (
            (farmer tx-sender)
            (contract-id (+ (var-get contract-id-nonce) u1))
            (total-amount (* quantity price-per-unit))
            (current-height stacks-block-height)
            (farmer-data (unwrap! (map-get? farmers farmer) err-not-registered))
        )
        (asserts! (get registered farmer-data) err-not-registered)
        (asserts! (> quantity u0) err-invalid-quantity)
        (asserts! (> price-per-unit u0) err-invalid-price)
        (asserts! (> delivery-date current-height) err-contract-expired)

        (var-set contract-id-nonce contract-id)

        (map-set crop-contracts contract-id {
            farmer: farmer,
            buyer: none,
            crop-type: crop-type,
            quantity: quantity,
            price-per-unit: price-per-unit,
            total-amount: total-amount,
            delivery-date: delivery-date,
            created-at: current-height,
            status: "open",
            escrow-amount: u0,
            quality-grade: quality-grade,
        })

        (map-set contract-payments contract-id {
            total-paid: u0,
            farmer-paid: u0,
            platform-fee: u0,
            escrow-released: false,
        })

        (ok contract-id)
    )
)

(define-public (purchase-contract (contract-id uint))
    (let (
            (buyer tx-sender)
            (contract-data (unwrap! (map-get? crop-contracts contract-id) err-not-found))
            (payment-data (unwrap! (map-get? contract-payments contract-id) err-not-found))
            (total-amount (get total-amount contract-data))
            (platform-fee (/ (* total-amount (var-get platform-fee-rate)) u10000))
            (farmer-payment (- total-amount platform-fee))
        )
        (asserts! (is-eq (get status contract-data) "open") err-unauthorized)
        (asserts! (is-none (get buyer contract-data)) err-unauthorized)
        (asserts! (> stacks-block-height (get created-at contract-data))
            err-contract-expired
        )

        (try! (stx-transfer? total-amount buyer (as-contract tx-sender)))

        (map-set crop-contracts contract-id
            (merge contract-data {
                buyer: (some buyer),
                status: "purchased",
                escrow-amount: total-amount,
            })
        )

        (map-set contract-payments contract-id
            (merge payment-data {
                total-paid: total-amount,
                platform-fee: platform-fee,
            })
        )

        (ok true)
    )
)

(define-public (confirm-delivery (contract-id uint))
    (let (
            (contract-data (unwrap! (map-get? crop-contracts contract-id) err-not-found))
            (payment-data (unwrap! (map-get? contract-payments contract-id) err-not-found))
            (buyer (unwrap! (get buyer contract-data) err-unauthorized))
            (farmer (get farmer contract-data))
            (platform-fee (get platform-fee payment-data))
            (farmer-payment (- (get total-paid payment-data) platform-fee))
        )
        (asserts! (is-eq tx-sender buyer) err-unauthorized)
        (asserts! (is-eq (get status contract-data) "purchased") err-unauthorized)
        (asserts! (not (get escrow-released payment-data)) err-already-delivered)

        (try! (as-contract (stx-transfer? farmer-payment tx-sender farmer)))
        (try! (as-contract (stx-transfer? platform-fee tx-sender contract-owner)))

        (map-set crop-contracts contract-id
            (merge contract-data { status: "delivered" })
        )

        (map-set contract-payments contract-id
            (merge payment-data {
                farmer-paid: farmer-payment,
                escrow-released: true,
            })
        )

        (try! (update-farmer-reputation farmer true))

        (ok true)
    )
)

(define-public (dispute-delivery (contract-id uint))
    (let (
            (contract-data (unwrap! (map-get? crop-contracts contract-id) err-not-found))
            (buyer (unwrap! (get buyer contract-data) err-unauthorized))
        )
        (asserts! (is-eq tx-sender buyer) err-unauthorized)
        (asserts! (is-eq (get status contract-data) "purchased") err-unauthorized)
        (asserts!
            (< stacks-block-height (+ (get delivery-date contract-data) u144))
            err-contract-expired
        )

        (map-set crop-contracts contract-id
            (merge contract-data { status: "disputed" })
        )

        (ok true)
    )
)

(define-public (resolve-dispute
        (contract-id uint)
        (favor-farmer bool)
    )
    (let (
            (contract-data (unwrap! (map-get? crop-contracts contract-id) err-not-found))
            (payment-data (unwrap! (map-get? contract-payments contract-id) err-not-found))
            (buyer (unwrap! (get buyer contract-data) err-unauthorized))
            (farmer (get farmer contract-data))
            (total-amount (get total-paid payment-data))
            (platform-fee (get platform-fee payment-data))
            (farmer-payment (- total-amount platform-fee))
        )
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (asserts! (is-eq (get status contract-data) "disputed") err-unauthorized)
        (asserts! (not (get escrow-released payment-data)) err-already-delivered)

        (if favor-farmer
            (begin
                (try! (as-contract (stx-transfer? farmer-payment tx-sender farmer)))
                (try! (as-contract (stx-transfer? platform-fee tx-sender contract-owner)))
                (try! (update-farmer-reputation farmer true))
                (map-set crop-contracts contract-id
                    (merge contract-data { status: "resolved-farmer" })
                )
            )
            (begin
                (try! (as-contract (stx-transfer? total-amount tx-sender buyer)))
                (try! (update-farmer-reputation farmer false))
                (map-set crop-contracts contract-id
                    (merge contract-data { status: "resolved-buyer" })
                )
            )
        )

        (map-set contract-payments contract-id
            (merge payment-data { escrow-released: true })
        )

        (ok true)
    )
)

(define-public (cancel-contract (contract-id uint))
    (let (
            (contract-data (unwrap! (map-get? crop-contracts contract-id) err-not-found))
            (farmer (get farmer contract-data))
        )
        (asserts! (is-eq tx-sender farmer) err-unauthorized)
        (asserts! (is-eq (get status contract-data) "open") err-unauthorized)
        (asserts! (is-none (get buyer contract-data)) err-unauthorized)

        (map-set crop-contracts contract-id
            (merge contract-data { status: "cancelled" })
        )

        (ok true)
    )
)

(define-public (emergency-refund (contract-id uint))
    (let (
            (contract-data (unwrap! (map-get? crop-contracts contract-id) err-not-found))
            (payment-data (unwrap! (map-get? contract-payments contract-id) err-not-found))
            (buyer (unwrap! (get buyer contract-data) err-unauthorized))
            (total-amount (get total-paid payment-data))
        )
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (asserts!
            (> stacks-block-height (+ (get delivery-date contract-data) u1008))
            err-contract-expired
        )
        (asserts! (not (get escrow-released payment-data)) err-already-delivered)

        (try! (as-contract (stx-transfer? total-amount tx-sender buyer)))

        (map-set crop-contracts contract-id
            (merge contract-data { status: "refunded" })
        )

        (map-set contract-payments contract-id
            (merge payment-data { escrow-released: true })
        )

        (try! (update-farmer-reputation (get farmer contract-data) false))

        (ok true)
    )
)

(define-private (update-farmer-reputation
        (farmer principal)
        (positive bool)
    )
    (let (
            (farmer-data (unwrap! (map-get? farmers farmer) err-not-found))
            (current-score (get reputation-score farmer-data))
            (new-score (if positive
                (if (< current-score u200)
                    (+ current-score u10)
                    current-score
                )
                (if (> current-score u10)
                    (- current-score u20)
                    u0
                )
            ))
        )
        (ok (map-set farmers farmer
            (merge farmer-data { reputation-score: new-score })
        ))
    )
)

(define-read-only (get-contract (contract-id uint))
    (map-get? crop-contracts contract-id)
)

(define-read-only (get-farmer-info (farmer principal))
    (map-get? farmers farmer)
)

(define-read-only (get-contract-payment (contract-id uint))
    (map-get? contract-payments contract-id)
)

(define-read-only (get-platform-fee-rate)
    (var-get platform-fee-rate)
)

(define-read-only (get-contract-count)
    (var-get contract-id-nonce)
)

(define-public (set-platform-fee-rate (new-rate uint))
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (asserts! (<= new-rate u1000) err-invalid-price)
        (var-set platform-fee-rate new-rate)
        (ok true)
    )
)

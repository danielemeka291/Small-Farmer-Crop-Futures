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
(define-constant err-batch-limit-exceeded (err u110))
(define-constant err-batch-empty (err u111))
(define-constant err-invalid-coverage (err u112))
(define-constant err-insurance-expired (err u113))
(define-constant err-already-claimed (err u114))
(define-constant err-no-qualifying-event (err u115))

(define-data-var contract-id-nonce uint u0)
(define-data-var platform-fee-rate uint u250)
(define-data-var max-batch-size uint u10)
(define-data-var insurance-policy-nonce uint u0)
(define-data-var base-premium-rate uint u500)
(define-data-var max-coverage-amount uint u10000000)

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

(define-map weather-insurance-policies
    uint
    {
        farmer: principal,
        coverage-amount: uint,
        premium-paid: uint,
        coverage-type: (string-ascii 20),
        threshold-value: uint,
        start-date: uint,
        end-date: uint,
        created-at: uint,
        status: (string-ascii 15),
        payout-claimed: bool,
    }
)

(define-map weather-events
    uint
    {
        event-date: uint,
        event-type: (string-ascii 20),
        severity-value: uint,
        verified: bool,
        recorded-by: principal,
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

(define-public (create-batch-contracts (contracts-data (list 10
    {
    crop-type: (string-utf8 50),
    quantity: uint,
    price-per-unit: uint,
    delivery-date: uint,
    quality-grade: (string-ascii 10),
})))
    (let (
            (farmer tx-sender)
            (contracts-count (len contracts-data))
            (farmer-data (unwrap! (map-get? farmers farmer) err-not-registered))
        )
        (asserts! (get registered farmer-data) err-not-registered)
        (asserts! (> contracts-count u0) err-batch-empty)
        (asserts! (<= contracts-count (var-get max-batch-size))
            err-batch-limit-exceeded
        )

        (ok (map create-single-contract-internal contracts-data))
    )
)

(define-private (create-single-contract-internal (contract-data {
    crop-type: (string-utf8 50),
    quantity: uint,
    price-per-unit: uint,
    delivery-date: uint,
    quality-grade: (string-ascii 10),
}))
    (let (
            (farmer tx-sender)
            (contract-id (+ (var-get contract-id-nonce) u1))
            (quantity (get quantity contract-data))
            (price-per-unit (get price-per-unit contract-data))
            (total-amount (* quantity price-per-unit))
            (current-height stacks-block-height)
            (delivery-date (get delivery-date contract-data))
        )
        (asserts! (> quantity u0) contract-id)
        (asserts! (> price-per-unit u0) contract-id)
        (asserts! (> delivery-date current-height) contract-id)

        (var-set contract-id-nonce contract-id)

        (map-set crop-contracts contract-id {
            farmer: farmer,
            buyer: none,
            crop-type: (get crop-type contract-data),
            quantity: quantity,
            price-per-unit: price-per-unit,
            total-amount: total-amount,
            delivery-date: delivery-date,
            created-at: current-height,
            status: "open",
            escrow-amount: u0,
            quality-grade: (get quality-grade contract-data),
        })

        (map-set contract-payments contract-id {
            total-paid: u0,
            farmer-paid: u0,
            platform-fee: u0,
            escrow-released: false,
        })

        contract-id
    )
)

(define-public (purchase-batch-contracts (contract-ids (list 10 uint)))
    (let (
            (buyer tx-sender)
            (contracts-count (len contract-ids))
        )
        (asserts! (> contracts-count u0) err-batch-empty)
        (asserts! (<= contracts-count (var-get max-batch-size))
            err-batch-limit-exceeded
        )

        (ok (map purchase-single-contract-internal contract-ids))
    )
)

(define-private (purchase-single-contract-internal (contract-id uint))
    (let (
            (buyer tx-sender)
            (contract-data (default-to {
                farmer: tx-sender,
                buyer: none,
                crop-type: u"",
                quantity: u0,
                price-per-unit: u0,
                total-amount: u0,
                delivery-date: u0,
                created-at: u0,
                status: "invalid",
                escrow-amount: u0,
                quality-grade: "",
            }
                (map-get? crop-contracts contract-id)
            ))
            (payment-data (default-to {
                total-paid: u0,
                farmer-paid: u0,
                platform-fee: u0,
                escrow-released: false,
            }
                (map-get? contract-payments contract-id)
            ))
            (total-amount (get total-amount contract-data))
            (platform-fee (/ (* total-amount (var-get platform-fee-rate)) u10000))
        )
        (if (and
                (is-eq (get status contract-data) "open")
                (is-none (get buyer contract-data))
                (> stacks-block-height (get created-at contract-data))
                (is-ok (stx-transfer? total-amount buyer (as-contract tx-sender)))
            )
            (begin
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

                contract-id
            )
            u0
        )
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

(define-read-only (get-max-batch-size)
    (var-get max-batch-size)
)

(define-read-only (get-farmer-active-policies-count (farmer principal))
    (let (
            (policy-count (var-get insurance-policy-nonce))
            (policy-range (list u1 u2 u3 u4 u5 u6 u7 u8 u9 u10))
        )
        (get count (fold check-farmer-policy-count policy-range { farmer: farmer, count: u0, max-id: policy-count }))
    )
)

(define-private (check-farmer-policy-count (policy-id uint) (acc { farmer: principal, count: uint, max-id: uint }))
    (let (
            (farmer (get farmer acc))
            (current-count (get count acc))
            (max-id (get max-id acc))
        )
        (if (<= policy-id max-id)
            (match (map-get? weather-insurance-policies policy-id)
                policy-data 
                    (if (and 
                            (is-eq farmer (get farmer policy-data))
                            (is-eq (get status policy-data) "active")
                        )
                        { farmer: farmer, count: (+ current-count u1), max-id: max-id }
                        acc
                    )
                acc
            )
            acc
        )
    )
)

(define-public (set-platform-fee-rate (new-rate uint))
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (asserts! (<= new-rate u1000) err-invalid-price)
        (var-set platform-fee-rate new-rate)
        (ok true)
    )
)

(define-public (set-max-batch-size (new-size uint))
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (asserts! (and (>= new-size u1) (<= new-size u20)) err-invalid-quantity)
        (var-set max-batch-size new-size)
        (ok true)
    )
)

;; Weather Insurance Module Functions

(define-public (purchase-weather-insurance
        (coverage-amount uint)
        (coverage-type (string-ascii 20))
        (threshold-value uint)
        (coverage-duration uint)
    )
    (let (
            (farmer tx-sender)
            (policy-id (+ (var-get insurance-policy-nonce) u1))
            (premium-amount (/ (* coverage-amount (var-get base-premium-rate)) u10000))
            (current-height stacks-block-height)
            (end-date (+ current-height coverage-duration))
            (farmer-data (unwrap! (map-get? farmers farmer) err-not-registered))
        )
        (asserts! (get registered farmer-data) err-not-registered)
        (asserts! (> coverage-amount u0) err-invalid-coverage)
        (asserts! (<= coverage-amount (var-get max-coverage-amount)) err-invalid-coverage)
        (asserts! (> coverage-duration u144) err-invalid-coverage)
        (asserts! (> threshold-value u0) err-invalid-coverage)

        (try! (stx-transfer? premium-amount farmer (as-contract tx-sender)))

        (var-set insurance-policy-nonce policy-id)

        (map-set weather-insurance-policies policy-id {
            farmer: farmer,
            coverage-amount: coverage-amount,
            premium-paid: premium-amount,
            coverage-type: coverage-type,
            threshold-value: threshold-value,
            start-date: current-height,
            end-date: end-date,
            created-at: current-height,
            status: "active",
            payout-claimed: false,
        })

        (ok policy-id)
    )
)

(define-public (record-weather-event
        (event-type (string-ascii 20))
        (severity-value uint)
    )
    (let (
            (event-id (+ (var-get insurance-policy-nonce) u1000000))
            (current-height stacks-block-height)
        )
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (asserts! (> severity-value u0) err-invalid-coverage)

        (map-set weather-events event-id {
            event-date: current-height,
            event-type: event-type,
            severity-value: severity-value,
            verified: true,
            recorded-by: tx-sender,
        })

        (ok event-id)
    )
)

(define-public (claim-weather-insurance
        (policy-id uint)
        (weather-event-id uint)
    )
    (let (
            (policy-data (unwrap! (map-get? weather-insurance-policies policy-id) err-not-found))
            (event-data (unwrap! (map-get? weather-events weather-event-id) err-not-found))
            (farmer (get farmer policy-data))
            (coverage-amount (get coverage-amount policy-data))
            (threshold (get threshold-value policy-data))
            (event-severity (get severity-value event-data))
            (current-height stacks-block-height)
        )
        (asserts! (is-eq tx-sender farmer) err-unauthorized)
        (asserts! (is-eq (get status policy-data) "active") err-insurance-expired)
        (asserts! (not (get payout-claimed policy-data)) err-already-claimed)
        (asserts! (>= current-height (get start-date policy-data)) err-insurance-expired)
        (asserts! (<= current-height (get end-date policy-data)) err-insurance-expired)
        (asserts! (get verified event-data) err-no-qualifying-event)
        (asserts! (>= event-severity threshold) err-no-qualifying-event)
        (asserts! (is-eq (get coverage-type policy-data) (get event-type event-data)) err-no-qualifying-event)
        (asserts!
            (and
                (>= (get event-date event-data) (get start-date policy-data))
                (<= (get event-date event-data) (get end-date policy-data))
            )
            err-no-qualifying-event
        )

        (let (
                (calculated-ratio (* (/ event-severity threshold) u10000))
                (payout-ratio (if (> calculated-ratio u10000) u10000 calculated-ratio))
                (payout-amount (/ (* coverage-amount payout-ratio) u10000))
            )
            (try! (as-contract (stx-transfer? payout-amount tx-sender farmer)))

            (map-set weather-insurance-policies policy-id
                (merge policy-data {
                    status: "claimed",
                    payout-claimed: true,
                })
            )

            (ok payout-amount)
        )
    )
)

(define-public (cancel-weather-insurance (policy-id uint))
    (let (
            (policy-data (unwrap! (map-get? weather-insurance-policies policy-id) err-not-found))
            (farmer (get farmer policy-data))
            (premium-paid (get premium-paid policy-data))
            (current-height stacks-block-height)
            (cancellation-fee (/ premium-paid u10))
            (refund-amount (- premium-paid cancellation-fee))
        )
        (asserts! (is-eq tx-sender farmer) err-unauthorized)
        (asserts! (is-eq (get status policy-data) "active") err-insurance-expired)
        (asserts! (not (get payout-claimed policy-data)) err-already-claimed)
        (asserts! (< current-height (+ (get start-date policy-data) u72)) err-insurance-expired)

        (try! (as-contract (stx-transfer? refund-amount tx-sender farmer)))
        (try! (as-contract (stx-transfer? cancellation-fee tx-sender contract-owner)))

        (map-set weather-insurance-policies policy-id
            (merge policy-data { status: "cancelled" })
        )

        (ok refund-amount)
    )
)

;; Weather Insurance Read-Only Functions

(define-read-only (get-weather-insurance-policy (policy-id uint))
    (map-get? weather-insurance-policies policy-id)
)

(define-read-only (get-weather-event (event-id uint))
    (map-get? weather-events event-id)
)

(define-read-only (get-insurance-policy-count)
    (var-get insurance-policy-nonce)
)

(define-read-only (get-base-premium-rate)
    (var-get base-premium-rate)
)

(define-read-only (get-max-coverage-amount)
    (var-get max-coverage-amount)
)

(define-read-only (calculate-premium (coverage-amount uint))
    (/ (* coverage-amount (var-get base-premium-rate)) u10000)
)

;; Weather Insurance Admin Functions

(define-public (set-base-premium-rate (new-rate uint))
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (asserts! (and (>= new-rate u100) (<= new-rate u2000)) err-invalid-price)
        (var-set base-premium-rate new-rate)
        (ok true)
    )
)

(define-public (set-max-coverage-amount (new-max uint))
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (asserts! (> new-max u0) err-invalid-coverage)
        (var-set max-coverage-amount new-max)
        (ok true)
    )
)

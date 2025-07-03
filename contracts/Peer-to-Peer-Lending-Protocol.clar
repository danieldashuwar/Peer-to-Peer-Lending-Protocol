(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-INVALID-AMOUNT (err u101))
(define-constant ERR-LOAN-NOT-FOUND (err u102))
(define-constant ERR-LOAN-ALREADY-FUNDED (err u103))
(define-constant ERR-INSUFFICIENT-COLLATERAL (err u104))
(define-constant ERR-LOAN-NOT-ACTIVE (err u105))
(define-constant ERR-REPAYMENT-FAILED (err u106))
(define-constant ERR-UNSUPPORTED-ASSET (err u107))
(define-constant ERR-COLLATERAL-TRANSFER-FAILED (err u108))

(define-data-var next-loan-id uint u1)
(define-data-var contract-owner principal tx-sender)

(define-map loans 
  { loan-id: uint }
  {
    borrower: principal,
    amount: uint,
    collateral-amount: uint,
    collateral-asset: principal,
    duration: uint,
    interest-rate: uint,
    lender: (optional principal),
    status: (string-ascii 20),
    start-height: uint,
    repaid-amount: uint
  }
)

(define-map borrower-stats
  principal
  {
    loans-taken: uint,
    loans-repaid: uint,
    reputation-score: uint
  }
)

(define-map supported-assets
  principal
  {
    enabled: bool,
    collateral-ratio: uint
  }
)

(define-map asset-vault
  { loan-id: uint }
  {
    asset: principal,
    amount: uint
  }
)

(define-trait sip-010-trait
  (
    (transfer (uint principal principal (optional (buff 34))) (response bool uint))
    (get-name () (response (string-ascii 32) uint))
    (get-symbol () (response (string-ascii 32) uint))
    (get-decimals () (response uint uint))
    (get-balance (principal) (response uint uint))
    (get-total-supply () (response uint uint))
    (get-token-uri () (response (optional (string-utf8 256)) uint))
  )
)

(define-public (add-supported-asset (asset-contract principal) (collateral-ratio uint))
  (begin
    (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
    (map-set supported-assets asset-contract {
      enabled: true,
      collateral-ratio: collateral-ratio
    })
    (ok true)
  )
)

(define-public (create-loan-request-with-asset 
  (amount uint) 
  (collateral-amount uint) 
  (collateral-asset <sip-010-trait>) 
  (duration uint) 
  (interest-rate uint))
  (let (
    (loan-id (var-get next-loan-id))
    (asset-principal (contract-of collateral-asset))
    (asset-info (unwrap! (map-get? supported-assets asset-principal) ERR-UNSUPPORTED-ASSET))
  )
    (asserts! (get enabled asset-info) ERR-UNSUPPORTED-ASSET)
    (asserts! (> collateral-amount u0) ERR-INSUFFICIENT-COLLATERAL)
    
    (try! (contract-call? collateral-asset transfer collateral-amount tx-sender (as-contract tx-sender) none))
    
    (map-set loans
      { loan-id: loan-id }
      {
        borrower: tx-sender,
        amount: amount,
        collateral-amount: collateral-amount,
        collateral-asset: asset-principal,
        duration: duration,
        interest-rate: interest-rate,
        lender: none,
        status: "PENDING",
        start-height: u0,
        repaid-amount: u0
      }
    )
    
    (map-set asset-vault 
      { loan-id: loan-id }
      {
        asset: asset-principal,
        amount: collateral-amount
      }
    )
    
    (var-set next-loan-id (+ loan-id u1))
    (ok loan-id)
  )
)

(define-public (fund-loan (loan-id uint))
  (let (
    (loan (unwrap! (map-get? loans { loan-id: loan-id }) ERR-LOAN-NOT-FOUND))
    (amount (get amount loan))
  )
    (asserts! (is-eq (get status loan) "PENDING") ERR-LOAN-ALREADY-FUNDED)
    (try! (stx-transfer? amount tx-sender (get borrower loan)))
    (map-set loans
      { loan-id: loan-id }
      (merge loan {
        lender: (some tx-sender),
        status: "ACTIVE",
        start-height: stacks-block-height
      })
    )
    (ok true)
  )
)

(define-public (repay-loan-with-asset (loan-id uint) (repayment-amount uint) (collateral-asset <sip-010-trait>))
  (let (
    (loan (unwrap! (map-get? loans { loan-id: loan-id }) ERR-LOAN-NOT-FOUND))
    (total-owed (+ (get amount loan) (/ (* (get amount loan) (get interest-rate loan)) u100)))
    (vault-info (unwrap! (map-get? asset-vault { loan-id: loan-id }) ERR-LOAN-NOT-FOUND))
  )
    (asserts! (is-eq (get status loan) "ACTIVE") ERR-LOAN-NOT-ACTIVE)
    (asserts! (is-eq (get borrower loan) tx-sender) ERR-NOT-AUTHORIZED)
    (try! (stx-transfer? repayment-amount tx-sender (unwrap! (get lender loan) ERR-LOAN-NOT-FOUND)))
    
    (let ((new-repaid-amount (+ (get repaid-amount loan) repayment-amount)))
      (if (>= new-repaid-amount total-owed)
        (begin
          (try! (as-contract (contract-call? 
            collateral-asset
            transfer 
            (get amount vault-info) 
            tx-sender 
            (get borrower loan) 
            none)))
          (map-delete asset-vault { loan-id: loan-id })
          (map-set loans
            { loan-id: loan-id }
            (merge loan {
              repaid-amount: new-repaid-amount,
              status: "COMPLETED"
            })
          )
        )
        (map-set loans
          { loan-id: loan-id }
          (merge loan { repaid-amount: new-repaid-amount })
        )
      )
      (ok true)
    )
  )
)

(define-public (create-loan-request (amount uint) (collateral uint) (duration uint) (interest-rate uint))
  (let ((loan-id (var-get next-loan-id)))
    (map-set loans
      { loan-id: loan-id }
      {
        borrower: tx-sender,
        amount: amount,
        collateral-amount: collateral,
        collateral-asset: 'ST1PQHQKV0RJXZFY1DGX8MNSNYVE3VGZJSRTPGZGM.stx-token,
        duration: duration,
        interest-rate: interest-rate,
        lender: none,
        status: "PENDING",
        start-height: u0,
        repaid-amount: u0
      }
    )
    (var-set next-loan-id (+ loan-id u1))
    (ok loan-id)
  )
)

(define-public (repay-loan (loan-id uint) (repayment-amount uint))
  (let (
    (loan (unwrap! (map-get? loans { loan-id: loan-id }) ERR-LOAN-NOT-FOUND))
    (total-owed (+ (get amount loan) (/ (* (get amount loan) (get interest-rate loan)) u100)))
  )
    (asserts! (is-eq (get status loan) "ACTIVE") ERR-LOAN-NOT-ACTIVE)
    (asserts! (is-eq (get borrower loan) tx-sender) ERR-NOT-AUTHORIZED)
    (try! (stx-transfer? repayment-amount tx-sender (unwrap! (get lender loan) ERR-LOAN-NOT-FOUND)))
    
    (let ((new-repaid-amount (+ (get repaid-amount loan) repayment-amount)))
      (map-set loans
        { loan-id: loan-id }
        (merge loan {
          repaid-amount: new-repaid-amount,
          status: (if (>= new-repaid-amount total-owed) "COMPLETED" "ACTIVE")
        })
      )
      (ok true)
    )
  )
)

(define-read-only (get-loan (loan-id uint))
  (ok (unwrap! (map-get? loans { loan-id: loan-id }) ERR-LOAN-NOT-FOUND))
)

(define-read-only (get-borrower-stats (borrower principal))
  (default-to
    { loans-taken: u0, loans-repaid: u0, reputation-score: u0 }
    (map-get? borrower-stats borrower)
  )
)

(define-read-only (get-supported-asset (asset principal))
  (map-get? supported-assets asset)
)

(define-read-only (get-asset-vault-info (loan-id uint))
  (map-get? asset-vault { loan-id: loan-id })
)

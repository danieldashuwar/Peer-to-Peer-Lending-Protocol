(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-INVALID-AMOUNT (err u101))
(define-constant ERR-LOAN-NOT-FOUND (err u102))
(define-constant ERR-LOAN-ALREADY-FUNDED (err u103))
(define-constant ERR-INSUFFICIENT-COLLATERAL (err u104))
(define-constant ERR-LOAN-NOT-ACTIVE (err u105))
(define-constant ERR-REPAYMENT-FAILED (err u106))

(define-data-var next-loan-id uint u1)

(define-map loans 
  { loan-id: uint }
  {
    borrower: principal,
    amount: uint,
    collateral: uint,
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

(define-public (create-loan-request (amount uint) (collateral uint) (duration uint) (interest-rate uint))
  (let ((loan-id (var-get next-loan-id)))
    (map-set loans
      { loan-id: loan-id }
      {
        borrower: tx-sender,
        amount: amount,
        collateral: collateral,
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

(define-public (repay-loan (loan-id uint) (repayment-amount uint))
  (let (
    (loan (unwrap! (map-get? loans { loan-id: loan-id }) ERR-LOAN-NOT-FOUND))
    (total-owed (+ (get amount loan) (* (get amount loan) (get interest-rate loan) u1)))
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

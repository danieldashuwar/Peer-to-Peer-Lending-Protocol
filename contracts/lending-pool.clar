;; Peer-to-Peer Lending Pool Contract
;; A decentralized lending platform enabling direct peer-to-peer loans

;; Error constants
(define-constant ERR-UNAUTHORIZED (err u100))
(define-constant ERR-LOAN-NOT-FOUND (err u101))
(define-constant ERR-INVALID-AMOUNT (err u102))
(define-constant ERR-LOAN-ALREADY-FUNDED (err u103))
(define-constant ERR-LOAN-NOT-ACTIVE (err u104))
(define-constant ERR-PAYMENT-INSUFFICIENT (err u105))
(define-constant ERR-LOAN-OVERDUE (err u106))
(define-constant ERR-INVALID-DURATION (err u107))
(define-constant ERR-INVALID-INTEREST (err u108))

;; Data variables
(define-data-var loan-counter uint u0)
(define-data-var contract-owner principal tx-sender)

;; Loan status constants
(define-constant STATUS-REQUESTED u1)
(define-constant STATUS-FUNDED u2)
(define-constant STATUS-ACTIVE u3)
(define-constant STATUS-REPAID u4)
(define-constant STATUS-DEFAULTED u5)

;; Loan structure
(define-map loans
  uint
  {
    borrower: principal,
    lender: (optional principal),
    amount: uint,
    interest-rate: uint, ;; Basis points (e.g., 500 = 5%)
    duration-blocks: uint,
    collateral: uint,
    status: uint,
    funded-at: (optional uint),
    due-at: (optional uint),
    repaid-amount: uint,
    created-at: uint
  }
)

;; User balances for collateral
(define-map user-balances principal uint)

;; Loan events
(define-map loan-payments
  uint
  {
    total-paid: uint,
    payment-count: uint,
    last-payment: (optional uint)
  }
)

;; Read-only functions

(define-read-only (get-loan (loan-id uint))
  (map-get? loans loan-id)
)

(define-read-only (get-user-balance (user principal))
  (default-to u0 (map-get? user-balances user))
)

(define-read-only (get-loan-counter)
  (var-get loan-counter)
)

(define-read-only (calculate-total-repayment (amount uint) (interest-rate uint))
  (+ amount (/ (* amount interest-rate) u10000))
)

(define-read-only (is-loan-overdue (loan-id uint))
  (match (map-get? loans loan-id)
    loan-data
    (match (get due-at loan-data)
      due-block
      (and (> block-height due-block) (is-eq (get status loan-data) STATUS-ACTIVE))
      false
    )
    false
  )
)

;; Public functions

;; Deposit collateral
(define-public (deposit-collateral (amount uint))
  (begin
    (asserts! (> amount u0) ERR-INVALID-AMOUNT)
    ;; In a real implementation, this would interact with SIP-10 tokens
    ;; For now, we simulate collateral deposits
    (map-set user-balances tx-sender 
      (+ (get-user-balance tx-sender) amount))
    (ok amount)
  )
)

;; Create a loan request
(define-public (request-loan (amount uint) (interest-rate uint) (duration-blocks uint) (collateral-amount uint))
  (let ((loan-id (+ (var-get loan-counter) u1)))
    (asserts! (> amount u0) ERR-INVALID-AMOUNT)
    (asserts! (<= interest-rate u2000) ERR-INVALID-INTEREST) ;; Max 20% interest
    (asserts! (and (>= duration-blocks u144) (<= duration-blocks u52560)) ERR-INVALID-DURATION) ;; 1 day to 1 year
    (asserts! (>= (get-user-balance tx-sender) collateral-amount) ERR-INVALID-AMOUNT)
    
    ;; Lock collateral
    (map-set user-balances tx-sender 
      (- (get-user-balance tx-sender) collateral-amount))
    
    ;; Create loan
    (map-set loans loan-id
      {
        borrower: tx-sender,
        lender: none,
        amount: amount,
        interest-rate: interest-rate,
        duration-blocks: duration-blocks,
        collateral: collateral-amount,
        status: STATUS-REQUESTED,
        funded-at: none,
        due-at: none,
        repaid-amount: u0,
        created-at: block-height
      }
    )
    
    ;; Initialize payment tracking
    (map-set loan-payments loan-id
      {
        total-paid: u0,
        payment-count: u0,
        last-payment: none
      }
    )
    
    (var-set loan-counter loan-id)
    (ok loan-id)
  )
)

;; Fund a loan (lender provides funds)
(define-public (fund-loan (loan-id uint))
  (match (map-get? loans loan-id)
    loan-data
    (let ((due-block (+ block-height (get duration-blocks loan-data))))
      (asserts! (is-eq (get status loan-data) STATUS-REQUESTED) ERR-LOAN-ALREADY-FUNDED)
      
      ;; Update loan with lender info
      (map-set loans loan-id
        (merge loan-data
          {
            lender: (some tx-sender),
            status: STATUS-ACTIVE,
            funded-at: (some block-height),
            due-at: (some due-block)
          }
        )
      )
      
      ;; In a real implementation, transfer tokens from lender to borrower
      (ok loan-id)
    )
    ERR-LOAN-NOT-FOUND
  )
)

;; Make loan payment
(define-public (make-payment (loan-id uint) (payment-amount uint))
  (match (map-get? loans loan-id)
    loan-data
    (let (
      (current-payments (default-to 
        { total-paid: u0, payment-count: u0, last-payment: none }
        (map-get? loan-payments loan-id)
      ))
      (new-total-paid (+ (get total-paid current-payments) payment-amount))
      (total-due (calculate-total-repayment (get amount loan-data) (get interest-rate loan-data)))
    )
      (asserts! (is-eq tx-sender (get borrower loan-data)) ERR-UNAUTHORIZED)
      (asserts! (is-eq (get status loan-data) STATUS-ACTIVE) ERR-LOAN-NOT-ACTIVE)
      (asserts! (> payment-amount u0) ERR-INVALID-AMOUNT)
      
      ;; Update payment tracking
      (map-set loan-payments loan-id
        {
          total-paid: new-total-paid,
          payment-count: (+ (get payment-count current-payments) u1),
          last-payment: (some block-height)
        }
      )
      
      ;; Update loan repaid amount
      (map-set loans loan-id
        (merge loan-data { repaid-amount: new-total-paid })
      )
      
      ;; Check if fully repaid
      (if (>= new-total-paid total-due)
        (begin
          ;; Mark as repaid and release collateral
          (map-set loans loan-id
            (merge loan-data 
              { 
                status: STATUS-REPAID,
                repaid-amount: new-total-paid
              }
            )
          )
          (map-set user-balances (get borrower loan-data)
            (+ (get-user-balance (get borrower loan-data)) (get collateral loan-data))
          )
        )
        true
      )
      
      (ok new-total-paid)
    )
    ERR-LOAN-NOT-FOUND
  )
)

;; Liquidate overdue loan (lender can claim collateral)
(define-public (liquidate-loan (loan-id uint))
  (match (map-get? loans loan-id)
    loan-data
    (begin
      (asserts! (is-eq (some tx-sender) (get lender loan-data)) ERR-UNAUTHORIZED)
      (asserts! (is-loan-overdue loan-id) ERR-LOAN-NOT-ACTIVE)
      
      ;; Mark loan as defaulted
      (map-set loans loan-id
        (merge loan-data { status: STATUS-DEFAULTED })
      )
      
      ;; Transfer collateral to lender
      (map-set user-balances tx-sender
        (+ (get-user-balance tx-sender) (get collateral loan-data))
      )
      
      (ok (get collateral loan-data))
    )
    ERR-LOAN-NOT-FOUND
  )
)

;; Emergency functions (contract owner only)
(define-public (set-contract-owner (new-owner principal))
  (begin
    (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-UNAUTHORIZED)
    (var-set contract-owner new-owner)
    (ok true)
  )
)

;; Get loan payment history
(define-read-only (get-loan-payments (loan-id uint))
  (map-get? loan-payments loan-id)
)

;; Calculate current loan health (repayment progress)
(define-read-only (get-loan-health (loan-id uint))
  (match (map-get? loans loan-id)
    loan-data
    (let (
      (total-due (calculate-total-repayment (get amount loan-data) (get interest-rate loan-data)))
      (repaid (get repaid-amount loan-data))
    )
      (if (> total-due u0)
        (some (/ (* repaid u100) total-due)) ;; Return percentage repaid
        none
      )
    )
    none
  )
)

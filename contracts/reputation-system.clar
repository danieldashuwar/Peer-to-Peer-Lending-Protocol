;; Advanced Reputation System for P2P Lending
;; Tracks user behavior, calculates dynamic reputation scores, and provides risk assessment

;; Error constants
(define-constant ERR-UNAUTHORIZED (err u200))
(define-constant ERR-USER-NOT-FOUND (err u201))
(define-constant ERR-INVALID-SCORE (err u202))
(define-constant ERR-INVALID-RATING (err u203))
(define-constant ERR-ALREADY-RATED (err u204))
(define-constant ERR-SELF-RATING (err u205))
(define-constant ERR-FREEZE-NOT-ALLOWED (err u206))
(define-constant ERR-ALREADY-FROZEN (err u207))
(define-constant ERR-NOT-FROZEN (err u208))

;; Data variables
(define-data-var contract-owner principal tx-sender)
(define-data-var reputation-decay-rate uint u5) ;; 0.5% per period

;; Reputation tiers
(define-constant TIER-BRONZE u1)
(define-constant TIER-SILVER u2)
(define-constant TIER-GOLD u3)
(define-constant TIER-PLATINUM u4)
(define-constant TIER-DIAMOND u5)

;; User reputation profile
(define-map user-reputation
  principal
  {
    ;; Core metrics
    reputation-score: uint,    ;; 0-1000 scale
    trust-level: uint,         ;; 1-5 tier system
    total-loans: uint,
    successful-loans: uint,
    defaulted-loans: uint,
    
    ;; Borrower metrics
    avg-repayment-time: uint,  ;; Average blocks to repay
    early-repayments: uint,
    late-payments: uint,
    total-borrowed: uint,
    
    ;; Lender metrics
    loans-funded: uint,
    total-lent: uint,
    recovery-rate: uint,       ;; Percentage of funds recovered from defaults
    
    ;; Social metrics
    peer-ratings-count: uint,
    peer-ratings-sum: uint,
    
    ;; Temporal data
    last-activity: uint,
    account-age: uint,
    reputation-updated: uint
  }
)

;; Peer rating system (prevents double-rating)
(define-map peer-ratings
  { rater: principal, ratee: principal }
  {
    rating: uint,              ;; 1-5 stars
    comment-hash: (buff 32),   ;; Hash of comment for privacy
    timestamp: uint,
    loan-id: (optional uint)   ;; Associated loan if applicable
  }
)

;; Reputation milestones and achievements
(define-map user-achievements
  principal
  {
    early-adopter: bool,       ;; First 100 users
    reliable-borrower: bool,   ;; 95%+ on-time payments
    trusted-lender: bool,      ;; 90%+ recovery rate
    community-builder: bool,   ;; High peer ratings
    volume-trader: bool        ;; High transaction volume
  }
)

;; Risk assessment cache (updated periodically)
(define-map risk-profiles
  principal
  {
    risk-category: uint,       ;; 1=Low, 2=Medium, 3=High, 4=Very High
    max-loan-amount: uint,
    recommended-interest: uint,
    confidence-level: uint,    ;; How confident we are in this assessment
    last-calculated: uint
  }
)

(define-map freeze-state
  principal
  {
    is-frozen: bool,
    frozen-at: uint,
    frozen-score: uint,
    freeze-reason: uint,
    freeze-duration: uint
  }
)

;; Read-only functions

(define-read-only (get-user-reputation (user principal))
  (map-get? user-reputation user)
)

(define-read-only (get-user-achievements (user principal))
  (map-get? user-achievements user)
)

(define-read-only (get-risk-profile (user principal))
  (map-get? risk-profiles user)
)

(define-read-only (get-peer-rating (rater principal) (ratee principal))
  (map-get? peer-ratings { rater: rater, ratee: ratee })
)

(define-read-only (get-freeze-state (user principal))
  (map-get? freeze-state user)
)

(define-read-only (is-reputation-frozen (user principal))
  (match (map-get? freeze-state user)
    freeze-data
    (if (get is-frozen freeze-data)
      (if (< (- block-height (get frozen-at freeze-data)) (get freeze-duration freeze-data))
        true
        false
      )
      false
    )
    false
  )
)

(define-read-only (calculate-reputation-score (user principal))
  (match (map-get? user-reputation user)
    user-data
    (let (
      (base-score u500) ;; Start at 50%
      (success-rate (if (> (get total-loans user-data) u0)
        (/ (* (get successful-loans user-data) u100) (get total-loans user-data))
        u50
      ))
      (default-rate (if (> (get total-loans user-data) u0)
        (/ (* (get defaulted-loans user-data) u100) (get total-loans user-data))
        u0
      ))
      (peer-score (if (> (get peer-ratings-count user-data) u0)
        (/ (* (get peer-ratings-sum user-data) u200) (get peer-ratings-count user-data)) ;; Convert to 0-1000 scale
        u500
      ))
      (volume-bonus (let ((calc (/ (get total-borrowed user-data) u10000))) (if (> calc u100) u100 calc))) ;; Bonus up to 10 points
      (age-bonus (let ((calc (/ (- block-height (get account-age user-data)) u1000))) (if (> calc u50) u50 calc))) ;; Account age bonus
    )
      ;; Weighted calculation
      (some (let ((calc (let ((result (+
        (/ (* base-score u20) u100)      ;; 20% base
        (/ (* success-rate u30) u100)    ;; 30% success rate
        (/ (* (- u100 default-rate) u25) u100) ;; 25% inverse default rate
        (/ (* peer-score u20) u100)      ;; 20% peer ratings
        (/ (* volume-bonus u3) u100)     ;; 3% volume bonus
        (/ (* age-bonus u2) u100)        ;; 2% age bonus
      ))) (if (< result u0) u0 result)))) (if (> calc u1000) u1000 calc)))
    )
    none
  )
)

(define-read-only (get-trust-tier (reputation-score uint))
  (if (>= reputation-score u900) TIER-DIAMOND
    (if (>= reputation-score u750) TIER-PLATINUM
      (if (>= reputation-score u600) TIER-GOLD
        (if (>= reputation-score u400) TIER-SILVER
          TIER-BRONZE
        )
      )
    )
  )
)

(define-read-only (calculate-risk-category (user principal))
  (match (get-user-reputation user)
    user-data
    (let (
      (reputation-score (unwrap! (calculate-reputation-score user) u4))
      (default-rate (if (> (get total-loans user-data) u0)
        (/ (* (get defaulted-loans user-data) u100) (get total-loans user-data))
        u10 ;; Conservative estimate for new users
      ))
      (recent-activity (< (- block-height (get last-activity user-data)) u1000))
    )
      (if (and (>= reputation-score u800) (<= default-rate u5) recent-activity)
        u1 ;; Low risk
        (if (and (>= reputation-score u600) (<= default-rate u15) recent-activity)
          u2 ;; Medium risk
          (if (and (>= reputation-score u400) (<= default-rate u25))
            u3 ;; High risk
            u4 ;; Very high risk
          )
        )
      )
    )
    u4 ;; Default to very high risk for unknown users
  )
)

;; Public functions

;; Initialize user reputation profile
(define-public (initialize-reputation)
  (let ((existing-profile (map-get? user-reputation tx-sender)))
    (if (is-some existing-profile)
      (ok false) ;; Already initialized
      (begin
        (map-set user-reputation tx-sender
          {
            reputation-score: u500,
            trust-level: TIER-SILVER,
            total-loans: u0,
            successful-loans: u0,
            defaulted-loans: u0,
            avg-repayment-time: u0,
            early-repayments: u0,
            late-payments: u0,
            total-borrowed: u0,
            loans-funded: u0,
            total-lent: u0,
            recovery-rate: u100,
            peer-ratings-count: u0,
            peer-ratings-sum: u0,
            last-activity: block-height,
            account-age: block-height,
            reputation-updated: block-height
          }
        )
        (map-set user-achievements tx-sender
          {
            early-adopter: false,
            reliable-borrower: false,
            trusted-lender: false,
            community-builder: false,
            volume-trader: false
          }
        )
        (ok true)
      )
    )
  )
)

;; Record successful loan completion (called by lending contract)
(define-public (record-loan-completion (borrower principal) (lender principal) (amount uint) (on-time bool))
  (begin
    ;; This would be restricted to authorized contracts in production
    (record-borrower-activity borrower amount on-time true)
    (record-lender-activity lender amount true)
    (ok true)
  )
)

;; Record loan default (called by lending contract)
(define-public (record-loan-default (borrower principal) (lender principal) (amount uint) (recovered-amount uint))
  (let ((recovery-rate (if (> amount u0) (/ (* recovered-amount u100) amount) u0)))
    (record-borrower-activity borrower amount false false)
    (record-lender-activity-with-recovery lender amount false recovery-rate)
    (ok recovery-rate)
  )
)

;; Rate another user (peer review system)
(define-public (rate-user (ratee principal) (rating uint) (comment-hash (buff 32)) (loan-id (optional uint)))
  (let ((rating-key { rater: tx-sender, ratee: ratee }))
    (asserts! (not (is-eq tx-sender ratee)) ERR-SELF-RATING)
    (asserts! (and (>= rating u1) (<= rating u5)) ERR-INVALID-RATING)
    (asserts! (is-none (map-get? peer-ratings rating-key)) ERR-ALREADY-RATED)
    
    ;; Record the rating
    (map-set peer-ratings rating-key
      {
        rating: rating,
        comment-hash: comment-hash,
        timestamp: block-height,
        loan-id: loan-id
      }
    )
    
    (ok rating)
  )
)

;; Update reputation score and achievements
(define-public (update-reputation-score (user principal))
  (match (map-get? user-reputation user)
    user-data
    (match (calculate-reputation-score user)
      new-score
      (let (
        (new-tier (get-trust-tier new-score))
        (risk-category (calculate-risk-category user))
      )
        ;; Update reputation
        (map-set user-reputation user
          (merge user-data
            {
              reputation-score: new-score,
              trust-level: new-tier,
              reputation-updated: block-height
            }
          )
        )
        
        ;; Update risk profile
        (map-set risk-profiles user
          {
            risk-category: risk-category,
            max-loan-amount: (calculate-max-loan-amount new-score risk-category),
            recommended-interest: (calculate-recommended-interest risk-category),
            confidence-level: (calculate-confidence-level user-data),
            last-calculated: block-height
          }
        )
        
        ;; Check and update achievements
        (update-achievements user user-data)
        (ok new-score)
      )
      (err ERR-INVALID-SCORE)
    )
    (err ERR-USER-NOT-FOUND)
  )
)

(define-public (freeze-reputation (target-user principal) (reason uint) (duration uint))
  (let (
    (caller-data (map-get? user-reputation tx-sender))
    (target-data (map-get? user-reputation target-user))
    (freeze-key target-user)
    (current-score (match (calculate-reputation-score target-user)
      score score
      u500
    ))
  )
    (asserts! (is-some caller-data) ERR-USER-NOT-FOUND)
    (asserts! (is-some target-data) ERR-USER-NOT-FOUND)
    (asserts! (is-none (map-get? freeze-state freeze-key)) ERR-ALREADY-FROZEN)
    
    (map-set freeze-state freeze-key
      {
        is-frozen: true,
        frozen-at: block-height,
        frozen-score: current-score,
        freeze-reason: reason,
        freeze-duration: duration
      }
    )
    (ok true)
  )
)

(define-public (unfreeze-reputation (target-user principal))
  (let ((freeze-key target-user))
    (asserts! (is-some (map-get? freeze-state freeze-key)) ERR-NOT-FROZEN)
    
    (map-set freeze-state freeze-key
      {
        is-frozen: false,
        frozen-at: u0,
        frozen-score: u0,
        freeze-reason: u0,
        freeze-duration: u0
      }
    )
    (ok true)
  )
)

;; Private helper functions

(define-private (record-borrower-activity (borrower principal) (amount uint) (on-time bool) (successful bool))
  (match (map-get? user-reputation borrower)
    user-data
    (map-set user-reputation borrower
      (merge user-data
        {
          total-loans: (+ (get total-loans user-data) u1),
          successful-loans: (if successful (+ (get successful-loans user-data) u1) (get successful-loans user-data)),
          defaulted-loans: (if successful (get defaulted-loans user-data) (+ (get defaulted-loans user-data) u1)),
          early-repayments: (if on-time (+ (get early-repayments user-data) u1) (get early-repayments user-data)),
          late-payments: (if on-time (get late-payments user-data) (+ (get late-payments user-data) u1)),
          total-borrowed: (+ (get total-borrowed user-data) amount),
          last-activity: block-height
        }
      )
    )
    false ;; User not found, should initialize first
  )
)

(define-private (record-lender-activity (lender principal) (amount uint) (successful bool))
  (match (map-get? user-reputation lender)
    user-data
    (map-set user-reputation lender
      (merge user-data
        {
          loans-funded: (+ (get loans-funded user-data) u1),
          total-lent: (+ (get total-lent user-data) amount),
          last-activity: block-height
        }
      )
    )
    false
  )
)

(define-private (record-lender-activity-with-recovery (lender principal) (amount uint) (successful bool) (recovery-rate uint))
  (match (map-get? user-reputation lender)
    user-data
    (let ((current-recovery (get recovery-rate user-data)))
      (map-set user-reputation lender
        (merge user-data
          {
            loans-funded: (+ (get loans-funded user-data) u1),
            total-lent: (+ (get total-lent user-data) amount),
            recovery-rate: (/ (+ current-recovery recovery-rate) u2), ;; Simple average
            last-activity: block-height
          }
        )
      )
    )
    false
  )
)

(define-private (calculate-max-loan-amount (reputation-score uint) (risk-category uint))
  (let ((base-amount u1000000)) ;; 1M base amount in microSTX
    (if (is-eq risk-category u1)
      (* base-amount u10) ;; Low risk: 10M max
      (if (is-eq risk-category u2)
        (* base-amount u5)  ;; Medium risk: 5M max
        (if (is-eq risk-category u3)
          (* base-amount u2) ;; High risk: 2M max
          base-amount        ;; Very high risk: 1M max
        )
      )
    )
  )
)

(define-private (calculate-recommended-interest (risk-category uint))
  (if (is-eq risk-category u1)
    u300  ;; 3% for low risk
    (if (is-eq risk-category u2)
      u800  ;; 8% for medium risk
      (if (is-eq risk-category u3)
        u1500 ;; 15% for high risk
        u2500 ;; 25% for very high risk
      )
    )
  )
)

(define-private (calculate-confidence-level (user-data (tuple (reputation-score uint) (trust-level uint) (total-loans uint) (successful-loans uint) (defaulted-loans uint) (avg-repayment-time uint) (early-repayments uint) (late-payments uint) (total-borrowed uint) (loans-funded uint) (total-lent uint) (recovery-rate uint) (peer-ratings-count uint) (peer-ratings-sum uint) (last-activity uint) (account-age uint) (reputation-updated uint))))
  (let (
    (loan-history-score (let ((calc (* (get total-loans user-data) u2))) (if (> calc u40) u40 calc)))
    (peer-rating-score (let ((calc (* (get peer-ratings-count user-data) u3))) (if (> calc u30) u30 calc)))
    (account-age-score (let ((calc (/ (- block-height (get account-age user-data)) u2500))) (if (> calc u20) u20 calc)))
    (activity-score (if (< (- block-height (get last-activity user-data)) u500) u10 u0))
  )
    (+ loan-history-score peer-rating-score account-age-score activity-score)
  )
)

(define-private (update-achievements (user principal) (user-data (tuple (reputation-score uint) (trust-level uint) (total-loans uint) (successful-loans uint) (defaulted-loans uint) (avg-repayment-time uint) (early-repayments uint) (late-payments uint) (total-borrowed uint) (loans-funded uint) (total-lent uint) (recovery-rate uint) (peer-ratings-count uint) (peer-ratings-sum uint) (last-activity uint) (account-age uint) (reputation-updated uint))))
  (let (
    (success-rate (if (> (get total-loans user-data) u0)
      (/ (* (get successful-loans user-data) u100) (get total-loans user-data))
      u0
    ))
  )
    (map-set user-achievements user
      {
        early-adopter: (< (get account-age user-data) u100), ;; First 100 blocks (adjust as needed)
        reliable-borrower: (and (> (get total-loans user-data) u5) (>= success-rate u95)),
        trusted-lender: (and (> (get loans-funded user-data) u5) (>= (get recovery-rate user-data) u90)),
        community-builder: (and (> (get peer-ratings-count user-data) u10) (>= (/ (* (get peer-ratings-sum user-data) u100) (get peer-ratings-count user-data)) u400)),
        volume-trader: (or (> (get total-borrowed user-data) u50000000) (> (get total-lent user-data) u50000000))
      }
    )
  )
)

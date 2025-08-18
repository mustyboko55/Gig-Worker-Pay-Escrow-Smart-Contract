(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-UNAUTHORIZED (err u100))
(define-constant ERR-NOT-FOUND (err u101))
(define-constant ERR-INVALID-STATE (err u102))
(define-constant ERR-INSUFFICIENT-FUNDS (err u103))
(define-constant ERR-ALREADY-EXISTS (err u104))
(define-constant ERR-TIMEOUT-NOT-REACHED (err u105))
(define-constant ERR-INVALID-PROOF (err u106))

(define-data-var next-escrow-id uint u1)
(define-data-var contract-fee uint u250)

(define-map escrows uint {
    employer: principal,
    worker: principal,
    amount: uint,
    milestone-description: (string-ascii 256),
    state: (string-ascii 20),
    created-at: uint,
    deadline: uint,
    proof-hash: (optional (buff 32)),
    dispute-reason: (optional (string-ascii 256))
})

(define-map user-balances principal uint)

(define-private (get-escrow-state (escrow-id uint))
    (get state (map-get? escrows escrow-id))
)

(define-private (is-employer (escrow-id uint) (user principal))
    (match (map-get? escrows escrow-id)
        escrow (is-eq (get employer escrow) user)
        false
    )
)

(define-private (is-worker (escrow-id uint) (user principal))
    (match (map-get? escrows escrow-id)
        escrow (is-eq (get worker escrow) user)
        false
    )
)

(define-private (is-valid-state (escrow-id uint) (expected-state (string-ascii 20)))
    (match (get-escrow-state escrow-id)
        state (is-eq state expected-state)
        false
    )
)

(define-private (calculate-fee (amount uint))
    (/ (* amount (var-get contract-fee)) u10000)
)

(define-private (add-to-balance (user principal) (amount uint))
    (let ((current-balance (default-to u0 (map-get? user-balances user))))
        (map-set user-balances user (+ current-balance amount))
    )
)

(define-private (subtract-from-balance (user principal) (amount uint))
    (let ((current-balance (default-to u0 (map-get? user-balances user))))
        (if (>= current-balance amount)
            (begin
                (map-set user-balances user (- current-balance amount))
                (ok true)
            )
            ERR-INSUFFICIENT-FUNDS
        )
    )
)

(define-public (create-escrow (worker principal) (amount uint) (milestone-description (string-ascii 256)) (days-deadline uint))
    (let (
        (escrow-id (var-get next-escrow-id))
        (current-block stacks-block-height)
        (deadline-block (+ current-block (* days-deadline u144)))
    )
        (asserts! (> amount u0) ERR-INSUFFICIENT-FUNDS)
        (asserts! (not (is-eq tx-sender worker)) ERR-UNAUTHORIZED)
        (map-set escrows escrow-id {
            employer: tx-sender,
            worker: worker,
            amount: amount,
            milestone-description: milestone-description,
            state: "created",
            created-at: current-block,
            deadline: deadline-block,
            proof-hash: none,
            dispute-reason: none
        })
        (var-set next-escrow-id (+ escrow-id u1))
        (ok escrow-id)
    )
)

(define-public (fund-escrow (escrow-id uint))
    (let (
        (escrow (unwrap! (map-get? escrows escrow-id) ERR-NOT-FOUND))
        (amount (get amount escrow))
        (fee (calculate-fee amount))
        (total-needed (+ amount fee))
    )
        (asserts! (is-employer escrow-id tx-sender) ERR-UNAUTHORIZED)
        (asserts! (is-valid-state escrow-id "created") ERR-INVALID-STATE)
        (try! (stx-transfer? total-needed tx-sender (as-contract tx-sender)))
        (map-set escrows escrow-id 
            (merge escrow { state: "funded" })
        )
        (add-to-balance CONTRACT-OWNER fee)
        (ok true)
    )
)

(define-public (submit-milestone-proof (escrow-id uint) (proof-hash (buff 32)))
    (let (
        (escrow (unwrap! (map-get? escrows escrow-id) ERR-NOT-FOUND))
    )
        (asserts! (is-worker escrow-id tx-sender) ERR-UNAUTHORIZED)
        (asserts! (is-valid-state escrow-id "funded") ERR-INVALID-STATE)
        (asserts! (> (len proof-hash) u0) ERR-INVALID-PROOF)
        (map-set escrows escrow-id 
            (merge escrow { 
                state: "proof-submitted",
                proof-hash: (some proof-hash)
            })
        )
        (ok true)
    )
)

(define-public (approve-milestone (escrow-id uint))
    (let (
        (escrow (unwrap! (map-get? escrows escrow-id) ERR-NOT-FOUND))
        (amount (get amount escrow))
        (worker (get worker escrow))
    )
        (asserts! (is-employer escrow-id tx-sender) ERR-UNAUTHORIZED)
        (asserts! (is-valid-state escrow-id "proof-submitted") ERR-INVALID-STATE)
        (try! (as-contract (stx-transfer? amount tx-sender worker)))
        (map-set escrows escrow-id 
            (merge escrow { state: "completed" })
        )
        (ok true)
    )
)

(define-public (auto-release-funds (escrow-id uint))
    (let (
        (escrow (unwrap! (map-get? escrows escrow-id) ERR-NOT-FOUND))
        (amount (get amount escrow))
        (worker (get worker escrow))
        (deadline (get deadline escrow))
        (current-block stacks-block-height)
    )
        (asserts! (is-valid-state escrow-id "proof-submitted") ERR-INVALID-STATE)
        (asserts! (>= current-block (+ deadline u144)) ERR-TIMEOUT-NOT-REACHED)
        (try! (as-contract (stx-transfer? amount tx-sender worker)))
        (map-set escrows escrow-id 
            (merge escrow { state: "auto-completed" })
        )
        (ok true)
    )
)

(define-public (dispute-escrow (escrow-id uint) (reason (string-ascii 256)))
    (let (
        (escrow (unwrap! (map-get? escrows escrow-id) ERR-NOT-FOUND))
    )
        (asserts! (or (is-employer escrow-id tx-sender) (is-worker escrow-id tx-sender)) ERR-UNAUTHORIZED)
        (asserts! (or 
            (is-valid-state escrow-id "proof-submitted")
            (is-valid-state escrow-id "funded")
        ) ERR-INVALID-STATE)
        (map-set escrows escrow-id 
            (merge escrow { 
                state: "disputed",
                dispute-reason: (some reason)
            })
        )
        (ok true)
    )
)

(define-public (resolve-dispute (escrow-id uint) (release-to-worker bool))
    (let (
        (escrow (unwrap! (map-get? escrows escrow-id) ERR-NOT-FOUND))
        (amount (get amount escrow))
        (employer (get employer escrow))
        (worker (get worker escrow))
        (recipient (if release-to-worker worker employer))
    )
        (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-UNAUTHORIZED)
        (asserts! (is-valid-state escrow-id "disputed") ERR-INVALID-STATE)
        (try! (as-contract (stx-transfer? amount tx-sender recipient)))
        (map-set escrows escrow-id 
            (merge escrow { state: "resolved" })
        )
        (ok true)
    )
)

(define-public (cancel-escrow (escrow-id uint))
    (let (
        (escrow (unwrap! (map-get? escrows escrow-id) ERR-NOT-FOUND))
        (amount (get amount escrow))
        (employer (get employer escrow))
        (fee (calculate-fee amount))
    )
        (asserts! (is-employer escrow-id tx-sender) ERR-UNAUTHORIZED)
        (asserts! (or 
            (is-valid-state escrow-id "created")
            (is-valid-state escrow-id "funded")
        ) ERR-INVALID-STATE)
        (if (is-valid-state escrow-id "funded")
            (try! (as-contract (stx-transfer? amount tx-sender employer)))
            true
        )
        (map-set escrows escrow-id 
            (merge escrow { state: "cancelled" })
        )
        (ok true)
    )
)

(define-public (withdraw-balance)
    (let (
        (balance (default-to u0 (map-get? user-balances tx-sender)))
    )
        (asserts! (> balance u0) ERR-INSUFFICIENT-FUNDS)
        (try! (subtract-from-balance tx-sender balance))
        (try! (as-contract (stx-transfer? balance tx-sender tx-sender)))
        (ok balance)
    )
)

(define-public (update-contract-fee (new-fee uint))
    (begin
        (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-UNAUTHORIZED)
        (asserts! (<= new-fee u1000) ERR-INVALID-STATE)
        (var-set contract-fee new-fee)
        (ok true)
    )
)

(define-read-only (get-escrow (escrow-id uint))
    (map-get? escrows escrow-id)
)

(define-read-only (get-user-balance (user principal))
    (default-to u0 (map-get? user-balances user))
)

(define-read-only (get-contract-fee)
    (var-get contract-fee)
)

(define-read-only (get-next-escrow-id)
    (var-get next-escrow-id)
)

(define-read-only (is-escrow-expired (escrow-id uint))
    (match (map-get? escrows escrow-id)
        escrow (>= stacks-block-height (get deadline escrow))
        false
    )
)

(define-read-only (get-escrow-time-remaining (escrow-id uint))
    (match (map-get? escrows escrow-id)
        escrow (let ((current-block stacks-block-height)
                     (deadline (get deadline escrow)))
                 (if (> deadline current-block)
                     (some (- deadline current-block))
                     (some u0)))
        none
    )
)

(define-read-only (can-auto-release (escrow-id uint))
    (match (map-get? escrows escrow-id)
        escrow (and 
            (is-eq (get state escrow) "proof-submitted")
            (>= stacks-block-height (+ (get deadline escrow) u144))
        )
        false
    )
)

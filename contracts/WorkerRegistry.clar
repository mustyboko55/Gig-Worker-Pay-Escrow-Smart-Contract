;; Worker Reputation & Skills Registry Contract
;; Enables workers to build verifiable reputation and skill profiles

(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-UNAUTHORIZED (err u200))
(define-constant ERR-NOT-FOUND (err u201))
(define-constant ERR-INVALID-RATING (err u202))
(define-constant ERR-ALREADY-EXISTS (err u203))
(define-constant ERR-INVALID-SKILL (err u204))
(define-constant ERR-CANNOT-SELF-RATE (err u205))
(define-constant ERR-INSUFFICIENT-STAKE (err u206))

;; Minimum stake required for skill certification (in microSTX)
(define-data-var certification-stake uint u1000000)
(define-data-var next-skill-id uint u1)

;; Worker profile structure
(define-map worker-profiles principal {
    display-name: (string-ascii 64),
    bio: (string-ascii 256),
    location: (string-ascii 64),
    hourly-rate: uint,
    total-jobs: uint,
    completed-jobs: uint,
    average-rating: uint,
    total-earned: uint,
    registration-date: uint,
    is-verified: bool
})

;; Skills catalog - predefined skills that workers can claim
(define-map skills uint {
    name: (string-ascii 32),
    category: (string-ascii 32),
    description: (string-ascii 128),
    created-by: principal,
    is-active: bool
})

;; Worker skills - tracks which skills a worker has and their proficiency
(define-map worker-skills {worker: principal, skill-id: uint} {
    proficiency-level: uint, ;; 1-5 scale
    certification-date: uint,
    endorsement-count: uint,
    stake-amount: uint,
    is-verified: bool
})

;; Endorsements - other users can endorse a worker's skill
(define-map skill-endorsements {endorser: principal, worker: principal, skill-id: uint} {
    endorsement-date: uint,
    comment: (optional (string-ascii 128))
})

;; Job completion records for reputation building
(define-map job-completions {worker: principal, job-id: uint} {
    employer: principal,
    rating: uint, ;; 1-5 scale
    feedback: (string-ascii 256),
    completion-date: uint,
    job-value: uint,
    skills-used: (list 5 uint)
})

;; Worker availability status
(define-map worker-availability principal {
    is-available: bool,
    available-hours-per-week: uint,
    earliest-start-date: uint
})

(define-private (is-valid-rating (rating uint))
    (and (>= rating u1) (<= rating u5))
)

(define-private (calculate-weighted-rating (current-avg uint) (current-count uint) (new-rating uint))
    (if (is-eq current-count u0)
        new-rating
        (/ (+ (* current-avg current-count) new-rating) (+ current-count u1))
    )
)

;; Create or update worker profile
(define-public (create-worker-profile (display-name (string-ascii 64)) (bio (string-ascii 256)) (location (string-ascii 64)) (hourly-rate uint))
    (begin
        (asserts! (> (len display-name) u0) ERR-INVALID-SKILL)
        (asserts! (> hourly-rate u0) ERR-INVALID-RATING)
        (map-set worker-profiles tx-sender {
            display-name: display-name,
            bio: bio,
            location: location,
            hourly-rate: hourly-rate,
            total-jobs: u0,
            completed-jobs: u0,
            average-rating: u0,
            total-earned: u0,
            registration-date: stacks-block-height,
            is-verified: false
        })
        (ok true)
    )
)

;; Update worker profile
(define-public (update-worker-profile (display-name (string-ascii 64)) (bio (string-ascii 256)) (location (string-ascii 64)) (hourly-rate uint))
    (let (
        (existing-profile (unwrap! (map-get? worker-profiles tx-sender) ERR-NOT-FOUND))
    )
        (asserts! (> (len display-name) u0) ERR-INVALID-SKILL)
        (asserts! (> hourly-rate u0) ERR-INVALID-RATING)
        (map-set worker-profiles tx-sender 
            (merge existing-profile {
                display-name: display-name,
                bio: bio,
                location: location,
                hourly-rate: hourly-rate
            })
        )
        (ok true)
    )
)

;; Set worker availability
(define-public (set-availability (is-available bool) (hours-per-week uint) (earliest-start-date uint))
    (begin
        (map-set worker-availability tx-sender {
            is-available: is-available,
            available-hours-per-week: hours-per-week,
            earliest-start-date: earliest-start-date
        })
        (ok true)
    )
)

;; Create a new skill in the catalog
(define-public (create-skill (name (string-ascii 32)) (category (string-ascii 32)) (description (string-ascii 128)))
    (let (
        (skill-id (var-get next-skill-id))
    )
        (asserts! (> (len name) u0) ERR-INVALID-SKILL)
        (asserts! (> (len category) u0) ERR-INVALID-SKILL)
        (map-set skills skill-id {
            name: name,
            category: category,
            description: description,
            created-by: tx-sender,
            is-active: true
        })
        (var-set next-skill-id (+ skill-id u1))
        (ok skill-id)
    )
)

;; Worker claims a skill with stake
(define-public (claim-skill (skill-id uint) (proficiency-level uint))
    (let (
        (skill (unwrap! (map-get? skills skill-id) ERR-NOT-FOUND))
        (stake-amount (var-get certification-stake))
        (existing-claim (map-get? worker-skills {worker: tx-sender, skill-id: skill-id}))
    )
        (asserts! (get is-active skill) ERR-INVALID-SKILL)
        (asserts! (and (>= proficiency-level u1) (<= proficiency-level u5)) ERR-INVALID-RATING)
        (asserts! (is-none existing-claim) ERR-ALREADY-EXISTS)
        (try! (stx-transfer? stake-amount tx-sender (as-contract tx-sender)))
        (map-set worker-skills {worker: tx-sender, skill-id: skill-id} {
            proficiency-level: proficiency-level,
            certification-date: stacks-block-height,
            endorsement-count: u0,
            stake-amount: stake-amount,
            is-verified: false
        })
        (ok true)
    )
)

;; Endorse another worker's skill
(define-public (endorse-skill (worker principal) (skill-id uint) (comment (optional (string-ascii 128))))
    (let (
        (worker-skill (unwrap! (map-get? worker-skills {worker: worker, skill-id: skill-id}) ERR-NOT-FOUND))
        (existing-endorsement (map-get? skill-endorsements {endorser: tx-sender, worker: worker, skill-id: skill-id}))
    )
        (asserts! (not (is-eq tx-sender worker)) ERR-CANNOT-SELF-RATE)
        (asserts! (is-none existing-endorsement) ERR-ALREADY-EXISTS)
        (map-set skill-endorsements {endorser: tx-sender, worker: worker, skill-id: skill-id} {
            endorsement-date: stacks-block-height,
            comment: comment
        })
        (map-set worker-skills {worker: worker, skill-id: skill-id}
            (merge worker-skill {
                endorsement-count: (+ (get endorsement-count worker-skill) u1)
            })
        )
        (ok true)
    )
)

;; Record job completion and update worker reputation
(define-public (record-job-completion (worker principal) (job-id uint) (rating uint) (feedback (string-ascii 256)) (job-value uint) (skills-used (list 5 uint)))
    (let (
        (worker-profile (unwrap! (map-get? worker-profiles worker) ERR-NOT-FOUND))
        (current-rating (get average-rating worker-profile))
        (current-jobs (get completed-jobs worker-profile))
        (new-average-rating (calculate-weighted-rating current-rating current-jobs rating))
    )
        (asserts! (is-valid-rating rating) ERR-INVALID-RATING)
        (asserts! (not (is-eq tx-sender worker)) ERR-CANNOT-SELF-RATE)
        (map-set job-completions {worker: worker, job-id: job-id} {
            employer: tx-sender,
            rating: rating,
            feedback: feedback,
            completion-date: stacks-block-height,
            job-value: job-value,
            skills-used: skills-used
        })
        (map-set worker-profiles worker
            (merge worker-profile {
                completed-jobs: (+ current-jobs u1),
                average-rating: new-average-rating,
                total-earned: (+ (get total-earned worker-profile) job-value)
            })
        )
        (ok true)
    )
)

;; Verify worker profile (owner only)
(define-public (verify-worker (worker principal))
    (let (
        (worker-profile (unwrap! (map-get? worker-profiles worker) ERR-NOT-FOUND))
    )
        (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-UNAUTHORIZED)
        (map-set worker-profiles worker
            (merge worker-profile { is-verified: true })
        )
        (ok true)
    )
)

;; Verify worker skill (owner only)
(define-public (verify-worker-skill (worker principal) (skill-id uint))
    (let (
        (worker-skill (unwrap! (map-get? worker-skills {worker: worker, skill-id: skill-id}) ERR-NOT-FOUND))
    )
        (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-UNAUTHORIZED)
        (map-set worker-skills {worker: worker, skill-id: skill-id}
            (merge worker-skill { is-verified: true })
        )
        (ok true)
    )
)

;; Update certification stake amount (owner only)
(define-public (update-certification-stake (new-stake uint))
    (begin
        (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-UNAUTHORIZED)
        (var-set certification-stake new-stake)
        (ok true)
    )
)

;; Read-only functions
(define-read-only (get-worker-profile (worker principal))
    (map-get? worker-profiles worker)
)

(define-read-only (get-worker-availability (worker principal))
    (map-get? worker-availability worker)
)

(define-read-only (get-skill (skill-id uint))
    (map-get? skills skill-id)
)

(define-read-only (get-worker-skill (worker principal) (skill-id uint))
    (map-get? worker-skills {worker: worker, skill-id: skill-id})
)

(define-read-only (get-skill-endorsement (endorser principal) (worker principal) (skill-id uint))
    (map-get? skill-endorsements {endorser: endorser, worker: worker, skill-id: skill-id})
)

(define-read-only (get-job-completion (worker principal) (job-id uint))
    (map-get? job-completions {worker: worker, job-id: job-id})
)

(define-read-only (get-certification-stake)
    (var-get certification-stake)
)

(define-read-only (get-next-skill-id)
    (var-get next-skill-id)
)

;; Check if worker meets minimum reputation criteria
(define-read-only (meets-reputation-criteria (worker principal) (min-rating uint) (min-jobs uint))
    (match (map-get? worker-profiles worker)
        profile (and 
            (>= (get average-rating profile) min-rating)
            (>= (get completed-jobs profile) min-jobs)
        )
        false
    )
)

;; Get worker's skills count - simplified version
(define-read-only (get-worker-skills-count (worker principal))
    (let (
        (skill-1 (map-get? worker-skills {worker: worker, skill-id: u1}))
        (skill-2 (map-get? worker-skills {worker: worker, skill-id: u2}))
        (skill-3 (map-get? worker-skills {worker: worker, skill-id: u3}))
        (skill-4 (map-get? worker-skills {worker: worker, skill-id: u4}))
        (skill-5 (map-get? worker-skills {worker: worker, skill-id: u5}))
    )
        (+ 
            (if (is-some skill-1) u1 u0)
            (+ 
                (if (is-some skill-2) u1 u0)
                (+ 
                    (if (is-some skill-3) u1 u0)
                    (+ 
                        (if (is-some skill-4) u1 u0)
                        (if (is-some skill-5) u1 u0)
                    )
                )
            )
        )
    )
)

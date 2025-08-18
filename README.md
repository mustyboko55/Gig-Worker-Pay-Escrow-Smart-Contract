# Gigguard - Gig Worker Pay Escrow Smart Contract

Gigguard is a decentralized escrow system built on the Stacks blockchain that protects both employers and gig workers by holding funds in escrow until milestone proof is submitted and verified.

## Features

- **Secure Escrow**: Funds are locked in smart contract until conditions are met
- **Milestone-Based**: Workers submit proof of completed work for payment release
- **Auto-Release**: Funds automatically release to worker after deadline if no dispute
- **Dispute Resolution**: Contract owner can resolve disputes between parties
- **Fee Structure**: Small platform fee (2.5% default) for escrow services
- **Time-Limited**: Each escrow has a deadline for milestone completion

## Contract States

- `created` - Escrow created but not yet funded
- `funded` - Employer has deposited funds
- `proof-submitted` - Worker has submitted milestone proof
- `completed` - Employer approved milestone and funds released
- `auto-completed` - Funds auto-released after deadline
- `disputed` - Either party raised a dispute
- `resolved` - Dispute resolved by contract owner
- `cancelled` - Escrow cancelled before completion

## Usage

### Creating an Escrow

```clarity
(contract-call? .Gigguard create-escrow 'SP1WORKER... u1000000 "Build website homepage" u7)
```
- `worker`: Principal address of the gig worker
- `amount`: Amount in microSTX (1 STX = 1,000,000 microSTX)
- `milestone-description`: Description of work to be completed
- `days-deadline`: Number of days to complete the milestone

### Funding an Escrow

```clarity
(contract-call? .Gigguard fund-escrow u1)
```
Employer must fund the escrow with the agreed amount plus platform fee.

### Submitting Milestone Proof

```clarity
(contract-call? .Gigguard submit-milestone-proof u1 0x1234567890abcdef...)
```
Worker submits a hash proving milestone completion (could be file hash, URL hash, etc.).

### Approving Milestone

```clarity
(contract-call? .Gigguard approve-milestone u1)
```
Employer approves the submitted proof and releases funds to worker.

### Auto-Release (Anyone Can Call)

```clarity
(contract-call? .Gigguard auto-release-funds u1)
```
If employer doesn't respond within 24 hours after deadline, anyone can trigger auto-release to worker.

### Dispute Resolution

```clarity
(contract-call? .Gigguard dispute-escrow u1 "Work not completed as specified")
(contract-call? .Gigguard resolve-dispute u1 true)
```
Either party can raise dispute; contract owner resolves by releasing funds to employer or worker.

### Cancelling Escrow

```clarity
(contract-call? .Gigguard cancel-escrow u1)
```
Employer can cancel unfunded or funded escrows and get refund.

## Read-Only Functions

### Get Escrow Details
```clarity
(contract-call? .Gigguard get-escrow u1)
```

### Check User Balance
```clarity
(contract-call? .Gigguard get-user-balance 'SP1USER...)
```

### Check if Auto-Release Available
```clarity
(contract-call? .Gigguard can-auto-release u1)
```

### Get Time Remaining
```clarity
(contract-call? .Gigguard get-escrow-time-remaining u1)
```

## Deployment

1. Deploy contract using Clarinet:
```bash
clarinet deploy
```

2. Test contract functions:
```bash
clarinet console
```

## Security Considerations

- Only employer can fund and approve escrows
- Only worker can submit milestone proofs
- Platform fee is capped at 10% maximum
- Contract owner has dispute resolution powers
- Funds are held securely in contract until release conditions are met

## Fee Structure

Default platform fee is 2.5% (250 basis points), capped at 10% maximum. Contract owner can adjust fees.

## License

MIT License

# 🏦 Peer-to-Peer Lending Protocol

A decentralized lending platform built on Stacks blockchain enabling direct peer-to-peer loans with smart contract enforcement.

## ✨ Features

- 📝 Create loan requests with customizable terms
- 💰 Fund loans directly as a lender
- 🔒 Automated collateral management
- 💸 Smart contract-enforced repayments
- ⭐ Borrower reputation tracking

## 🚀 Quick Start

1. Deploy the contract:
```bash
clarinet contract deploy
```

2. Create a loan request:
```bash
clarinet contract call create-loan-request amount=1000 collateral=2000 duration=144 interest-rate=10
```

3. Fund a loan as a lender:
```bash
clarinet contract call fund-loan loan-id=1
```

4. Make repayments as a borrower:
```bash
clarinet contract call repay-loan loan-id=1 repayment-amount=100
```

## 📖 Contract Functions

### create-loan-request
Create a new loan request with specified terms:
- amount: Loan amount in STX
- collateral: Collateral amount in STX
- duration: Loan duration in blocks
- interest-rate: Annual interest rate (in basis points)

### fund-loan
Fund an existing loan request:
- loan-id: ID of the loan to fund

### repay-loan
Make a repayment towards an active loan:
- loan-id: ID of the loan
- repayment-amount: Amount to repay in STX

### get-loan
Query loan details:
- loan-id: ID of the loan to query

### get-borrower-stats
Query borrower statistics:
- borrower: Principal to query

## 🔒 Security

The protocol implements basic security measures:
- Loan state validation
- Authorization checks
- Safe STX transfers

## 🤝 Contributing

Contributions are welcome! Please submit PRs with improvements.
```

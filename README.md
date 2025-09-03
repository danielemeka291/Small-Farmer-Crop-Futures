# 🌾 Small Farmer Crop Futures

A decentralized smart contract platform enabling small farmers to sell crop futures directly to buyers with secure escrow and reputation management.

## 📋 Overview

This Clarity smart contract facilitates crop futures trading between farmers and buyers on the Stacks blockchain. Farmers can list future crop harvests, buyers can purchase contracts with escrow protection, and the platform handles delivery confirmation and dispute resolution.

## ✨ Features

- 👨‍🌾 **Farmer Registration**: Secure farmer onboarding with reputation tracking
- 📦 **Crop Futures Listing**: Create contracts for future crop deliveries
- 💰 **Escrow Protection**: Secure payment handling until delivery confirmation
- 🤝 **Dispute Resolution**: Platform-mediated conflict resolution
- ⭐ **Reputation System**: Dynamic farmer reputation based on delivery performance
- 💸 **Platform Fees**: Configurable fee structure (default 2.5%)
- 🚀 **Batch Operations**: Create/purchase multiple contracts in single transactions

## 🚀 Getting Started

### Prerequisites

- [Clarinet](https://docs.hiro.so/stacks/clarinet) installed
- Stacks wallet for interactions
- STX tokens for transactions

### Installation

```bash
git clone <repository-url>
cd Small-Farmer-Crop-Futures
clarinet check
```

## 📖 Usage Guide

### For Farmers 👨‍🌾

#### 1. Register as a Farmer
```clarity
(contract-call? .Small-Farmer-Crop-Futures register-farmer 
    u"Green Valley Farm" 
    u"Iowa, USA")
```

#### 2. Create a Crop Contract
```clarity
(contract-call? .Small-Farmer-Crop-Futures create-crop-contract 
    u"Corn"           ;; crop type
    u1000             ;; quantity (bushels)
    u500000           ;; price per unit (micro-STX)
    u1000000          ;; delivery date (block height)
    "Grade-A")        ;; quality grade
```

#### 3. Create Multiple Contracts (Batch)
```clarity
(contract-call? .Small-Farmer-Crop-Futures create-batch-contracts
    (list
        { crop-type: u"Corn", quantity: u1000, price-per-unit: u500000, delivery-date: u1000000, quality-grade: "Grade-A" }
        { crop-type: u"Wheat", quantity: u800, price-per-unit: u600000, delivery-date: u1000000, quality-grade: "Grade-B" }
    )
)
```

#### 4. Cancel Open Contract (if needed)
```clarity
(contract-call? .Small-Farmer-Crop-Futures cancel-contract u1)
```

### For Buyers 🛒

#### 1. Browse and Purchase Contracts
```clarity
;; View contract details
(contract-call? .Small-Farmer-Crop-Futures get-contract u1)

;; Purchase contract
(contract-call? .Small-Farmer-Crop-Futures purchase-contract u1)
```

#### 2. Purchase Multiple Contracts (Batch)
```clarity
(contract-call? .Small-Farmer-Crop-Futures purchase-batch-contracts (list u1 u2 u3))
```

#### 3. Confirm Delivery
```clarity
(contract-call? .Small-Farmer-Crop-Futures confirm-delivery u1)
```

#### 4. Dispute if Issues Arise
```clarity
(contract-call? .Small-Farmer-Crop-Futures dispute-delivery u1)
```

### For Platform Admins 🔧

#### Resolve Disputes
```clarity
;; Resolve in favor of farmer
(contract-call? .Small-Farmer-Crop-Futures resolve-dispute u1 true)

;; Resolve in favor of buyer
(contract-call? .Small-Farmer-Crop-Futures resolve-dispute u1 false)
```

#### Emergency Refund (after 1 week delay)
```clarity
(contract-call? .Small-Farmer-Crop-Futures emergency-refund u1)
```

## 📊 Contract States

| Status | Description |
|--------|-------------|
| `open` | Contract created, awaiting buyer |
| `purchased` | Buyer locked in, payment escrowed |
| `delivered` | Delivery confirmed, payment released |
| `disputed` | Delivery disputed, awaiting resolution |
| `resolved-farmer` | Dispute resolved in farmer's favor |
| `resolved-buyer` | Dispute resolved in buyer's favor |
| `cancelled` | Contract cancelled by farmer |
| `refunded` | Emergency refund processed |

## 💡 Key Functions

### Read-Only Functions
- `get-contract(contract-id)` - Get contract details
- `get-farmer-info(farmer)` - Get farmer information
- `get-contract-payment(contract-id)` - Get payment details
- `get-platform-fee-rate()` - Current platform fee rate
- `get-contract-count()` - Total contracts created
- `get-max-batch-size()` - Current batch size limit

### Public Functions
- `register-farmer()` - Register as a farmer
- `create-crop-contract()` - List crop futures
- `create-batch-contracts()` - Create multiple contracts at once
- `purchase-contract()` - Buy crop futures  
- `purchase-batch-contracts()` - Purchase multiple contracts at once
- `confirm-delivery()` - Confirm crop delivery
- `dispute-delivery()` - Raise delivery dispute
- `resolve-dispute()` - Admin dispute resolution
- `cancel-contract()` - Cancel open contract
- `emergency-refund()` - Emergency buyer refund

## 🔒 Security Features

- ✅ Access control for sensitive operations
- ✅ Escrow protection for buyer payments
- ✅ Time-based contract validation
- ✅ Reputation-based farmer scoring
- ✅ Platform fee management
- ✅ Emergency refund mechanisms

## 🏗️ Architecture

```
Farmer → Register → Create Contract → Buyer Purchase → Escrow Lock
                                          ↓
                                    Delivery/Dispute
                                          ↓
                              Confirm → Release Payment
                              Dispute → Admin Resolution
```

## 🧪 Testing

```bash
npm install
npm test
```

## 📝 Error Codes

| Code | Description |
|------|-------------|
| u100 | Owner only operation |
| u101 | Contract not found |
| u102 | Unauthorized access |
| u103 | Insufficient funds |
| u104 | Contract expired |
| u105 | Already delivered |
| u106 | Invalid quantity |
| u107 | Invalid price |
| u108 | Already registered |
| u109 | Not registered |
| u110 | Batch limit exceeded |
| u111 | Batch empty |



## 📄 License

MIT License - see LICENSE file for details

---

*Built with 💚 for small farmers worldwide*

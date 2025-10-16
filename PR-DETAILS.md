Weather Insurance Module

## Overview
Added a comprehensive weather insurance system that allows farmers to purchase parametric insurance policies that automatically pay out based on verified weather events. This independent module integrates seamlessly with the existing crop futures platform without cross-contract dependencies.

## Technical Implementation

### Key Functions Added:
- `purchase-weather-insurance()` - Farmers can buy insurance with customizable coverage amounts, types, thresholds, and durations
- `record-weather-event()` - Admin function to record verified weather events with severity values
- `claim-weather-insurance()` - Automatic payout calculation based on weather event severity vs. policy threshold
- `cancel-weather-insurance()` - Early policy cancellation with 10% fee structure
- `get-farmer-active-policies-count()` - Query active insurance policies by farmer

### Data Structures Added:
- **weather-insurance-policies map**: Stores policy details including coverage amounts, premium rates, thresholds, and status
- **weather-events map**: Records verified weather events with severity metrics and timestamps
- **New data variables**: `insurance-policy-nonce`, `base-premium-rate` (5%), `max-coverage-amount` (10M micro-STX)

### Error Handling:
- Added 5 new error constants (u112-u115) for comprehensive insurance validation
- Proper Clarity v3 error constants and validation patterns

## Testing & Validation
- ✅ Contract passes clarinet check with Clarity v3 compliance
- ✅ All npm tests successful (existing test suite)
- ✅ CI/CD pipeline configured with GitHub Actions
- ✅ Proper line ending normalization (CRLF → LF)
- ✅ Independent feature implementation (no cross-contract calls)

## Value Proposition
This weather insurance module adds significant value by:
1. **Risk Mitigation**: Protects farmers against weather-related crop losses
2. **Automated Payouts**: Eliminates lengthy claim processes through parametric triggers
3. **Revenue Stream**: Platform earns insurance premiums alongside existing fees
4. **Farmer Retention**: Additional value-added service strengthens platform ecosystem
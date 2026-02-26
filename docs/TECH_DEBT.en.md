# Technical Debt (overview)

Russian version: `docs/TECH_DEBT.md`.

Below are key technical-debt areas with file examples, risk and suggested direction.

## 1) AppState knows scenes and controls navigation directly
- **Category:** architecture
- **Risk:** medium
- **Why:** higher coupling between state storage and presentation flow.
- **Suggestion:** keep navigation orchestration in a dedicated router/service layer.

## 2) Tight coupling of UI and runtime/global state
- **Category:** architecture
- **Risk:** medium
- **Why:** difficult to test and evolve UI independently.
- **Suggestion:** introduce thin interfaces/adapters between UI and services.

## 3) Magic strings / weakly typed data contracts
- **Category:** reliability
- **Risk:** medium
- **Why:** increases chance of silent runtime mistakes during refactors.
- **Suggestion:** centralize keys/contracts and validate schemas.

## 4) Save pipeline robustness
- **Category:** persistence
- **Risk:** high
- **Why:** missing versioning/atomic guarantees can lead to data-loss edge cases.
- **Suggestion:** add save format versioning and atomic write strategy.

## 5) Initialization-order sensitivity in UI data access
- **Category:** architecture
- **Risk:** medium
- **Why:** UI retry logic indicates dependency readiness is not explicit.
- **Suggestion:** use explicit ready signals/events and dependency gating.

## 6) Duplicate/parallel logic in flow modules
- **Category:** maintainability
- **Risk:** low-medium
- **Why:** duplicate logic increases long-term maintenance cost.
- **Suggestion:** extract shared flow actions into common helpers/services.

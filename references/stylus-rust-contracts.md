# Stylus Rust Contracts

## Prerequisites

- Rust 1.88+ (pin in `rust-toolchain.toml`)
- `wasm32-unknown-unknown` target: `rustup target add wasm32-unknown-unknown`
- `cargo-stylus` CLI: `cargo install --force cargo-stylus`
- Docker (required for `cargo stylus check` and `deploy`)

## Project Setup

```bash
cargo stylus new my-contract
cd my-contract
```

This generates a counter contract template with `Cargo.toml` pre-configured for Stylus.

## Cargo.toml

```toml
[dependencies]
stylus-sdk = "0.10"
alloy-primitives = "1.3"
alloy-sol-types = "1.3"

[dev-dependencies]
stylus-sdk = { version = "0.10", features = ["stylus-test"] }

[features]
export-abi = ["stylus-sdk/export-abi"]
```

## Workspace Configuration (v0.10)

Multi-contract workspaces need a root `Stylus.toml`:

```toml
[workspace]
[workspace.networks]
```

Each contract also gets its own `Stylus.toml`:

```toml
[contract]
```

## Storage

v0.10 uses the `#[storage]` attribute instead of the old `sol_storage!` macro (though `sol_storage!` still compiles in v0.10, `#[storage]` is the recommended pattern):

```rust
use stylus_sdk::prelude::*;
use stylus_sdk::storage::{StorageAddress, StorageU256, StorageMap, StorageBool};
use alloy_primitives::{Address, U256};

#[storage]
#[entrypoint]
pub struct Counter {
    owner: StorageAddress,
    number: StorageU256,
    approved: StorageMap<Address, StorageBool>,
}
```

**Important:** Concrete storage types (`StorageU256`, `StorageAddress`, `StorageMap`, `StorageVec`, etc.) live in `stylus_sdk::storage::*`, NOT the prelude. The prelude only exports the traits (`Erase`, `SimpleStorageType`, `StorageType`).

### Supported Storage Types

- `StorageU256`, `StorageU128`, `StorageU64`, `StorageU32`, `StorageU16`, `StorageU8`
- `StorageI256`, `StorageI128`, `StorageI64`, `StorageI32`, `StorageI16`, `StorageI8`
- `StorageBool`, `StorageAddress`, `StorageB256`
- `StorageString`, `StorageBytes`
- `StorageMap<K, V>` — Solidity-compatible mapping
- `StorageVec<T>` — dynamic array
- Nested maps: `StorageMap<U256, StorageMap<Address, StorageBool>>`

### Storage Access

```rust
// Read
let value = self.number.get();

// Write
self.number.set(value + U256::from(1));

// Maps
let is_approved = self.approved.get(addr);
let mut setter = self.approved.setter(addr);
setter.set(true);
```

## Public Methods

Use `#[public]` to expose methods via the ABI:

```rust
#[public]
impl Counter {
    pub fn number(&self) -> U256 {
        self.number.get()
    }

    pub fn set_number(&mut self, new_number: U256) {
        self.number.set(new_number);
    }

    pub fn increment(&mut self) {
        let number = self.number.get();
        self.number.set(number + U256::from(1));
    }
}
```

## Payable Methods

```rust
#[payable]
pub fn deposit(&mut self) {
    let value = self.vm().msg_value();
    // handle deposit
}
```

## Events

v0.10 uses `self.vm().log()` instead of `evm::log()`:

```rust
use alloy_sol_types::sol;

sol! {
    event Transfer(address indexed from, address indexed to, uint256 value);
}

// Emit in a method
self.vm().log(Transfer {
    from: caller,
    to: recipient,
    value: amount,
});
```

## Cross-Contract Calls (v0.10 Trait Pattern)

### Define the Interface on the Callee

```rust
// In voter-registry crate
#[public]
pub trait IVoterRegistry {
    fn is_registered(&self, voter: Address) -> bool;
    fn voter_count(&self) -> U256;
}
```

### Implement with `#[implements]`

```rust
#[public]
#[implements(IVoterRegistry)]
impl VoterRegistry {
    pub fn register(&mut self) -> Result<(), RegistryError> { /* ... */ }
}

#[public]
impl IVoterRegistry for VoterRegistry {
    fn is_registered(&self, voter: Address) -> bool {
        self.registered_voters.get(voter)
    }

    fn voter_count(&self) -> U256 {
        self.voter_count.get()
    }
}
```

### Enable Client Generation in Cargo.toml

Callee crate:

```toml
[features]
contract-client-gen = []
```

Caller crate:

```toml
[dependencies]
voter-registry = { path = "../voter-registry", features = ["contract-client-gen"] }
```

### Call from the Caller

Generated methods from traits/interfaces always take `(host, call_context, ...solidity_params)`. Choose the right `Call` variant:

- `Call::new()` — for view/pure (read-only) calls
- `Call::new_mutating(&mut self)` — for state-changing calls
- `Call::new_payable(&mut self, value)` — for payable calls

```rust
use voter_registry::{VoterRegistry, IVoterRegistry};
use stylus_sdk::call::Call;

// View call (read-only)
let registry = VoterRegistry::new(registry_addr);
let is_registered: bool = registry
    .is_registered(self.vm(), Call::new(), voter)
    .expect("Cross-contract call failed");

// Mutating call: bind Call BEFORE self.vm() to avoid borrow checker conflicts
let token = IToken::new(token_addr);
let call = Call::new_mutating(self);
let result = token.transfer(self.vm(), call, recipient, amount)?;
```

**Borrow checker note:** `Call::new_mutating(self)` takes `&mut self`, and `self.vm()` takes `&self`. If you put both in the same expression, the compiler will complain about conflicting borrows. Always bind the `Call` to a variable first.

### Testing with Feature Unification

`contract-client-gen` changes method signatures, so callee tests need isolation:

```bash
# Polls tests (pulls in voter-registry with client gen)
cargo test

# Voter-registry tests separately
cargo test -p voter-registry --no-default-features --features stylus-sdk/stylus-test
```

## Low-Level Calls: RawCall and RawDeploy

For direct EVM calls and contract deployment without typed interfaces:

### RawCall

```rust
use stylus_sdk::call::RawCall;

// Basic call
let result = unsafe { RawCall::new(self.vm()).call(target, &data) };

// Call with ETH value (value passed in constructor, not chained)
let result = unsafe {
    RawCall::new_with_value(self.vm(), amount)
        .call(target, &data)
};

// Static call (read-only)
let result = unsafe { RawCall::new_static(self.vm()).call(target, &data) };

// Delegate call
let result = unsafe { RawCall::new_delegate(self.vm()).call(target, &data) };
```

### RawDeploy

```rust
use stylus_sdk::deploy::RawDeploy;
use stylus_sdk::alloy_primitives::B256;

// Deploy with CREATE2 (salt-based deterministic address)
let addr = unsafe {
    RawDeploy::new()
        .salt(B256::ZERO)
        .deploy(self.vm(), &bytecode, endowment)
};
```

Note: `RawDeploy::new()` takes no arguments. The host/vm is passed at `.deploy()` time, and the endowment (ETH value) is also passed to `.deploy()`, not via a `.value()` chain method.

## Error Handling

```rust
#[derive(SolidityError)]
pub enum MyError {
    InsufficientBalance(InsufficientBalance),
    Unauthorized(Unauthorized),
}

sol! {
    error InsufficientBalance(uint256 available, uint256 required);
    error Unauthorized(address caller);
}
```

Return `Result<T, MyError>` from public methods.

## Validation and Deployment

```bash
# Check contract compiles and is valid for Stylus
cargo stylus check --endpoint http://localhost:8547

# Estimate deployment gas
cargo stylus deploy --endpoint http://localhost:8547 \
  --private-key 0x... --estimate-gas

# Deploy
cargo stylus deploy --endpoint http://localhost:8547 \
  --private-key 0x...

# Export Solidity ABI
cargo stylus export-abi
```

## Testing

The `stylus-test` feature provides `TestVM` for simulating the Stylus execution environment. See `references/testing.md` for full details.

```rust
#[cfg(test)]
mod tests {
    use super::*;
    use stylus_sdk::testing::*;

    #[test]
    fn test_increment() {
        let vm = TestVM::default();
        let mut contract = Counter::from(&vm);
        contract.set_number(U256::from(0));
        contract.increment();
        assert_eq!(contract.number(), U256::from(1));
    }
}
```

Run with `cargo test`. The `stylus-test` feature enables `TestVM` for simulating transaction context, `self.vm().msg_sender()`, `self.vm().msg_value()`, block info, and storage operations without deployment.

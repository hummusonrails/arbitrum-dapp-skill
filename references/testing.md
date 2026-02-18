# Testing

## Stylus Rust Testing

### Unit tests with stylus-test

Add the test feature to `Cargo.toml`. The `stylus-test` feature enables `stylus_sdk::testing::*` which provides `TestVM` and `TestVMBuilder`:

```toml
[dev-dependencies]
stylus-sdk = { version = "0.10", features = ["stylus-test"] }
```

### Basic test with TestVM

Always create a `TestVM` instance and initialize contracts with `::from(&vm)`:

```rust
#[cfg(test)]
mod tests {
    use super::*;
    use stylus_sdk::testing::*;

    #[test]
    fn test_counter_operations() {
        let vm = TestVM::default();
        let mut contract = Counter::from(&vm);

        // Initial state
        assert_eq!(contract.number(), U256::from(0));

        // Set and read
        contract.set_number(U256::from(42));
        assert_eq!(contract.number(), U256::from(42));

        // Increment
        contract.increment();
        assert_eq!(contract.number(), U256::from(43));
    }
}
```

### TestVM configuration with builder

Use `TestVMBuilder` for custom transaction context (sender, value, contract address):

```rust
#[cfg(test)]
mod tests {
    use super::*;
    use stylus_sdk::testing::*;
    use alloy_primitives::address;

    #[test]
    fn test_with_custom_context() {
        let vm: TestVM = TestVMBuilder::new()
            .sender(address!("f39Fd6e51aad88F6F4ce6aB8827279cffFb92266"))
            .contract_address(address!("5FbDB2315678afecb367f032d93F642f64180aa3"))
            .value(U256::from(1_000_000))
            .build();

        let mut contract = Counter::from(&vm);

        // self.vm().msg_sender() will return the configured sender
        // self.vm().msg_value() will return 1_000_000
        contract.increment();
        assert_eq!(contract.number(), U256::from(1));
    }
}
```

### Manipulating block state

```rust
// Set block timestamp (useful for time-dependent logic)
vm.set_block_timestamp(1_700_000_000);

// Set block number
vm.set_block_number(12345678);

// Advance timestamp relatively
vm.set_block_timestamp(vm.block_timestamp() + 60);
```

### Mocking external calls

```rust
let external_contract = address!("8626f6940E2eb28930eFb4CeF49B2d1F2C9C1199");
let call_data = vec![0xab, 0xcd, 0xef];
let expected_response = vec![0x12, 0x34, 0x56];

vm.mock_call(external_contract, call_data, Ok(expected_response));
```

### Verifying emitted events

```rust
// After calling a method that emits events
let logs = vm.get_emitted_logs();
assert_eq!(logs.len(), 1);

// logs[i].0 = topics (Vec<B256>), logs[i].1 = data (Vec<u8>)
// First topic is always the event signature hash
```

### VM state snapshots

```rust
let snapshot = vm.snapshot();
assert_eq!(snapshot.chain_id, 42161); // Arbitrum One default
assert_eq!(snapshot.msg_value, U256::from(1));
```

### Running Stylus tests

```bash
cargo test
cargo test -- --nocapture    # with println! output
cargo test test_name         # run specific test
```

## Solidity Testing with Foundry

### Basic test

```solidity
// test/Counter.t.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "../src/Counter.sol";

contract CounterTest is Test {
    Counter public counter;

    function setUp() public {
        counter = new Counter();
    }

    function test_InitialValue() public view {
        assertEq(counter.number(), 0);
    }

    function test_SetNumber() public {
        counter.setNumber(42);
        assertEq(counter.number(), 42);
    }

    function test_Increment() public {
        counter.setNumber(0);
        counter.increment();
        assertEq(counter.number(), 1);
    }
}
```

### Fuzz testing

```solidity
function testFuzz_SetNumber(uint256 x) public {
    counter.setNumber(x);
    assertEq(counter.number(), x);
}
```

### Testing with cheatcodes

```solidity
function test_OnlyOwner() public {
    // Impersonate a different address
    vm.prank(address(0xdead));
    vm.expectRevert("Unauthorized");
    counter.setNumber(999);
}

function test_WithValue() public {
    // Send ETH with call
    vm.deal(address(this), 1 ether);
    payableContract.deposit{value: 1 ether}();
}

function test_EventEmission() public {
    vm.expectEmit(true, true, false, true);
    emit NumberSet(42);
    counter.setNumber(42);
}
```

### Running Solidity tests

```bash
forge test                    # run all tests
forge test -vvvv              # verbose with full traces
forge test --match-test test_Increment   # specific test
forge test --match-contract CounterTest  # specific contract
forge test --gas-report       # with gas usage report
forge test --fork-url $ARBITRUM_SEPOLIA_RPC_URL  # fork testing
```

## Integration Testing

### Testing Stylus + Solidity interop

Deploy both contracts to the local devnode and test cross-contract calls:

```bash
# 1. Start devnode
cd apps/nitro-devnode && ./run-dev-node.sh

# 2. Deploy Stylus contract
cd apps/contracts-stylus
cargo stylus deploy --endpoint http://localhost:8547 \
  --private-key 0xb6b15c8cb491557369f3c7d2c287b053eb229daa9c22138887752191c9520659
# Note the deployed address

# 3. Deploy Solidity contract (passing Stylus address as constructor arg if needed)
cd apps/contracts-solidity
forge script script/Deploy.s.sol --rpc-url http://localhost:8547 \
  --broadcast --private-key 0xb6b15c8cb491557369f3c7d2c287b053eb229daa9c22138887752191c9520659

# 4. Test interactions via cast
cast call --rpc-url http://localhost:8547 $STYLUS_ADDRESS "number()(uint256)"
cast send --rpc-url http://localhost:8547 \
  --private-key 0xb6b15c8cb491557369f3c7d2c287b053eb229daa9c22138887752191c9520659 \
  $STYLUS_ADDRESS "increment()"
```

## Coverage

### Solidity

```bash
forge coverage
forge coverage --report lcov  # for IDE integration
```

### Stylus

Stylus unit tests compile for the native host target (not WASM), so standard Rust coverage tools work. `cargo tarpaulin` requires Linux — on macOS, use LLVM source-based coverage instead:

```bash
# Linux
cargo tarpaulin --out Html

# macOS / cross-platform (LLVM source-based coverage)
RUSTFLAGS="-C instrument-coverage" cargo test
grcov . -s . --binary-path ./target/debug/ -t html --branch -o ./coverage/
```

## Test Strategy Recommendations

1. **Unit tests** — test individual contract functions in isolation (both Rust and Solidity)
2. **Fuzz tests** — use Foundry fuzz testing for Solidity; proptest or quickcheck for Rust
3. **Integration tests** — deploy to local devnode and test cross-contract interactions
4. **Fork tests** — use `forge test --fork-url` to test against real testnet state
5. **Frontend tests** — mock viem clients for component testing

# arbitrum-dapp-skill

A [Claude Code skill](https://github.com/anthropics/skills) for building dApps on Arbitrum with Stylus (Rust) and Solidity.

## What it does

This skill gives Claude Code deep knowledge of the Arbitrum development stack so it can help you:

- Scaffold a monorepo with Stylus Rust contracts, Solidity contracts, and a React frontend
- Write and test smart contracts using the Stylus Rust SDK or Foundry
- Set up a local Arbitrum devnode for development
- Build frontend interfaces with viem and wagmi
- Deploy contracts to Arbitrum Sepolia and Arbitrum One
- Handle cross-language contract interop (Stylus ↔ Solidity)

## Install

```bash
bash <(curl -s https://raw.githubusercontent.com/hummusonrails/arbitrum-dapp-skill/main/install.sh)
```

Or clone manually:

```bash
git clone https://github.com/hummusonrails/arbitrum-dapp-skill.git ~/.claude/skills/arbitrum-dapp
```

## Prerequisites

The skill will guide you through installing these, but for reference:

- [Rust](https://rustup.rs/) 1.81+
- [cargo-stylus](https://github.com/OffchainLabs/stylus-sdk-rs): `cargo install --force cargo-stylus`
- [Foundry](https://book.getfoundry.sh/getting-started/installation): `curl -L https://foundry.paradigm.xyz | bash && foundryup`
- [Docker](https://www.docker.com/products/docker-desktop/) for the local devnode
- [Node.js](https://nodejs.org/) 20+ and [pnpm](https://pnpm.io/)

## Stack

| Layer | Tool |
|-------|------|
| Smart contracts (Rust) | Stylus SDK v0.10+ |
| Smart contracts (Solidity) | Solidity 0.8.x + Foundry |
| Local chain | nitro-devnode |
| Frontend | React / Next.js + viem + wagmi |
| Package manager | pnpm |

## Skill structure

```
arbitrum-dapp-skill/
├── SKILL.md                            # Main skill definition
├── references/
│   ├── stylus-rust-contracts.md        # Stylus SDK patterns and examples
│   ├── solidity-contracts.md           # Solidity on Arbitrum + Foundry
│   ├── frontend-integration.md         # viem + wagmi patterns
│   ├── local-devnode.md                # Nitro devnode setup
│   ├── deployment.md                   # Testnet and mainnet deployment
│   └── testing.md                      # Testing strategies
├── install.sh
└── README.md
```

## Usage

Once installed, start a Claude Code session and ask things like:

- "Help me create a new Arbitrum dApp"
- "Write a Stylus contract that implements an ERC-20 token"
- "Set up my local devnode and deploy my contract"
- "Add a frontend that reads from my deployed contract"
- "Help me write tests for my Stylus contract"

## Resources

- [Arbitrum Stylus Quickstart](https://docs.arbitrum.io/stylus/quickstart)
- [Stylus SDK](https://github.com/OffchainLabs/stylus-sdk-rs)
- [Stylus Workshop (Game of Life)](https://github.com/ArbitrumFoundation/stylus-workshop-gol)
- [Nitro Devnode](https://github.com/OffchainLabs/nitro-devnode)
- [viem Documentation](https://viem.sh)
- [wagmi Documentation](https://wagmi.sh)

## Contributing

Contributions welcome. Open an issue or PR.

## License

[MIT](LICENSE)

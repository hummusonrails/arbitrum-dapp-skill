# Frontend Integration (viem + wagmi)

All chain interaction uses viem directly or wagmi hooks.

## Dependencies

```bash
pnpm add viem wagmi @tanstack/react-query
# wagmi v3 made connector packages optional peer deps — install only what you use:
pnpm add @metamask/connect-evm   # if you want MetaMask
# pnpm add @reown/walletconnect-evm     # WalletConnect via Reown
# pnpm add @coinbase/wallet-sdk         # Coinbase Wallet
```

> **Version baseline:** This guide targets `viem ^2`, `wagmi ^3`, `@tanstack/react-query ^5`, Next.js `^16`, and TypeScript `>=5.9.3`. wagmi v3 renamed several hooks and switched mutation hooks to TanStack Query's `.mutate()` API; if you are migrating from wagmi v2, see the [v2 to v3 migration guide](https://wagmi.sh/react/guides/migrate-from-v2-to-v3).

## Chain Configuration

### Local devnode

```typescript
import { defineChain } from "viem";

export const arbitrumLocal = defineChain({
  id: 412346,
  name: "Arbitrum Local",
  nativeCurrency: { name: "Ether", symbol: "ETH", decimals: 18 },
  rpcUrls: {
    default: { http: ["/api/rpc"] },
  },
});
```

The local devnode RPC URL points to `/api/rpc` (a Next.js API route proxy) rather than `http://localhost:8547` directly, to avoid CORS issues. See the CORS proxy section below.

### Testnets and mainnet

```typescript
import { arbitrumSepolia, arbitrum } from "viem/chains";
```

viem ships with built-in chain definitions for `arbitrum` (One) and `arbitrumSepolia`.

## wagmi Config

**Important:** Always pass explicit URLs to `http()`. Calling `http()` with no argument does not reliably resolve custom chain RPC URLs from `defineChain` — requests will silently fail.

```typescript
import { http, createConfig, createStorage, cookieStorage } from "wagmi";
import { arbitrum, arbitrumSepolia } from "wagmi/chains";
import { injected, walletConnect } from "wagmi/connectors";
import { arbitrumLocal } from "./chains";

export const config = createConfig({
  chains: [arbitrum, arbitrumSepolia, arbitrumLocal],
  connectors: [
    injected(),
    walletConnect({ projectId: process.env.NEXT_PUBLIC_WC_PROJECT_ID! }),
  ],
  transports: {
    [arbitrum.id]: http("https://arb1.arbitrum.io/rpc"),
    [arbitrumSepolia.id]: http("https://sepolia-rollup.arbitrum.io/rpc"),
    [arbitrumLocal.id]: http("/api/rpc"),
  },
  ssr: true,
  storage: createStorage({ storage: cookieStorage }),
});

declare module "wagmi" {
  interface Register {
    config: typeof config;
  }
}
```

The `declare module "wagmi"` block gives you full type inference for your configured chains across all wagmi hooks. `ssr: true` plus `cookieStorage` lets wagmi rehydrate the connection state from a cookie on the server, which is the recommended Next.js App Router pattern (see the Hydration section below for why this beats the older `useMounted` workaround).

> **Note:** WalletConnect project IDs are now issued at [dashboard.reown.com](https://dashboard.reown.com) (the old `cloud.walletconnect.com` dashboard now redirects to Reown). The `walletConnect()` connector from `wagmi/connectors` still works; for a fuller modal UX, consider [`@reown/appkit-adapter-wagmi`](https://docs.reown.com/appkit/next/core/installation).

### CORS proxy for local devnode

The nitro-devnode doesn't set CORS headers, so browser requests from `localhost:3000` to `localhost:8547` will fail. Use a Next.js API route as a proxy:

```typescript
// src/app/api/rpc/route.ts
import { NextResponse } from "next/server";

const DEVNODE_RPC = process.env.DEVNODE_RPC_URL ?? "http://localhost:8547";

export async function POST(request: Request) {
  const body = await request.json();
  const res = await fetch(DEVNODE_RPC, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });
  const data = await res.json();
  return NextResponse.json(data);
}
```

## Provider Setup (Next.js App Router)

```typescript
// components/providers.tsx
"use client";

import { useState, type ReactNode } from "react";
import { WagmiProvider, type State } from "wagmi";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { config } from "@/config/wagmi";

export function Providers({
  children,
  initialState,
}: {
  children: ReactNode;
  initialState?: State;
}) {
  const [queryClient] = useState(() => new QueryClient());

  return (
    <WagmiProvider config={config} initialState={initialState}>
      <QueryClientProvider client={queryClient}>
        {children}
      </QueryClientProvider>
    </WagmiProvider>
  );
}
```

Wrap in `layout.tsx`, hydrating wagmi from the request cookie:

```typescript
// app/layout.tsx
import { headers } from "next/headers";
import { cookieToInitialState } from "wagmi";
import { config } from "@/config/wagmi";
import { Providers } from "@/components/providers";

export default async function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  const initialState = cookieToInitialState(
    config,
    (await headers()).get("cookie"),
  );

  return (
    <html lang="en">
      <body>
        <Providers initialState={initialState}>{children}</Providers>
      </body>
    </html>
  );
}
```

## Hydration Safety

With `ssr: true` + `cookieStorage` + `cookieToInitialState` (above), wagmi's account state is consistent between the server render and the client hydration, so most components no longer need a `useMounted` workaround. Use the cookie-based pattern in new code.

If you do hit a hook whose value is genuinely browser-only (e.g. reading `window.ethereum` directly), the small `useMounted` hook is still a fine escape hatch:

```typescript
import { useState, useEffect } from "react";

export function useMounted() {
  const [mounted, setMounted] = useState(false);
  useEffect(() => setMounted(true), []);
  return mounted;
}
```

```typescript
"use client";

import { useConnection } from "wagmi"; // wagmi v3: useAccount was renamed to useConnection

export function WalletInfo() {
  const { address, isConnected } = useConnection();

  if (!isConnected) return <button>Connect Wallet</button>;
  return <span>{address}</span>;
}
```

## Contract Addresses from Env Vars

Never hardcode contract addresses. Use environment variables so the same frontend works across local, testnet, and mainnet:

```typescript
import type { Address } from "viem";

export const COUNTER_ADDRESS = (process.env
  .NEXT_PUBLIC_COUNTER_ADDRESS ?? "0x") as Address;
```

## Reading Contract State

### With wagmi hooks

```typescript
import { useReadContract } from "wagmi";
import { counterAbi } from "./abi";

function CounterDisplay({ address }: { address: `0x${string}` }) {
  const { data: count, isLoading } = useReadContract({
    address,
    abi: counterAbi,
    functionName: "number",
  });

  if (isLoading) return <span>Loading...</span>;
  return <span>{count?.toString()}</span>;
}
```

### Conditional reads

Only fetch when a prerequisite value is available:

```typescript
const { data: balance } = useReadContract({
  address: COUNTER_ADDRESS,
  abi: counterAbi,
  functionName: "balanceOf",
  args: userAddress ? [userAddress] : undefined,
  query: { enabled: !!userAddress },
});
```

### With viem directly

```typescript
import { createPublicClient, http } from "viem";
import { arbitrumSepolia } from "viem/chains";

const publicClient = createPublicClient({
  chain: arbitrumSepolia,
  transport: http("https://sepolia-rollup.arbitrum.io/rpc"),
});

const count = await publicClient.readContract({
  address: "0x...",
  abi: counterAbi,
  functionName: "number",
});
```

## Writing to Contracts

In wagmi v3, mutation hooks like `useWriteContract` follow the TanStack Query mutation API: instead of returning a named function, they expose `.mutate(args)` and `.mutateAsync(args)`. Plan the examples below around that shape.

### Custom hook pattern

Wrap `useWriteContract` + `useWaitForTransactionReceipt` in a reusable hook per contract action. This keeps components clean and makes tx lifecycle easy to track:

```typescript
import { useWriteContract, useWaitForTransactionReceipt } from "wagmi";

export function useIncrement() {
  const writeContract = useWriteContract();
  const hash = writeContract.data;

  const { isLoading: isConfirming, isSuccess } = useWaitForTransactionReceipt({
    hash,
  });

  function increment(address: `0x${string}`) {
    writeContract.mutate({
      address,
      abi: counterAbi,
      functionName: "increment",
    });
  }

  return {
    increment,
    hash,
    isPending: writeContract.isPending,
    isConfirming,
    isSuccess,
    error: writeContract.error,
    reset: writeContract.reset,
  };
}
```

### Inline component pattern

For simpler cases, inline the hooks directly:

```typescript
function IncrementButton({ address }: { address: `0x${string}` }) {
  const writeContract = useWriteContract();

  const { isLoading: isConfirming, isSuccess } = useWaitForTransactionReceipt({
    hash: writeContract.data,
  });

  return (
    <div>
      <button
        disabled={writeContract.isPending || isConfirming}
        onClick={() =>
          writeContract.mutate({
            address,
            abi: counterAbi,
            functionName: "increment",
          })
        }
      >
        {writeContract.isPending ? "Confirming..." : "Increment"}
      </button>
      {isSuccess && <p>Transaction confirmed.</p>}
    </div>
  );
}
```

### Refetch after tx confirmation

When a write changes on-chain state, refetch any related reads:

```typescript
const { refetch } = useReadContract({ /* ... */ });
const { isSuccess } = useIncrement();

useEffect(() => {
  if (isSuccess) refetch();
}, [isSuccess, refetch]);
```

### With viem wallet client

```typescript
import { createWalletClient, custom } from "viem";
import { arbitrumSepolia } from "viem/chains";

const walletClient = createWalletClient({
  chain: arbitrumSepolia,
  transport: custom(window.ethereum!),
});

const hash = await walletClient.writeContract({
  address: "0x...",
  abi: counterAbi,
  functionName: "increment",
  account: "0x...",
});
```

## Watching Events

```typescript
import { useWatchContractEvent } from "wagmi";

useWatchContractEvent({
  address: "0x...",
  abi: counterAbi,
  eventName: "NumberSet",
  onLogs(logs) {
    console.log("New event:", logs);
  },
});
```

## ABI Management

Keep ABIs in a shared location both contract workspaces can export to:

```
apps/
├── frontend/src/abi/
│   ├── Counter.ts          # Stylus contract ABI (from cargo stylus export-abi)
│   └── SolidityCounter.ts  # Solidity ABI (from forge inspect)
```

### Typed ABI pattern

```typescript
export const counterAbi = [
  {
    type: "function",
    name: "number",
    inputs: [],
    outputs: [{ type: "uint256" }],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "increment",
    inputs: [],
    outputs: [],
    stateMutability: "nonpayable",
  },
  {
    type: "function",
    name: "setNumber",
    inputs: [{ name: "newNumber", type: "uint256" }],
    outputs: [],
    stateMutability: "nonpayable",
  },
  {
    type: "event",
    name: "NumberSet",
    inputs: [{ name: "newNumber", type: "uint256", indexed: false }],
  },
] as const;
```

`as const` gives full type inference with wagmi and viem. Stylus generates camelCase selectors (`increment`, `setNumber`, etc.).

## Error Handling

### Parsing contract errors for UI

A simple helper to turn contract errors into user-friendly messages:

```typescript
function parseContractError(error: Error): string {
  const msg = error.message ?? String(error);
  if (msg.includes("User rejected")) return "Transaction rejected.";
  if (msg.includes("InsufficientBalance")) return "Insufficient balance.";
  // Add your contract's custom error names here
  return msg.length > 200 ? msg.slice(0, 200) + "..." : msg;
}
```

### With viem error types

For structured error handling, use viem's error walking. With wagmi v3, use `mutateAsync` so you can `await` and catch in one place:

```typescript
import { BaseError, ContractFunctionRevertedError } from "viem";
import { useWriteContract } from "wagmi";

const writeContract = useWriteContract();

try {
  await writeContract.mutateAsync({ /* ... */ });
} catch (err) {
  if (err instanceof BaseError) {
    const revertError = err.walk(
      (e) => e instanceof ContractFunctionRevertedError
    );
    if (revertError instanceof ContractFunctionRevertedError) {
      const errorName = revertError.data?.errorName;
      // Handle specific contract errors by name
    }
  }
}
```

## Transaction Status Pattern

A reusable type for tracking transaction lifecycle in UI components:

```typescript
type TxState =
  | { status: "idle" }
  | { status: "pending"; message?: string }
  | { status: "confirming"; hash: string }
  | { status: "success"; hash: string }
  | { status: "error"; message: string };
```

Derive state from hook returns:

```typescript
const txState: TxState = useMemo(() => {
  if (isPending) return { status: "pending" };
  if (isConfirming && hash) return { status: "confirming", hash };
  if (error) return { status: "error", message: parseContractError(error) };
  if (isSuccess && hash) return { status: "success", hash };
  return { status: "idle" };
}, [isPending, isConfirming, isSuccess, hash, error]);
```

Use this to drive loading spinners, success toasts, error alerts, and block explorer links in a consistent way across your app.

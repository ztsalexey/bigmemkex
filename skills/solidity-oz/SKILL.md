# Solidity & OpenZeppelin Development Skill

Expert Solidity smart contract development using OpenZeppelin Contracts v5.x, Foundry, and security-first patterns. Use when writing, reviewing, auditing, or deploying smart contracts on EVM chains.

## When to Use

- Writing smart contracts (ERC-20, ERC-721, ERC-1155, Governor, etc.)
- Auditing contracts for vulnerabilities
- Using OpenZeppelin libraries
- Foundry or Hardhat project setup
- Gas optimization
- Contract upgrades (proxy patterns)
- DeFi protocol development

## OpenZeppelin Contracts v5.x

### Key Changes from v4 → v5
- Removed `SafeMath` (Solidity 0.8+ has built-in overflow checks)
- `Ownable` now requires constructor arg: `Ownable(initialOwner)`
- `ERC20`, `ERC721`, `ERC1155` constructors simplified
- Upgradeable variants no longer needed for libraries/interfaces
- `ReentrancyGuard` moved to `utils/ReentrancyGuard.sol`
- Access control: prefer `AccessControl` over `Ownable` for complex roles
- Namespace storage for upgradeable contracts (ERC-7201)

### Import Patterns (v5)
```solidity
// Token standards
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";

// Access control
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";

// Security
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

// Utilities
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/utils/Address.sol";

// Proxy/Upgradeable
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
```

### ERC-20 Template (v5)
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

contract MyToken is ERC20, ERC20Burnable, ERC20Permit, Ownable, Pausable {
    constructor(address initialOwner)
        ERC20("MyToken", "MTK")
        ERC20Permit("MyToken")
        Ownable(initialOwner)
    {
        _mint(initialOwner, 1_000_000 * 10 ** decimals());
    }

    function mint(address to, uint256 amount) public onlyOwner {
        _mint(to, amount);
    }

    function pause() public onlyOwner { _pause(); }
    function unpause() public onlyOwner { _unpause(); }

    function _update(address from, address to, uint256 value)
        internal override
    {
        require(!paused(), "Token transfers paused");
        super._update(from, to, value);
    }
}
```

### ERC-721 Template (v5)
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Burnable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract MyNFT is ERC721, ERC721URIStorage, ERC721Burnable, Ownable {
    uint256 private _nextTokenId;

    constructor(address initialOwner)
        ERC721("MyNFT", "MNFT")
        Ownable(initialOwner)
    {}

    function safeMint(address to, string memory uri) public onlyOwner {
        uint256 tokenId = _nextTokenId++;
        _safeMint(to, tokenId);
        _setTokenURI(tokenId, uri);
    }

    // Required overrides
    function tokenURI(uint256 tokenId) public view override(ERC721, ERC721URIStorage) returns (string memory) {
        return super.tokenURI(tokenId);
    }

    function supportsInterface(bytes4 interfaceId) public view override(ERC721, ERC721URIStorage) returns (bool) {
        return super.supportsInterface(interfaceId);
    }
}
```

## Security Patterns (MANDATORY)

### Checks-Effects-Interactions (CEI)
```solidity
function withdraw(uint256 amount) public {
    // 1. CHECKS
    require(amount <= balances[msg.sender], "Insufficient");
    require(amount > 0, "Zero amount");

    // 2. EFFECTS (state changes BEFORE external calls)
    balances[msg.sender] -= amount;

    // 3. INTERACTIONS (external calls LAST)
    (bool success, ) = msg.sender.call{value: amount}("");
    require(success, "Transfer failed");
}
```

### ReentrancyGuard
```solidity
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract Vault is ReentrancyGuard {
    function withdraw() public nonReentrant {
        // Safe from reentrancy
    }
}
```

### Access Control (Role-Based)
```solidity
import "@openzeppelin/contracts/access/AccessControl.sol";

contract MyContract is AccessControl {
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    constructor(address admin) {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(MINTER_ROLE, admin);
    }
}
```

### Input Validation Checklist
- `address != address(0)` for all address params
- `amount > 0` for value transfers
- Array length checks (prevent gas DoS)
- `msg.sender` not `tx.origin` for auth
- Check return values of all external calls

### Common Vulnerabilities
1. **Reentrancy** — Use CEI + ReentrancyGuard
2. **Front-running** — Commit-reveal or use private mempools
3. **Integer overflow** — Solidity 0.8+ handles this (use `unchecked` carefully)
4. **Access control** — Never leave admin functions public
5. **Delegatecall to untrusted** — Can hijack storage
6. **tx.origin auth** — Phishable, use msg.sender
7. **Floating pragma** — Pin exact version: `pragma solidity 0.8.20;`
8. **Unchecked return values** — Always check `.call()` returns
9. **Storage collisions** — Use ERC-7201 namespaced storage for upgradeable
10. **Flash loan attacks** — Validate state across transactions

## Gas Optimization

```solidity
// Pack storage (same slot)
uint128 a; uint64 b; uint64 c; // 1 slot

// Use calldata for read-only arrays
function process(uint256[] calldata data) external { }

// Cache storage reads
uint256 cached = storageVar;
for (uint256 i; i < cached; ) {
    unchecked { ++i; }
}

// Use custom errors (cheaper than require strings)
error InsufficientBalance(uint256 available, uint256 required);

// Use events for historical data (not storage)
// Use immutable for constructor-set values
// Use constants for compile-time values
```

## Foundry Project Setup

```bash
# New project
forge init my-project
cd my-project

# Install OpenZeppelin
forge install OpenZeppelin/openzeppelin-contracts

# remappings.txt
echo '@openzeppelin/=lib/openzeppelin-contracts/' > remappings.txt

# Build & test
forge build
forge test -vvv

# Deploy
forge script script/Deploy.s.sol --rpc-url $RPC_URL --broadcast --verify

# Gas report
forge test --gas-report
```

### Foundry Test Pattern
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/MyToken.sol";

contract MyTokenTest is Test {
    MyToken token;
    address owner = makeAddr("owner");
    address user = makeAddr("user");

    function setUp() public {
        vm.prank(owner);
        token = new MyToken(owner);
    }

    function test_Mint() public {
        vm.prank(owner);
        token.mint(user, 100e18);
        assertEq(token.balanceOf(user), 100e18);
    }

    function testFail_MintUnauthorized() public {
        vm.prank(user);
        token.mint(user, 100e18); // Should revert
    }

    function testFuzz_Transfer(uint256 amount) public {
        amount = bound(amount, 1, token.balanceOf(owner));
        vm.prank(owner);
        token.transfer(user, amount);
        assertEq(token.balanceOf(user), amount);
    }
}
```

## Upgradeable Contracts (UUPS)

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

contract MyTokenV1 is Initializable, ERC20Upgradeable, OwnableUpgradeable, UUPSUpgradeable {
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address initialOwner) public initializer {
        __ERC20_init("MyToken", "MTK");
        __Ownable_init(initialOwner);
        __UUPSUpgradeable_init();
        _mint(initialOwner, 1_000_000 * 10 ** decimals());
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
}
```

## Audit Preparation Checklist

- [ ] All functions have NatSpec documentation
- [ ] CEI pattern followed everywhere
- [ ] ReentrancyGuard on all external-facing state-changing functions
- [ ] Access control on all admin functions
- [ ] Input validation on all public/external functions
- [ ] Events emitted for all state changes
- [ ] No floating pragma
- [ ] No `tx.origin` authentication
- [ ] All external call return values checked
- [ ] Storage layout documented for upgradeable contracts
- [ ] Fuzz tests for critical functions
- [ ] Invariant tests for protocol properties
- [ ] Gas optimization reviewed
- [ ] Slither / Mythril static analysis clean

## OpenZeppelin Contracts MCP

For generating OZ-compliant contracts interactively: https://mcp.openzeppelin.com/
Supports: ERC-20, ERC-721, ERC-1155, Stablecoin, RWA, Governor, Account (Solidity, Cairo, Stylus, Stellar)

## Tools

- **Foundry** (forge/cast/anvil) — preferred for testing/deployment
- **Hardhat** — alternative, better plugin ecosystem
- **Slither** — static analysis (`pip install slither-analyzer`)
- **Mythril** — symbolic execution (`pip install mythril`)
- **Echidna** — property-based fuzzing
- **OpenZeppelin Defender** — deployment & monitoring

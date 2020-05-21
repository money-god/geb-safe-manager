# 1. Introduction (Summary)

**Summary:** The `GebCdpManager` (aka `manager`) was created to enable a formalized process for CDPs to be transferred between owners. In short, the `manager` works by having a wrapper that allows users to interact with their CDPs in an easy way, treating them as non-fungible tokens (NFTs).

# 2. Contract Details

## Key Functionalities (as defined in the smart contract)

- `allowCDP(uint cdp, address usr, uint ok)`: Allow/Disallow (`ok`) `usr` to manage `cdp`.
- `allowHandler(address usr, uint ok)`: Allow/Disallow (`ok`) `usr` to access `msg.sender` space (for sending a position in `quitSystem`).
- `openCDP(bytes32 collateralType, address usr)`: Opens a new CDP for `usr` to be used for an `collateralType` collateral type.
- `transferCDPOwnership(uint cdp, address dst)`: Transfers `cdp` to `dst`.
- `modifyCDPCollateralization(uint cdp, int deltaCollateral, int deltaDebt)`: Increments/decrements the `deltaCollateral` amount of collateral locked and increments/decrements the `deltaDebt` amount of debt in the `cdp` depositing the generated debt or collateral freed in the `cdp` address.
- `transferCollateral(bytes32 collateralType, uint cdp, address dst, uint wad)`: Moves `wad` (precision 18) amount of collateral `collateralType` from `cdp` to `dst`.
- `transferCollateral(uint cdp, address dst, uint wad)`: Moves `wad` amount of `cdp` collateral from `cdp` to `dst`.
- `transferInternalCoins(uint cdp, address dst, uint rad)`: Moves `rad` (precision 45) amount of internal coins from `cdp` to `dst`.
- `quitSystem(uint cdp, address dst)`: Moves the collateral locked and debt generated from `cdp` to `dst`.
- `enterSystem(address src, uint cdp)`: Moves the collateral locked and debt generated from `src` to `cdp`.
- `transferInternalCoinsCDP(uint cdpSrc, uint cdpDst)`: Moves the collateral locked and debt generated from `cdpSrc` to `cdpDst`.
- `claimCDPManagementRewards(uint cdp, address lad)`: Claims rewards for good cdp management

**Note:** `dst` refers to the destination address.

## Storage Layout

- `cdpEngine` : core contract address that holds the CDPs.
- `cdpi`: Auto incremental id.
- `cdps`: Mapping `CDPId => CDPHandler`
- `list`: Mapping `CDPId => Prev & Next CDPIds` (double linked list)
- `ownsCDP`: Mapping `CDPId => Owner`
- `collateralTypes`: Mapping `CDPId => CollateralType` (collateral type)
- `firstCDPID` : Mapping `Owner => First CDPId`
- `lastCDPID`: Mapping `Owner => Last CDPId`
- `cdpCount`: Mapping `Owner => Amount of CDPs`
- `cdpCan`: Mapping `Owner => CDPId => Allowed Addr => True/False`
- `handlerCan`: Mapping `Urn => Allowed Addr => True/False`
- `rewardDistributor`: Manager of rewards for cdp creators

# 3. Key Mechanisms & Concepts

## Summary

The CDP manager was created as a way to enable CDPs to be treated more like assets that can be exchanged as non-fungible tokens (NFT) would.

## High-level Purpose

- The `manager` receives the `cdpEngine` address in its creation and acts as an interface contract between it and the users.
- The `manager` keeps an internal registry of `id => owner` and `id => cdp` allowing for the `owner` to execute `CDPEngine` functions for their `cdp` via the `manager`.
- The `manager` keeps a double linked list structure that allows the retrieval of all the CDPs that an `owner` has via on-chain calls.
    - In short, this is what the `GetCdps` is for. This contract is a helper contract that allows the fetching of all the CDPs in just one call.

## CDP **Manager Usage Example (common path):**

- A User executes `openCDP` and gets a `cdpId` in return.
- After this, the `cdpId` gets associated with a `handler` with `manager.cdps(cdpId)` and then `join`'s collateral to it.
- After the user executes `modifyCDPCollateralization`, the generated debt will remain in the CDP's `handler`. Then the user can `transferInternalCoins` it at a later point in time.
    - Note that this is the same process for collateral that is freed after `modifyCDPCollateralization`. The user can `transferCollateral` to another address at a later time.
- In the case where a user wants to abandon the `manager`, they can use `quitSystem` as a way to migrate their position of their CDP to another `dst` address.

# 4. Gotchas (Potential source of user error)

- For the developers who want to integrate with the `manager`, they will need to understand that the CDP actions are still in the `handler` environment. Regardless of this, the `manager` tries to abstract the `handler` usage by a `cdpId`. This means that developers will need to get the `handler` (`handler = manager.cdps(cdpId)`) to allow the `join`ing of collateral to that CDP.
- As the `manager` assigns a specific `collateralType` per `cdpId` and doesn't allow others to use it for theirs, there is a second `transferCollateral` function which expects an `collateralType` parameter. This function has the simple purpose of taking out collateral that was wrongly sent to a CDP that can't handle it/is incompatible.
- **ModifyCDPCollateralization:**
    - When you `modifyCDPCollateralization` in the CDP manager, you generate new debt in the `CDPEngine` via the CDP manager which is then deposited in the `handler` that the CDP manager manages.
    - You would need to manually use the `transferCollateral` or `transferInternalCoins` functions to get the debt or collateral out.

# 5. Failure Modes (Bounds on Operating Conditions & External Risk Factors)

## **Potential Issues around Chain Reorganization**

When `openCDP` is executed, a new `handler` is created and a `cdpId` is assigned to it for a specific `owner`. If the user uses `join` to add collateral to the `handler` immediately after the transaction is mined, there is a chance that a reorganization of the chain occurs. This would result in the user losing the ownership of that `cdpId`/`handler` pair, therefore losing their collateral. However, this issue can only arise when avoiding the use of the proxy functions ([https://github.com/reflexer-labs/geb-proxy-actions](https://github.com/reflexer-labs/geb-proxy-actions)) via a profile proxy ([https://github.com/dapphub/ds-proxy](https://github.com/dapphub/ds-proxy)) as the user will `openCDP` the `cdp` and `join` collateral in the same transaction.

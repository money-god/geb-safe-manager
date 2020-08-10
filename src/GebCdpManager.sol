// Copyright (C) 2018-2020 Maker Ecosystem Growth Holdings, INC.

// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.

pragma solidity ^0.6.7;

import { Logging } from "geb/Logging.sol";

abstract contract CDPEngineLike {
    function cdps(bytes32, address) virtual public view returns (uint, uint);
    function approveCDPModification(address) virtual public;
    function transferCollateral(bytes32, address, address, uint) virtual public;
    function transferInternalCoins(address, address, uint) virtual public;
    function modifyCDPCollateralization(bytes32, address, address, address, int, int) virtual public;
    function transferCDPCollateralAndDebt(bytes32, address, address, int, int) virtual public;
}

abstract contract LiquidationEngineLike {
    function protectCDP(bytes32, address, address) virtual external;
}

abstract contract CollateralLike {
    function transfer(address,uint) virtual external returns (bool);
    function transferFrom(address,address,uint) virtual external returns (bool);
}

contract CDPHandler {
    constructor(address cdpEngine) public {
        CDPEngineLike(cdpEngine).approveCDPModification(msg.sender);
    }
}

contract GebCdpManager is Logging {
    address                   public cdpEngine;
    uint                      public cdpi;               // Auto incremental
    mapping (uint => address) public cdps;               // CDPId => CDPHandler
    mapping (uint => List)    public cdpList;            // CDPId => Prev & Next CDPIds (double linked list)
    mapping (uint => address) public ownsCDP;            // CDPId => Owner
    mapping (uint => bytes32) public collateralTypes;    // CDPId => CollateralType

    mapping (address => uint) public firstCDPID;         // Owner => First CDPId
    mapping (address => uint) public lastCDPID;          // Owner => Last CDPId
    mapping (address => uint) public cdpCount;           // Owner => Amount of CDPs

    mapping (
        address => mapping (
            uint => mapping (
                address => uint
            )
        )
    ) public cdpCan;                            // Owner => CDPId => Allowed Addr => True/False

    mapping (
        address => mapping (
            address => uint
        )
    ) public handlerCan;                        // CDP handler => Allowed Addr => True/False

    struct List {
        uint prev;
        uint next;
    }

    // --- Events ---
    event AllowCDP(
        address sender,
        uint cdp,
        address usr,
        uint ok
    );
    event AllowHandler(
        address sender,
        address usr,
        uint ok
    );
    event TransferCDPOwnership(
        address sender,
        uint cdp,
        address dst
    );
    event NewCdp(address indexed sender, address indexed own, uint indexed cdp);
    event ModifyCDPCollateralization(
        address sender,
        uint cdp,
        int deltaCollateral,
        int deltaDebt
    );
    event TransferCollateral(
        address sender,
        uint cdp,
        address dst,
        uint wad
    );
    event TransferCollateral(
        address sender,
        bytes32 collateralType,
        uint cdp,
        address dst,
        uint wad
    );
    event TransferInternalCoins(
        address sender,
        uint cdp,
        address dst,
        uint rad
    );
    event QuitSystem(
        address sender,
        uint cdp,
        address dst
    );
    event EnterSystem(
        address sender,
        address src,
        uint cdp
    );
    event MoveCDP(
        address sender,
        uint cdpSrc,
        uint cdpDst
    );
    event ProtectCDP(
        address sender,
        uint cdp,
        address liquidationEngine,
        address saviour
    );

    modifier cdpAllowed(
        uint cdp
    ) {
        require(msg.sender == ownsCDP[cdp] || cdpCan[ownsCDP[cdp]][cdp][msg.sender] == 1, "cdp-not-allowed");
        _;
    }

    modifier handlerAllowed(
        address handler
    ) {
        require(
          msg.sender == handler ||
          handlerCan[handler][msg.sender] == 1,
          "internal-system-cdp-not-allowed"
        );
        _;
    }

    constructor(address cdpEngine_) public {
        cdpEngine = cdpEngine_;
    }

    // --- Math ---
    function add(uint x, uint y) internal pure returns (uint z) {
        require((z = x + y) >= x);
    }

    function sub(uint x, uint y) internal pure returns (uint z) {
        require((z = x - y) <= x);
    }

    function toInt(uint x) internal pure returns (int y) {
        y = int(x);
        require(y >= 0);
    }

    // --- CDP Manipulation ---

    // Allow/disallow a usr address to manage the cdp
    function allowCDP(
        uint cdp,
        address usr,
        uint ok
    ) public cdpAllowed(cdp) {
        cdpCan[ownsCDP[cdp]][cdp][usr] = ok;
        emit AllowCDP(
            msg.sender,
            cdp,
            usr,
            ok
        );
    }

    // Allow/disallow a usr address to quit to the the sender handler
    function allowHandler(
        address usr,
        uint ok
    ) public {
        handlerCan[msg.sender][usr] = ok;
        emit AllowHandler(
            msg.sender,
            usr,
            ok
        );
    }

    // Open a new cdp for a given usr address.
    function openCDP(
        bytes32 collateralType,
        address usr
    ) public emitLog returns (uint) {
        require(usr != address(0), "usr-address-0");

        cdpi = add(cdpi, 1);
        cdps[cdpi] = address(new CDPHandler(cdpEngine));
        ownsCDP[cdpi] = usr;
        collateralTypes[cdpi] = collateralType;

        // Add new CDP to double linked list and pointers
        if (firstCDPID[usr] == 0) {
            firstCDPID[usr] = cdpi;
        }
        if (lastCDPID[usr] != 0) {
            cdpList[cdpi].prev = lastCDPID[usr];
            cdpList[lastCDPID[usr]].next = cdpi;
        }
        lastCDPID[usr] = cdpi;
        cdpCount[usr] = add(cdpCount[usr], 1);

        emit NewCdp(msg.sender, usr, cdpi);
        return cdpi;
    }

    // Give the cdp ownership to a dst address.
    function transferCDPOwnership(
        uint cdp,
        address dst
    ) public emitLog cdpAllowed(cdp) {
        require(dst != address(0), "dst-address-0");
        require(dst != ownsCDP[cdp], "dst-already-owner");

        // Remove transferred CDP from double linked list of origin user and pointers
        if (cdpList[cdp].prev != 0) {
            cdpList[cdpList[cdp].prev].next = cdpList[cdp].next;    // Set the next pointer of the prev cdp (if exists) to the next of the transferred one
        }
        if (cdpList[cdp].next != 0) {                               // If wasn't the last one
            cdpList[cdpList[cdp].next].prev = cdpList[cdp].prev;    // Set the prev pointer of the next cdp to the prev of the transferred one
        } else {                                                    // If was the last one
            lastCDPID[ownsCDP[cdp]] = cdpList[cdp].prev;            // Update last pointer of the owner
        }
        if (firstCDPID[ownsCDP[cdp]] == cdp) {                      // If was the first one
            firstCDPID[ownsCDP[cdp]] = cdpList[cdp].next;           // Update first pointer of the owner
        }
        cdpCount[ownsCDP[cdp]] = sub(cdpCount[ownsCDP[cdp]], 1);

        // Transfer ownership
        ownsCDP[cdp] = dst;

        // Add transferred CDP to double linked list of destiny user and pointers
        cdpList[cdp].prev = lastCDPID[dst];
        cdpList[cdp].next = 0;
        if (lastCDPID[dst] != 0) {
            cdpList[lastCDPID[dst]].next = cdp;
        }
        if (firstCDPID[dst] == 0) {
            firstCDPID[dst] = cdp;
        }
        lastCDPID[dst] = cdp;
        cdpCount[dst] = add(cdpCount[dst], 1);

        emit TransferCDPOwnership(
            msg.sender,
            cdp,
            dst
        );
    }

    // Frob the cdp keeping the generated COIN or collateral freed in the cdp handler address.
    function modifyCDPCollateralization(
        uint cdp,
        int deltaCollateral,
        int deltaDebt
    ) public emitLog cdpAllowed(cdp) {
        address cdpHandler = cdps[cdp];
        CDPEngineLike(cdpEngine).modifyCDPCollateralization(
            collateralTypes[cdp],
            cdpHandler,
            cdpHandler,
            cdpHandler,
            deltaCollateral,
            deltaDebt
        );
        emit ModifyCDPCollateralization(
            msg.sender,
            cdp,
            deltaCollateral,
            deltaDebt
        );
    }

    // Transfer wad amount of cdp collateral from the cdp address to a dst address.
    function transferCollateral(
        uint cdp,
        address dst,
        uint wad
    ) public emitLog cdpAllowed(cdp) {
        CDPEngineLike(cdpEngine).transferCollateral(collateralTypes[cdp], cdps[cdp], dst, wad);
        emit TransferCollateral(
            msg.sender,
            cdp,
            dst,
            wad
        );
    }

    // Transfer wad amount of any type of collateral (collateralType) from the cdp address to a dst address.
    // This function has the purpose to take away collateral from the system that doesn't correspond to the cdp but was sent there wrongly.
    function transferCollateral(
        bytes32 collateralType,
        uint cdp,
        address dst,
        uint wad
    ) public emitLog cdpAllowed(cdp) {
        CDPEngineLike(cdpEngine).transferCollateral(collateralType, cdps[cdp], dst, wad);
        emit TransferCollateral(
            msg.sender,
            collateralType,
            cdp,
            dst,
            wad
        );
    }

    // Transfer rad amount of COIN from the cdp address to a dst address.
    function transferInternalCoins(
        uint cdp,
        address dst,
        uint rad
    ) public emitLog cdpAllowed(cdp) {
        CDPEngineLike(cdpEngine).transferInternalCoins(cdps[cdp], dst, rad);
        emit TransferInternalCoins(
            msg.sender,
            cdp,
            dst,
            rad
        );
    }

    // Quit the system, migrating the cdp (lockedCollateral, generatedDebt) to a different dst handler
    function quitSystem(
        uint cdp,
        address dst
    ) public emitLog cdpAllowed(cdp) handlerAllowed(dst) {
        (uint lockedCollateral, uint generatedDebt) = CDPEngineLike(cdpEngine).cdps(collateralTypes[cdp], cdps[cdp]);
        int deltaCollateral = toInt(lockedCollateral);
        int deltaDebt = toInt(generatedDebt);
        CDPEngineLike(cdpEngine).transferCDPCollateralAndDebt(
            collateralTypes[cdp],
            cdps[cdp],
            dst,
            deltaCollateral,
            deltaDebt
        );
        emit QuitSystem(
            msg.sender,
            cdp,
            dst
        );
    }

    // Import a position from src handler to the handler owned by cdp
    function enterSystem(
        address src,
        uint cdp
    ) public emitLog handlerAllowed(src) cdpAllowed(cdp) {
        (uint lockedCollateral, uint generatedDebt) = CDPEngineLike(cdpEngine).cdps(collateralTypes[cdp], src);
        int deltaCollateral = toInt(lockedCollateral);
        int deltaDebt = toInt(generatedDebt);
        CDPEngineLike(cdpEngine).transferCDPCollateralAndDebt(
            collateralTypes[cdp],
            src,
            cdps[cdp],
            deltaCollateral,
            deltaDebt
        );
        emit EnterSystem(
            msg.sender,
            src,
            cdp
        );
    }

    // Move a position from cdpSrc handler to the cdpDst handler
    function moveCDP(
        uint cdpSrc,
        uint cdpDst
    ) public emitLog cdpAllowed(cdpSrc) cdpAllowed(cdpDst) {
        require(collateralTypes[cdpSrc] == collateralTypes[cdpDst], "non-matching-cdps");
        (uint lockedCollateral, uint generatedDebt) = CDPEngineLike(cdpEngine).cdps(collateralTypes[cdpSrc], cdps[cdpSrc]);
        int deltaCollateral = toInt(lockedCollateral);
        int deltaDebt = toInt(generatedDebt);
        CDPEngineLike(cdpEngine).transferCDPCollateralAndDebt(
            collateralTypes[cdpSrc],
            cdps[cdpSrc],
            cdps[cdpDst],
            deltaCollateral,
            deltaDebt
        );
        emit MoveCDP(
            msg.sender,
            cdpSrc,
            cdpDst
        );
    }

    // Choose a CDP saviour inside LiquidationEngine for CDP with id 'cdp'
    function protectCDP(
        uint cdp,
        address liquidationEngine,
        address saviour
    ) public emitLog cdpAllowed(cdp) {
        LiquidationEngineLike(liquidationEngine).protectCDP(
            collateralTypes[cdp],
            cdps[cdp],
            saviour
        );
        emit ProtectCDP(
            msg.sender,
            cdp,
            liquidationEngine,
            saviour
        );
    }
}

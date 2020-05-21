pragma solidity ^0.5.15;

import { GebDeployTestBase, CDPEngine, DSToken } from "geb-deploy/GebDeploy.t.base.sol";
import "./GetCdps.sol";

contract FakeRewardsDistributor {
    address public token1;
    address public token2;

    uint256 public qty;

    constructor(
      address token1_,
      address token2_,
      uint256 qty_
    ) public {
        token1 = token1_;
        token2 = token2_;
        qty  = qty_;
    }

    function claimCDPManagementRewards(bytes32 collateralType, address cdp, address dst) external returns (bool) {
        if (dst == address(0)) return false;
        DSToken(token1).transfer(dst, qty);
        DSToken(token2).transfer(dst, qty);
        return true;
    }
}

contract FakeUser {
    function doCdpAllow(
        GebCdpManager manager,
        uint cdp,
        address usr,
        uint ok
    ) public {
        manager.allowCDP(cdp, usr, ok);
    }

    function doHandlerAllow(
        GebCdpManager manager,
        address usr,
        uint ok
    ) public {
        manager.allowHandler(usr, ok);
    }

    function doTransferCDPOwnership(
        GebCdpManager manager,
        uint cdp,
        address dst
    ) public {
        manager.transferCDPOwnership(cdp, dst);
    }

    function doModifyCDPCollateralization(
        GebCdpManager manager,
        uint cdp,
        int deltaCollateral,
        int deltaDebt
    ) public {
        manager.modifyCDPCollateralization(cdp, deltaCollateral, deltaDebt);
    }

    function doApproveCDPModification(
        CDPEngine cdpEngine,
        address usr
    ) public {
        cdpEngine.approveCDPModification(usr);
    }

    function doCDPEngineFrob(
        CDPEngine cdpEngine,
        bytes32 collateralType,
        address cdp,
        address collateralSource,
        address debtDst,
        int deltaCollateral,
        int deltaDebt
    ) public {
        cdpEngine.modifyCDPCollateralization(collateralType, cdp, collateralSource, debtDst, deltaCollateral, deltaDebt);
    }
}

contract GebCdpManagerTest is GebDeployTestBase {
    GebCdpManager manager;
    GetCdps   getCdps;
    FakeUser  user;

    DSToken   tkn1;
    DSToken   tkn2;

    FakeRewardsDistributor rewardDistributor;

    function setUp() public {
        super.setUp();
        deployBond();
        manager = new GebCdpManager(address(cdpEngine));
        getCdps = new GetCdps();
        user = new FakeUser();

        // Incentive system setup
        tkn1 = new DSToken('ONE');
        tkn2 = new DSToken('TWO');

        rewardDistributor = new FakeRewardsDistributor(address(tkn1), address(tkn2), 1 ether);

        tkn1.mint(100 ether);
        tkn2.mint(100 ether);

        tkn1.push(address(rewardDistributor), 100 ether);
        tkn2.push(address(rewardDistributor), 100 ether);
    }

    function testModifyParams() public {
        manager.modifyParameters("rewardDistributor", address(rewardDistributor));
        assertTrue(address(manager.rewardDistributor()) == address(rewardDistributor));
    }

    function testClaimingZeroAddress() public {
        manager.modifyParameters("rewardDistributor", address(rewardDistributor));

        uint cdp = manager.openCDP("ETH", address(this));
        manager.claimCDPManagementRewards(cdp, address(0));

        assertEq(DSToken(rewardDistributor.token1()).balanceOf(address(this)), 1 ether);
        assertEq(DSToken(rewardDistributor.token2()).balanceOf(address(this)), 1 ether);
    }

    function testClaimingOtherAddress() public {
        address alice = address(0x1234);

        manager.modifyParameters("rewardDistributor", address(rewardDistributor));

        uint cdp = manager.openCDP("ETH", address(this));
        manager.claimCDPManagementRewards(cdp, alice);

        assertEq(DSToken(rewardDistributor.token1()).balanceOf(alice), 1 ether);
        assertEq(DSToken(rewardDistributor.token2()).balanceOf(alice), 1 ether);
    }

    function testOpenCDP() public {
        uint cdp = manager.openCDP("ETH", address(this));
        assertEq(cdp, 1);
        assertEq(cdpEngine.cdpRights(address(bytes20(manager.cdps(cdp))), address(manager)), 1);
        assertEq(manager.ownsCDP(cdp), address(this));
    }

    function testOpenCDPOtherAddress() public {
        uint cdp = manager.openCDP("ETH", address(123));
        assertEq(manager.ownsCDP(cdp), address(123));
    }

    function testFailOpenCDPZeroAddress() public {
        manager.openCDP("ETH", address(0));
    }

    function testGiveCDP() public {
        uint cdp = manager.openCDP("ETH", address(this));
        manager.transferCDPOwnership(cdp, address(123));
        assertEq(manager.ownsCDP(cdp), address(123));
    }

    function testAllowAllowed() public {
        uint cdp = manager.openCDP("ETH", address(this));
        manager.allowCDP(cdp, address(user), 1);
        user.doCdpAllow(manager, cdp, address(123), 1);
        assertEq(manager.cdpCan(address(this), cdp, address(123)), 1);
    }

    function testFailAllowNotAllowed() public {
        uint cdp = manager.openCDP("ETH", address(this));
        user.doCdpAllow(manager, cdp, address(123), 1);
    }

    function testGiveAllowed() public {
        uint cdp = manager.openCDP("ETH", address(this));
        manager.allowCDP(cdp, address(user), 1);
        user.doTransferCDPOwnership(manager, cdp, address(123));
        assertEq(manager.ownsCDP(cdp), address(123));
    }

    function testFailGiveNotAllowed() public {
        uint cdp = manager.openCDP("ETH", address(this));
        user.doTransferCDPOwnership(manager, cdp, address(123));
    }

    function testFailGiveNotAllowed2() public {
        uint cdp = manager.openCDP("ETH", address(this));
        manager.allowCDP(cdp, address(user), 1);
        manager.allowCDP(cdp, address(user), 0);
        user.doTransferCDPOwnership(manager, cdp, address(123));
    }

    function testFailGiveNotAllowed3() public {
        uint cdp = manager.openCDP("ETH", address(this));
        uint cdp2 = manager.openCDP("ETH", address(this));
        manager.allowCDP(cdp2, address(user), 1);
        user.doTransferCDPOwnership(manager, cdp, address(123));
    }

    function testFailGiveToZeroAddress() public {
        uint cdp = manager.openCDP("ETH", address(this));
        manager.transferCDPOwnership(cdp, address(0));
    }

    function testFailGiveToSameOwner() public {
        uint cdp = manager.openCDP("ETH", address(this));
        manager.transferCDPOwnership(cdp, address(this));
    }

    function testDoubleLinkedList() public {
        uint cdp1 = manager.openCDP("ETH", address(this));
        uint cdp2 = manager.openCDP("ETH", address(this));
        uint cdp3 = manager.openCDP("ETH", address(this));

        uint cdp4 = manager.openCDP("ETH", address(user));
        uint cdp5 = manager.openCDP("ETH", address(user));
        uint cdp6 = manager.openCDP("ETH", address(user));
        uint cdp7 = manager.openCDP("ETH", address(user));

        assertEq(manager.cdpCount(address(this)), 3);
        assertEq(manager.firstCDPID(address(this)), cdp1);
        assertEq(manager.lastCDPID(address(this)), cdp3);
        (uint prev, uint next) = manager.cdpList(cdp1);
        assertEq(prev, 0);
        assertEq(next, cdp2);
        (prev, next) = manager.cdpList(cdp2);
        assertEq(prev, cdp1);
        assertEq(next, cdp3);
        (prev, next) = manager.cdpList(cdp3);
        assertEq(prev, cdp2);
        assertEq(next, 0);

        assertEq(manager.cdpCount(address(user)), 4);
        assertEq(manager.firstCDPID(address(user)), cdp4);
        assertEq(manager.lastCDPID(address(user)), cdp7);
        (prev, next) = manager.cdpList(cdp4);
        assertEq(prev, 0);
        assertEq(next, cdp5);
        (prev, next) = manager.cdpList(cdp5);
        assertEq(prev, cdp4);
        assertEq(next, cdp6);
        (prev, next) = manager.cdpList(cdp6);
        assertEq(prev, cdp5);
        assertEq(next, cdp7);
        (prev, next) = manager.cdpList(cdp7);
        assertEq(prev, cdp6);
        assertEq(next, 0);

        manager.transferCDPOwnership(cdp2, address(user));

        assertEq(manager.cdpCount(address(this)), 2);
        assertEq(manager.firstCDPID(address(this)), cdp1);
        assertEq(manager.lastCDPID(address(this)), cdp3);
        (prev, next) = manager.cdpList(cdp1);
        assertEq(next, cdp3);
        (prev, next) = manager.cdpList(cdp3);
        assertEq(prev, cdp1);

        assertEq(manager.cdpCount(address(user)), 5);
        assertEq(manager.firstCDPID(address(user)), cdp4);
        assertEq(manager.lastCDPID(address(user)), cdp2);
        (prev, next) = manager.cdpList(cdp7);
        assertEq(next, cdp2);
        (prev, next) = manager.cdpList(cdp2);
        assertEq(prev, cdp7);
        assertEq(next, 0);

        user.doTransferCDPOwnership(manager, cdp2, address(this));

        assertEq(manager.cdpCount(address(this)), 3);
        assertEq(manager.firstCDPID(address(this)), cdp1);
        assertEq(manager.lastCDPID(address(this)), cdp2);
        (prev, next) = manager.cdpList(cdp3);
        assertEq(next, cdp2);
        (prev, next) = manager.cdpList(cdp2);
        assertEq(prev, cdp3);
        assertEq(next, 0);

        assertEq(manager.cdpCount(address(user)), 4);
        assertEq(manager.firstCDPID(address(user)), cdp4);
        assertEq(manager.lastCDPID(address(user)), cdp7);
        (prev, next) = manager.cdpList(cdp7);
        assertEq(next, 0);

        manager.transferCDPOwnership(cdp1, address(user));
        assertEq(manager.cdpCount(address(this)), 2);
        assertEq(manager.firstCDPID(address(this)), cdp3);
        assertEq(manager.lastCDPID(address(this)), cdp2);

        manager.transferCDPOwnership(cdp2, address(user));
        assertEq(manager.cdpCount(address(this)), 1);
        assertEq(manager.firstCDPID(address(this)), cdp3);
        assertEq(manager.lastCDPID(address(this)), cdp3);

        manager.transferCDPOwnership(cdp3, address(user));
        assertEq(manager.cdpCount(address(this)), 0);
        assertEq(manager.firstCDPID(address(this)), 0);
        assertEq(manager.lastCDPID(address(this)), 0);
    }

    function testGetCdpsAsc() public {
        uint cdp1 = manager.openCDP("ETH", address(this));
        uint cdp2 = manager.openCDP("REP", address(this));
        uint cdp3 = manager.openCDP("GOLD", address(this));

        (uint[] memory ids,, bytes32[] memory collateralTypes) = getCdps.getCdpsAsc(address(manager), address(this));
        assertEq(ids.length, 3);
        assertEq(ids[0], cdp1);
        assertEq32(collateralTypes[0], bytes32("ETH"));
        assertEq(ids[1], cdp2);
        assertEq32(collateralTypes[1], bytes32("REP"));
        assertEq(ids[2], cdp3);
        assertEq32(collateralTypes[2], bytes32("GOLD"));

        manager.transferCDPOwnership(cdp2, address(user));
        (ids,, collateralTypes) = getCdps.getCdpsAsc(address(manager), address(this));
        assertEq(ids.length, 2);
        assertEq(ids[0], cdp1);
        assertEq32(collateralTypes[0], bytes32("ETH"));
        assertEq(ids[1], cdp3);
        assertEq32(collateralTypes[1], bytes32("GOLD"));
    }

    function testGetCdpsDesc() public {
        uint cdp1 = manager.openCDP("ETH", address(this));
        uint cdp2 = manager.openCDP("REP", address(this));
        uint cdp3 = manager.openCDP("GOLD", address(this));

        (uint[] memory ids,, bytes32[] memory collateralTypes) = getCdps.getCdpsDesc(address(manager), address(this));
        assertEq(ids.length, 3);
        assertEq(ids[0], cdp3);
        assertTrue(collateralTypes[0] == bytes32("GOLD"));
        assertEq(ids[1], cdp2);
        assertTrue(collateralTypes[1] == bytes32("REP"));
        assertEq(ids[2], cdp1);
        assertTrue(collateralTypes[2] == bytes32("ETH"));

        manager.transferCDPOwnership(cdp2, address(user));
        (ids,, collateralTypes) = getCdps.getCdpsDesc(address(manager), address(this));
        assertEq(ids.length, 2);
        assertEq(ids[0], cdp3);
        assertTrue(collateralTypes[0] == bytes32("GOLD"));
        assertEq(ids[1], cdp1);
        assertTrue(collateralTypes[1] == bytes32("ETH"));
    }

    function testModifyCDPCollateralization() public {
        uint cdp = manager.openCDP("ETH", address(this));
        weth.deposit.value(1 ether)();
        weth.approve(address(ethJoin), 1 ether);
        ethJoin.join(manager.cdps(cdp), 1 ether);
        manager.modifyCDPCollateralization(cdp, 1 ether, 50 ether);
        assertEq(cdpEngine.coinBalance(manager.cdps(cdp)), 50 ether * ONE);
        assertEq(cdpEngine.coinBalance(address(this)), 0);
        manager.transferInternalCoins(cdp, address(this), 50 ether * ONE);
        assertEq(cdpEngine.coinBalance(manager.cdps(cdp)), 0);
        assertEq(cdpEngine.coinBalance(address(this)), 50 ether * ONE);
        assertEq(coin.balanceOf(address(this)), 0);
        cdpEngine.approveCDPModification(address(coinJoin));
        coinJoin.exit(address(this), 50 ether);
        assertEq(coin.balanceOf(address(this)), 50 ether);
    }

    function testFrobAllowed() public {
        uint cdp = manager.openCDP("ETH", address(this));
        weth.deposit.value(1 ether)();
        weth.approve(address(ethJoin), 1 ether);
        ethJoin.join(manager.cdps(cdp), 1 ether);
        manager.allowCDP(cdp, address(user), 1);
        user.doModifyCDPCollateralization(manager, cdp, 1 ether, 50 ether);
        assertEq(cdpEngine.coinBalance(manager.cdps(cdp)), 50 ether * ONE);
    }

    function testFailFrobNotAllowed() public {
        uint cdp = manager.openCDP("ETH", address(this));
        weth.deposit.value(1 ether)();
        weth.approve(address(ethJoin), 1 ether);
        ethJoin.join(manager.cdps(cdp), 1 ether);
        user.doModifyCDPCollateralization(manager, cdp, 1 ether, 50 ether);
    }

    function testFrobGetCollateralBack() public {
        uint cdp = manager.openCDP("ETH", address(this));
        weth.deposit.value(1 ether)();
        weth.approve(address(ethJoin), 1 ether);
        ethJoin.join(manager.cdps(cdp), 1 ether);
        manager.modifyCDPCollateralization(cdp, 1 ether, 50 ether);
        manager.modifyCDPCollateralization(cdp, -int(1 ether), -int(50 ether));
        assertEq(cdpEngine.coinBalance(address(this)), 0);
        assertEq(cdpEngine.tokenCollateral("ETH", manager.cdps(cdp)), 1 ether);
        assertEq(cdpEngine.tokenCollateral("ETH", address(this)), 0);
        manager.transferCollateral(cdp, address(this), 1 ether);
        assertEq(cdpEngine.tokenCollateral("ETH", manager.cdps(cdp)), 0);
        assertEq(cdpEngine.tokenCollateral("ETH", address(this)), 1 ether);
        uint prevBalance = address(this).balance;
        ethJoin.exit(address(this), 1 ether);
        weth.withdraw(1 ether);
        assertEq(address(this).balance, prevBalance + 1 ether);
    }

    function testGetWrongCollateralBack() public {
        uint cdp = manager.openCDP("ETH", address(this));
        col.mint(1 ether);
        col.approve(address(colJoin), 1 ether);
        colJoin.join(manager.cdps(cdp), 1 ether);
        assertEq(cdpEngine.tokenCollateral("COL", manager.cdps(cdp)), 1 ether);
        assertEq(cdpEngine.tokenCollateral("COL", address(this)), 0);
        manager.transferCollateral("COL", cdp, address(this), 1 ether);
        assertEq(cdpEngine.tokenCollateral("COL", manager.cdps(cdp)), 0);
        assertEq(cdpEngine.tokenCollateral("COL", address(this)), 1 ether);
    }

    function testQuit() public {
        uint cdp = manager.openCDP("ETH", address(this));
        weth.deposit.value(1 ether)();
        weth.approve(address(ethJoin), 1 ether);
        ethJoin.join(manager.cdps(cdp), 1 ether);
        manager.modifyCDPCollateralization(cdp, 1 ether, 50 ether);

        (uint collateralType, uint art) = cdpEngine.cdps("ETH", manager.cdps(cdp));
        assertEq(collateralType, 1 ether);
        assertEq(art, 50 ether);
        (collateralType, art) = cdpEngine.cdps("ETH", address(this));
        assertEq(collateralType, 0);
        assertEq(art, 0);

        cdpEngine.approveCDPModification(address(manager));
        manager.quitSystem(cdp, address(this));
        (collateralType, art) = cdpEngine.cdps("ETH", manager.cdps(cdp));
        assertEq(collateralType, 0);
        assertEq(art, 0);
        (collateralType, art) = cdpEngine.cdps("ETH", address(this));
        assertEq(collateralType, 1 ether);
        assertEq(art, 50 ether);
    }

    function testQuitOtherDst() public {
        uint cdp = manager.openCDP("ETH", address(this));
        weth.deposit.value(1 ether)();
        weth.approve(address(ethJoin), 1 ether);
        ethJoin.join(manager.cdps(cdp), 1 ether);
        manager.modifyCDPCollateralization(cdp, 1 ether, 50 ether);

        (uint collateralType, uint art) = cdpEngine.cdps("ETH", manager.cdps(cdp));
        assertEq(collateralType, 1 ether);
        assertEq(art, 50 ether);
        (collateralType, art) = cdpEngine.cdps("ETH", address(this));
        assertEq(collateralType, 0);
        assertEq(art, 0);

        user.doApproveCDPModification(cdpEngine, address(manager));
        user.doHandlerAllow(manager, address(this), 1);
        manager.quitSystem(cdp, address(user));
        (collateralType, art) = cdpEngine.cdps("ETH", manager.cdps(cdp));
        assertEq(collateralType, 0);
        assertEq(art, 0);
        (collateralType, art) = cdpEngine.cdps("ETH", address(user));
        assertEq(collateralType, 1 ether);
        assertEq(art, 50 ether);
    }

    function testFailQuitOtherDst() public {
        uint cdp = manager.openCDP("ETH", address(this));
        weth.deposit.value(1 ether)();
        weth.approve(address(ethJoin), 1 ether);
        ethJoin.join(manager.cdps(cdp), 1 ether);
        manager.modifyCDPCollateralization(cdp, 1 ether, 50 ether);

        (uint collateralType, uint art) = cdpEngine.cdps("ETH", manager.cdps(cdp));
        assertEq(collateralType, 1 ether);
        assertEq(art, 50 ether);
        (collateralType, art) = cdpEngine.cdps("ETH", address(this));
        assertEq(collateralType, 0);
        assertEq(art, 0);

        user.doApproveCDPModification(cdpEngine, address(manager));
        manager.quitSystem(cdp, address(user));
    }

    function testEnter() public {
        weth.deposit.value(1 ether)();
        weth.approve(address(ethJoin), 1 ether);
        ethJoin.join(address(this), 1 ether);
        cdpEngine.modifyCDPCollateralization("ETH", address(this), address(this), address(this), 1 ether, 50 ether);
        uint cdp = manager.openCDP("ETH", address(this));

        (uint collateralType, uint art) = cdpEngine.cdps("ETH", manager.cdps(cdp));
        assertEq(collateralType, 0);
        assertEq(art, 0);

        (collateralType, art) = cdpEngine.cdps("ETH", address(this));
        assertEq(collateralType, 1 ether);
        assertEq(art, 50 ether);

        cdpEngine.approveCDPModification(address(manager));
        manager.enterSystem(address(this), cdp);

        (collateralType, art) = cdpEngine.cdps("ETH", manager.cdps(cdp));
        assertEq(collateralType, 1 ether);
        assertEq(art, 50 ether);

        (collateralType, art) = cdpEngine.cdps("ETH", address(this));
        assertEq(collateralType, 0);
        assertEq(art, 0);
    }

    function testEnterOtherSrc() public {
        weth.deposit.value(1 ether)();
        weth.approve(address(ethJoin), 1 ether);
        ethJoin.join(address(user), 1 ether);
        user.doCDPEngineFrob(cdpEngine, "ETH", address(user), address(user), address(user), 1 ether, 50 ether);

        uint cdp = manager.openCDP("ETH", address(this));

        (uint collateralType, uint art) = cdpEngine.cdps("ETH", manager.cdps(cdp));
        assertEq(collateralType, 0);
        assertEq(art, 0);

        (collateralType, art) = cdpEngine.cdps("ETH", address(user));
        assertEq(collateralType, 1 ether);
        assertEq(art, 50 ether);

        user.doApproveCDPModification(cdpEngine, address(manager));
        user.doHandlerAllow(manager, address(this), 1);
        manager.enterSystem(address(user), cdp);

        (collateralType, art) = cdpEngine.cdps("ETH", manager.cdps(cdp));
        assertEq(collateralType, 1 ether);
        assertEq(art, 50 ether);

        (collateralType, art) = cdpEngine.cdps("ETH", address(user));
        assertEq(collateralType, 0);
        assertEq(art, 0);
    }

    function testFailEnterOtherSrc() public {
        weth.deposit.value(1 ether)();
        weth.approve(address(ethJoin), 1 ether);
        ethJoin.join(address(user), 1 ether);
        user.doCDPEngineFrob(cdpEngine, "ETH", address(user), address(user), address(user), 1 ether, 50 ether);

        uint cdp = manager.openCDP("ETH", address(this));

        user.doApproveCDPModification(cdpEngine, address(manager));
        manager.enterSystem(address(user), cdp);
    }

    function testFailEnterOtherSrc2() public {
        weth.deposit.value(1 ether)();
        weth.approve(address(ethJoin), 1 ether);
        ethJoin.join(address(user), 1 ether);
        user.doCDPEngineFrob(cdpEngine, "ETH", address(user), address(user), address(user), 1 ether, 50 ether);

        uint cdp = manager.openCDP("ETH", address(this));

        user.doHandlerAllow(manager, address(this), 1);
        manager.enterSystem(address(user), cdp);
    }

    function testEnterOtherCdp() public {
        weth.deposit.value(1 ether)();
        weth.approve(address(ethJoin), 1 ether);
        ethJoin.join(address(this), 1 ether);
        cdpEngine.modifyCDPCollateralization("ETH", address(this), address(this), address(this), 1 ether, 50 ether);
        uint cdp = manager.openCDP("ETH", address(this));
        manager.transferCDPOwnership(cdp, address(user));

        (uint collateralType, uint art) = cdpEngine.cdps("ETH", manager.cdps(cdp));
        assertEq(collateralType, 0);
        assertEq(art, 0);

        (collateralType, art) = cdpEngine.cdps("ETH", address(this));
        assertEq(collateralType, 1 ether);
        assertEq(art, 50 ether);

        cdpEngine.approveCDPModification(address(manager));
        user.doCdpAllow(manager, cdp, address(this), 1);
        manager.enterSystem(address(this), cdp);

        (collateralType, art) = cdpEngine.cdps("ETH", manager.cdps(cdp));
        assertEq(collateralType, 1 ether);
        assertEq(art, 50 ether);

        (collateralType, art) = cdpEngine.cdps("ETH", address(this));
        assertEq(collateralType, 0);
        assertEq(art, 0);
    }

    function testFailEnterOtherCdp() public {
        weth.deposit.value(1 ether)();
        weth.approve(address(ethJoin), 1 ether);
        ethJoin.join(address(this), 1 ether);
        cdpEngine.modifyCDPCollateralization("ETH", address(this), address(this), address(this), 1 ether, 50 ether);
        uint cdp = manager.openCDP("ETH", address(this));
        manager.transferCDPOwnership(cdp, address(user));

        cdpEngine.approveCDPModification(address(manager));
        manager.enterSystem(address(this), cdp);
    }

    function testFailEnterOtherCdp2() public {
        weth.deposit.value(1 ether)();
        weth.approve(address(ethJoin), 1 ether);
        ethJoin.join(address(this), 1 ether);
        cdpEngine.modifyCDPCollateralization("ETH", address(this), address(this), address(this), 1 ether, 50 ether);
        uint cdp = manager.openCDP("ETH", address(this));
        manager.transferCDPOwnership(cdp, address(user));

        user.doCdpAllow(manager, cdp, address(this), 1);
        manager.enterSystem(address(this), cdp);
    }

    function testMove() public {
        weth.deposit.value(1 ether)();
        weth.approve(address(ethJoin), 1 ether);
        uint cdpSrc = manager.openCDP("ETH", address(this));
        ethJoin.join(address(manager.cdps(cdpSrc)), 1 ether);
        manager.modifyCDPCollateralization(cdpSrc, 1 ether, 50 ether);
        uint cdpDst = manager.openCDP("ETH", address(this));

        (uint collateralType, uint art) = cdpEngine.cdps("ETH", manager.cdps(cdpDst));
        assertEq(collateralType, 0);
        assertEq(art, 0);

        (collateralType, art) = cdpEngine.cdps("ETH", manager.cdps(cdpSrc));
        assertEq(collateralType, 1 ether);
        assertEq(art, 50 ether);

        manager.moveCDP(cdpSrc, cdpDst);

        (collateralType, art) = cdpEngine.cdps("ETH", manager.cdps(cdpDst));
        assertEq(collateralType, 1 ether);
        assertEq(art, 50 ether);

        (collateralType, art) = cdpEngine.cdps("ETH", manager.cdps(cdpSrc));
        assertEq(collateralType, 0);
        assertEq(art, 0);
    }

    function testMoveOtherCdpDst() public {
        weth.deposit.value(1 ether)();
        weth.approve(address(ethJoin), 1 ether);
        uint cdpSrc = manager.openCDP("ETH", address(this));
        ethJoin.join(address(manager.cdps(cdpSrc)), 1 ether);
        manager.modifyCDPCollateralization(cdpSrc, 1 ether, 50 ether);
        uint cdpDst = manager.openCDP("ETH", address(this));
        manager.transferCDPOwnership(cdpDst, address(user));

        (uint collateralType, uint art) = cdpEngine.cdps("ETH", manager.cdps(cdpDst));
        assertEq(collateralType, 0);
        assertEq(art, 0);

        (collateralType, art) = cdpEngine.cdps("ETH", manager.cdps(cdpSrc));
        assertEq(collateralType, 1 ether);
        assertEq(art, 50 ether);

        user.doCdpAllow(manager, cdpDst, address(this), 1);
        manager.moveCDP(cdpSrc, cdpDst);

        (collateralType, art) = cdpEngine.cdps("ETH", manager.cdps(cdpDst));
        assertEq(collateralType, 1 ether);
        assertEq(art, 50 ether);

        (collateralType, art) = cdpEngine.cdps("ETH", manager.cdps(cdpSrc));
        assertEq(collateralType, 0);
        assertEq(art, 0);
    }

    function testFailMoveOtherCdpDst() public {
        weth.deposit.value(1 ether)();
        weth.approve(address(ethJoin), 1 ether);
        uint cdpSrc = manager.openCDP("ETH", address(this));
        ethJoin.join(address(manager.cdps(cdpSrc)), 1 ether);
        manager.modifyCDPCollateralization(cdpSrc, 1 ether, 50 ether);
        uint cdpDst = manager.openCDP("ETH", address(this));
        manager.transferCDPOwnership(cdpDst, address(user));

        manager.moveCDP(cdpSrc, cdpDst);
    }

    function testMoveOtherCdpSrc() public {
        weth.deposit.value(1 ether)();
        weth.approve(address(ethJoin), 1 ether);
        uint cdpSrc = manager.openCDP("ETH", address(this));
        ethJoin.join(address(manager.cdps(cdpSrc)), 1 ether);
        manager.modifyCDPCollateralization(cdpSrc, 1 ether, 50 ether);
        uint cdpDst = manager.openCDP("ETH", address(this));
        manager.transferCDPOwnership(cdpSrc, address(user));

        (uint collateralType, uint art) = cdpEngine.cdps("ETH", manager.cdps(cdpDst));
        assertEq(collateralType, 0);
        assertEq(art, 0);

        (collateralType, art) = cdpEngine.cdps("ETH", manager.cdps(cdpSrc));
        assertEq(collateralType, 1 ether);
        assertEq(art, 50 ether);

        user.doCdpAllow(manager, cdpSrc, address(this), 1);
        manager.moveCDP(cdpSrc, cdpDst);

        (collateralType, art) = cdpEngine.cdps("ETH", manager.cdps(cdpDst));
        assertEq(collateralType, 1 ether);
        assertEq(art, 50 ether);

        (collateralType, art) = cdpEngine.cdps("ETH", manager.cdps(cdpSrc));
        assertEq(collateralType, 0);
        assertEq(art, 0);
    }

    function testFailMoveOtherCdpSrc() public {
        weth.deposit.value(1 ether)();
        weth.approve(address(ethJoin), 1 ether);
        uint cdpSrc = manager.openCDP("ETH", address(this));
        ethJoin.join(address(manager.cdps(cdpSrc)), 1 ether);
        manager.modifyCDPCollateralization(cdpSrc, 1 ether, 50 ether);
        uint cdpDst = manager.openCDP("ETH", address(this));
        manager.transferCDPOwnership(cdpSrc, address(user));

        manager.moveCDP(cdpSrc, cdpDst);
    }
}

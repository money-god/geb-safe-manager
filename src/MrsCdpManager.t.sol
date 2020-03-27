pragma solidity ^0.5.15;

import { MrsDeployTestBase, Vat, DSToken } from "mrs-deploy/MrsDeploy.t.base.sol";
import "./GetCdps.sol";

contract FakePurse {
    address public gem1;
    address public gem2;

    uint256 public qty;

    constructor(
      address gem1_,
      address gem2_,
      uint256 qty_
    ) public {
        gem1 = gem1_;
        gem2 = gem2_;
        qty  = qty_;
    }

    function claim(bytes32 ilk, address urn, address lad) external returns (bool) {
        if (lad == address(0)) return false;
        DSToken(gem1).transfer(lad, qty);
        DSToken(gem2).transfer(lad, qty);
        return true;
    }
}

contract FakeRoot {
    struct Urn {
      uint ink;
      uint art;
    }

    mapping(bytes32 => mapping(address => Urn)) public urns;

    constructor() public {}

    // --- Math ---
    function add(uint x, int y) internal pure returns (uint z) {
        z = x + uint(y);
        require(y >= 0 || z <= x);
        require(y <= 0 || z >= x);
    }
    function sub(uint x, int y) internal pure returns (uint z) {
        z = x - uint(y);
        require(y <= 0 || z <= x);
        require(y >= 0 || z >= x);
    }

    function mail(bytes32 ilk, address urn, int dink, int dart) external {
        urns[ilk][urn].ink = add(urns[ilk][urn].ink, dink);
        urns[ilk][urn].art = add(urns[ilk][urn].art, dart);
    }
}

contract FakeUser {

    function doCdpAllow(
        MrsCdpManager manager,
        uint cdp,
        address usr,
        uint ok
    ) public {
        manager.cdpAllow(cdp, usr, ok);
    }

    function doUrnAllow(
        MrsCdpManager manager,
        address usr,
        uint ok
    ) public {
        manager.urnAllow(usr, ok);
    }

    function doGive(
        MrsCdpManager manager,
        uint cdp,
        address dst
    ) public {
        manager.give(cdp, dst);
    }

    function doFrob(
        MrsCdpManager manager,
        uint cdp,
        int dink,
        int dart
    ) public {
        manager.frob(cdp, dink, dart);
    }

    function doHope(
        Vat vat,
        address usr
    ) public {
        vat.hope(usr);
    }

    function doVatFrob(
        Vat vat,
        bytes32 i,
        address u,
        address v,
        address w,
        int dink,
        int dart
    ) public {
        vat.frob(i, u, v, w, dink, dart);
    }
}

contract MrsCdpManagerTest is MrsDeployTestBase {
    MrsCdpManager manager;
    GetCdps   getCdps;
    FakeUser  user;

    DSToken   tkn1;
    DSToken   tkn2;

    FakeRoot  root;
    FakePurse purse;

    function setUp() public {
        super.setUp();
        deploy();
        manager = new MrsCdpManager(address(vat));
        getCdps = new GetCdps();
        user = new FakeUser();

        // Incentive system setup
        tkn1 = new DSToken('ONE');
        tkn2 = new DSToken('TWO');

        purse = new FakePurse(address(tkn1), address(tkn2), 1 ether);
        root  = new FakeRoot();

        tkn1.mint(100 ether);
        tkn2.mint(100 ether);

        tkn1.push(address(purse), 100 ether);
        tkn2.push(address(purse), 100 ether);
    }

    function testFileParams() public {
        manager.file("purse", address(purse));
        manager.file("root", address(root));

        assertTrue(address(manager.purse()) == address(purse));
        assertTrue(address(manager.root()) == address(root));
    }

    function testMailing() public {
        manager.file("root", address(root));

        uint cdp = manager.open("ETH", address(this));
        weth.deposit.value(1 ether)();
        weth.approve(address(ethJoin), 1 ether);
        ethJoin.join(manager.urns(cdp), 1 ether);

        (uint ink, uint art) = root.urns(manager.ilks(cdp), manager.urns(cdp));
        assertEq(ink, 0);
        assertEq(art, 0);

        manager.frob(cdp, 1 ether, 50 ether);
        (ink, art) = root.urns(manager.ilks(cdp), manager.urns(cdp));
        assertEq(ink, 1 ether);
        assertEq(art, 50 ether);
    }

    function testClaimingZeroAddress() public {
        manager.file("purse", address(purse));

        uint cdp = manager.open("ETH", address(this));
        manager.claim(cdp, address(0));

        assertEq(DSToken(purse.gem1()).balanceOf(address(this)), 1 ether);
        assertEq(DSToken(purse.gem2()).balanceOf(address(this)), 1 ether);
    }

    function testClaimingOtherAddress() public {
        address alice = address(0x1234);

        manager.file("purse", address(purse));

        uint cdp = manager.open("ETH", address(this));
        manager.claim(cdp, alice);

        assertEq(DSToken(purse.gem1()).balanceOf(alice), 1 ether);
        assertEq(DSToken(purse.gem2()).balanceOf(alice), 1 ether);
    }

    function testOpenCDP() public {
        uint cdp = manager.open("ETH", address(this));
        assertEq(cdp, 1);
        assertEq(vat.can(address(bytes20(manager.urns(cdp))), address(manager)), 1);
        assertEq(manager.owns(cdp), address(this));
    }

    function testOpenCDPOtherAddress() public {
        uint cdp = manager.open("ETH", address(123));
        assertEq(manager.owns(cdp), address(123));
    }

    function testFailOpenCDPZeroAddress() public {
        manager.open("ETH", address(0));
    }

    function testGiveCDP() public {
        uint cdp = manager.open("ETH", address(this));
        manager.give(cdp, address(123));
        assertEq(manager.owns(cdp), address(123));
    }

    function testAllowAllowed() public {
        uint cdp = manager.open("ETH", address(this));
        manager.cdpAllow(cdp, address(user), 1);
        user.doCdpAllow(manager, cdp, address(123), 1);
        assertEq(manager.cdpCan(address(this), cdp, address(123)), 1);
    }

    function testFailAllowNotAllowed() public {
        uint cdp = manager.open("ETH", address(this));
        user.doCdpAllow(manager, cdp, address(123), 1);
    }

    function testGiveAllowed() public {
        uint cdp = manager.open("ETH", address(this));
        manager.cdpAllow(cdp, address(user), 1);
        user.doGive(manager, cdp, address(123));
        assertEq(manager.owns(cdp), address(123));
    }

    function testFailGiveNotAllowed() public {
        uint cdp = manager.open("ETH", address(this));
        user.doGive(manager, cdp, address(123));
    }

    function testFailGiveNotAllowed2() public {
        uint cdp = manager.open("ETH", address(this));
        manager.cdpAllow(cdp, address(user), 1);
        manager.cdpAllow(cdp, address(user), 0);
        user.doGive(manager, cdp, address(123));
    }

    function testFailGiveNotAllowed3() public {
        uint cdp = manager.open("ETH", address(this));
        uint cdp2 = manager.open("ETH", address(this));
        manager.cdpAllow(cdp2, address(user), 1);
        user.doGive(manager, cdp, address(123));
    }

    function testFailGiveToZeroAddress() public {
        uint cdp = manager.open("ETH", address(this));
        manager.give(cdp, address(0));
    }

    function testFailGiveToSameOwner() public {
        uint cdp = manager.open("ETH", address(this));
        manager.give(cdp, address(this));
    }

    function testDoubleLinkedList() public {
        uint cdp1 = manager.open("ETH", address(this));
        uint cdp2 = manager.open("ETH", address(this));
        uint cdp3 = manager.open("ETH", address(this));

        uint cdp4 = manager.open("ETH", address(user));
        uint cdp5 = manager.open("ETH", address(user));
        uint cdp6 = manager.open("ETH", address(user));
        uint cdp7 = manager.open("ETH", address(user));

        assertEq(manager.count(address(this)), 3);
        assertEq(manager.first(address(this)), cdp1);
        assertEq(manager.last(address(this)), cdp3);
        (uint prev, uint next) = manager.list(cdp1);
        assertEq(prev, 0);
        assertEq(next, cdp2);
        (prev, next) = manager.list(cdp2);
        assertEq(prev, cdp1);
        assertEq(next, cdp3);
        (prev, next) = manager.list(cdp3);
        assertEq(prev, cdp2);
        assertEq(next, 0);

        assertEq(manager.count(address(user)), 4);
        assertEq(manager.first(address(user)), cdp4);
        assertEq(manager.last(address(user)), cdp7);
        (prev, next) = manager.list(cdp4);
        assertEq(prev, 0);
        assertEq(next, cdp5);
        (prev, next) = manager.list(cdp5);
        assertEq(prev, cdp4);
        assertEq(next, cdp6);
        (prev, next) = manager.list(cdp6);
        assertEq(prev, cdp5);
        assertEq(next, cdp7);
        (prev, next) = manager.list(cdp7);
        assertEq(prev, cdp6);
        assertEq(next, 0);

        manager.give(cdp2, address(user));

        assertEq(manager.count(address(this)), 2);
        assertEq(manager.first(address(this)), cdp1);
        assertEq(manager.last(address(this)), cdp3);
        (prev, next) = manager.list(cdp1);
        assertEq(next, cdp3);
        (prev, next) = manager.list(cdp3);
        assertEq(prev, cdp1);

        assertEq(manager.count(address(user)), 5);
        assertEq(manager.first(address(user)), cdp4);
        assertEq(manager.last(address(user)), cdp2);
        (prev, next) = manager.list(cdp7);
        assertEq(next, cdp2);
        (prev, next) = manager.list(cdp2);
        assertEq(prev, cdp7);
        assertEq(next, 0);

        user.doGive(manager, cdp2, address(this));

        assertEq(manager.count(address(this)), 3);
        assertEq(manager.first(address(this)), cdp1);
        assertEq(manager.last(address(this)), cdp2);
        (prev, next) = manager.list(cdp3);
        assertEq(next, cdp2);
        (prev, next) = manager.list(cdp2);
        assertEq(prev, cdp3);
        assertEq(next, 0);

        assertEq(manager.count(address(user)), 4);
        assertEq(manager.first(address(user)), cdp4);
        assertEq(manager.last(address(user)), cdp7);
        (prev, next) = manager.list(cdp7);
        assertEq(next, 0);

        manager.give(cdp1, address(user));
        assertEq(manager.count(address(this)), 2);
        assertEq(manager.first(address(this)), cdp3);
        assertEq(manager.last(address(this)), cdp2);

        manager.give(cdp2, address(user));
        assertEq(manager.count(address(this)), 1);
        assertEq(manager.first(address(this)), cdp3);
        assertEq(manager.last(address(this)), cdp3);

        manager.give(cdp3, address(user));
        assertEq(manager.count(address(this)), 0);
        assertEq(manager.first(address(this)), 0);
        assertEq(manager.last(address(this)), 0);
    }

    function testGetCdpsAsc() public {
        uint cdp1 = manager.open("ETH", address(this));
        uint cdp2 = manager.open("REP", address(this));
        uint cdp3 = manager.open("GOLD", address(this));

        (uint[] memory ids,, bytes32[] memory ilks) = getCdps.getCdpsAsc(address(manager), address(this));
        assertEq(ids.length, 3);
        assertEq(ids[0], cdp1);
        assertEq32(ilks[0], bytes32("ETH"));
        assertEq(ids[1], cdp2);
        assertEq32(ilks[1], bytes32("REP"));
        assertEq(ids[2], cdp3);
        assertEq32(ilks[2], bytes32("GOLD"));

        manager.give(cdp2, address(user));
        (ids,, ilks) = getCdps.getCdpsAsc(address(manager), address(this));
        assertEq(ids.length, 2);
        assertEq(ids[0], cdp1);
        assertEq32(ilks[0], bytes32("ETH"));
        assertEq(ids[1], cdp3);
        assertEq32(ilks[1], bytes32("GOLD"));
    }

    function testGetCdpsDesc() public {
        uint cdp1 = manager.open("ETH", address(this));
        uint cdp2 = manager.open("REP", address(this));
        uint cdp3 = manager.open("GOLD", address(this));

        (uint[] memory ids,, bytes32[] memory ilks) = getCdps.getCdpsDesc(address(manager), address(this));
        assertEq(ids.length, 3);
        assertEq(ids[0], cdp3);
        assertTrue(ilks[0] == bytes32("GOLD"));
        assertEq(ids[1], cdp2);
        assertTrue(ilks[1] == bytes32("REP"));
        assertEq(ids[2], cdp1);
        assertTrue(ilks[2] == bytes32("ETH"));

        manager.give(cdp2, address(user));
        (ids,, ilks) = getCdps.getCdpsDesc(address(manager), address(this));
        assertEq(ids.length, 2);
        assertEq(ids[0], cdp3);
        assertTrue(ilks[0] == bytes32("GOLD"));
        assertEq(ids[1], cdp1);
        assertTrue(ilks[1] == bytes32("ETH"));
    }

    function testFrob() public {
        uint cdp = manager.open("ETH", address(this));
        weth.deposit.value(1 ether)();
        weth.approve(address(ethJoin), 1 ether);
        ethJoin.join(manager.urns(cdp), 1 ether);
        manager.frob(cdp, 1 ether, 50 ether);
        assertEq(vat.mai(manager.urns(cdp)), 50 ether * ONE);
        assertEq(vat.mai(address(this)), 0);
        manager.move(cdp, address(this), 50 ether * ONE);
        assertEq(vat.mai(manager.urns(cdp)), 0);
        assertEq(vat.mai(address(this)), 50 ether * ONE);
        assertEq(mai.balanceOf(address(this)), 0);
        vat.hope(address(maiJoin));
        maiJoin.exit(address(this), 50 ether);
        assertEq(mai.balanceOf(address(this)), 50 ether);
    }

    function testFrobAllowed() public {
        uint cdp = manager.open("ETH", address(this));
        weth.deposit.value(1 ether)();
        weth.approve(address(ethJoin), 1 ether);
        ethJoin.join(manager.urns(cdp), 1 ether);
        manager.cdpAllow(cdp, address(user), 1);
        user.doFrob(manager, cdp, 1 ether, 50 ether);
        assertEq(vat.mai(manager.urns(cdp)), 50 ether * ONE);
    }

    function testFailFrobNotAllowed() public {
        uint cdp = manager.open("ETH", address(this));
        weth.deposit.value(1 ether)();
        weth.approve(address(ethJoin), 1 ether);
        ethJoin.join(manager.urns(cdp), 1 ether);
        user.doFrob(manager, cdp, 1 ether, 50 ether);
    }

    function testFrobGetCollateralBack() public {
        uint cdp = manager.open("ETH", address(this));
        weth.deposit.value(1 ether)();
        weth.approve(address(ethJoin), 1 ether);
        ethJoin.join(manager.urns(cdp), 1 ether);
        manager.frob(cdp, 1 ether, 50 ether);
        manager.frob(cdp, -int(1 ether), -int(50 ether));
        assertEq(vat.mai(address(this)), 0);
        assertEq(vat.gem("ETH", manager.urns(cdp)), 1 ether);
        assertEq(vat.gem("ETH", address(this)), 0);
        manager.flux(cdp, address(this), 1 ether);
        assertEq(vat.gem("ETH", manager.urns(cdp)), 0);
        assertEq(vat.gem("ETH", address(this)), 1 ether);
        uint prevBalance = address(this).balance;
        ethJoin.exit(address(this), 1 ether);
        weth.withdraw(1 ether);
        assertEq(address(this).balance, prevBalance + 1 ether);
    }

    function testGetWrongCollateralBack() public {
        uint cdp = manager.open("ETH", address(this));
        col.mint(1 ether);
        col.approve(address(colJoin), 1 ether);
        colJoin.join(manager.urns(cdp), 1 ether);
        assertEq(vat.gem("COL", manager.urns(cdp)), 1 ether);
        assertEq(vat.gem("COL", address(this)), 0);
        manager.flux("COL", cdp, address(this), 1 ether);
        assertEq(vat.gem("COL", manager.urns(cdp)), 0);
        assertEq(vat.gem("COL", address(this)), 1 ether);
    }

    function testQuit() public {
        uint cdp = manager.open("ETH", address(this));
        weth.deposit.value(1 ether)();
        weth.approve(address(ethJoin), 1 ether);
        ethJoin.join(manager.urns(cdp), 1 ether);
        manager.frob(cdp, 1 ether, 50 ether);

        (uint ink, uint art) = vat.urns("ETH", manager.urns(cdp));
        assertEq(ink, 1 ether);
        assertEq(art, 50 ether);
        (ink, art) = vat.urns("ETH", address(this));
        assertEq(ink, 0);
        assertEq(art, 0);

        vat.hope(address(manager));
        manager.quit(cdp, address(this));
        (ink, art) = vat.urns("ETH", manager.urns(cdp));
        assertEq(ink, 0);
        assertEq(art, 0);
        (ink, art) = vat.urns("ETH", address(this));
        assertEq(ink, 1 ether);
        assertEq(art, 50 ether);
    }

    function testQuitOtherDst() public {
        uint cdp = manager.open("ETH", address(this));
        weth.deposit.value(1 ether)();
        weth.approve(address(ethJoin), 1 ether);
        ethJoin.join(manager.urns(cdp), 1 ether);
        manager.frob(cdp, 1 ether, 50 ether);

        (uint ink, uint art) = vat.urns("ETH", manager.urns(cdp));
        assertEq(ink, 1 ether);
        assertEq(art, 50 ether);
        (ink, art) = vat.urns("ETH", address(this));
        assertEq(ink, 0);
        assertEq(art, 0);

        user.doHope(vat, address(manager));
        user.doUrnAllow(manager, address(this), 1);
        manager.quit(cdp, address(user));
        (ink, art) = vat.urns("ETH", manager.urns(cdp));
        assertEq(ink, 0);
        assertEq(art, 0);
        (ink, art) = vat.urns("ETH", address(user));
        assertEq(ink, 1 ether);
        assertEq(art, 50 ether);
    }

    function testFailQuitOtherDst() public {
        uint cdp = manager.open("ETH", address(this));
        weth.deposit.value(1 ether)();
        weth.approve(address(ethJoin), 1 ether);
        ethJoin.join(manager.urns(cdp), 1 ether);
        manager.frob(cdp, 1 ether, 50 ether);

        (uint ink, uint art) = vat.urns("ETH", manager.urns(cdp));
        assertEq(ink, 1 ether);
        assertEq(art, 50 ether);
        (ink, art) = vat.urns("ETH", address(this));
        assertEq(ink, 0);
        assertEq(art, 0);

        user.doHope(vat, address(manager));
        manager.quit(cdp, address(user));
    }

    function testEnter() public {
        weth.deposit.value(1 ether)();
        weth.approve(address(ethJoin), 1 ether);
        ethJoin.join(address(this), 1 ether);
        vat.frob("ETH", address(this), address(this), address(this), 1 ether, 50 ether);
        uint cdp = manager.open("ETH", address(this));

        (uint ink, uint art) = vat.urns("ETH", manager.urns(cdp));
        assertEq(ink, 0);
        assertEq(art, 0);

        (ink, art) = vat.urns("ETH", address(this));
        assertEq(ink, 1 ether);
        assertEq(art, 50 ether);

        vat.hope(address(manager));
        manager.enter(address(this), cdp);

        (ink, art) = vat.urns("ETH", manager.urns(cdp));
        assertEq(ink, 1 ether);
        assertEq(art, 50 ether);

        (ink, art) = vat.urns("ETH", address(this));
        assertEq(ink, 0);
        assertEq(art, 0);
    }

    function testEnterOtherSrc() public {
        weth.deposit.value(1 ether)();
        weth.approve(address(ethJoin), 1 ether);
        ethJoin.join(address(user), 1 ether);
        user.doVatFrob(vat, "ETH", address(user), address(user), address(user), 1 ether, 50 ether);

        uint cdp = manager.open("ETH", address(this));

        (uint ink, uint art) = vat.urns("ETH", manager.urns(cdp));
        assertEq(ink, 0);
        assertEq(art, 0);

        (ink, art) = vat.urns("ETH", address(user));
        assertEq(ink, 1 ether);
        assertEq(art, 50 ether);

        user.doHope(vat, address(manager));
        user.doUrnAllow(manager, address(this), 1);
        manager.enter(address(user), cdp);

        (ink, art) = vat.urns("ETH", manager.urns(cdp));
        assertEq(ink, 1 ether);
        assertEq(art, 50 ether);

        (ink, art) = vat.urns("ETH", address(user));
        assertEq(ink, 0);
        assertEq(art, 0);
    }

    function testFailEnterOtherSrc() public {
        weth.deposit.value(1 ether)();
        weth.approve(address(ethJoin), 1 ether);
        ethJoin.join(address(user), 1 ether);
        user.doVatFrob(vat, "ETH", address(user), address(user), address(user), 1 ether, 50 ether);

        uint cdp = manager.open("ETH", address(this));

        user.doHope(vat, address(manager));
        manager.enter(address(user), cdp);
    }

    function testFailEnterOtherSrc2() public {
        weth.deposit.value(1 ether)();
        weth.approve(address(ethJoin), 1 ether);
        ethJoin.join(address(user), 1 ether);
        user.doVatFrob(vat, "ETH", address(user), address(user), address(user), 1 ether, 50 ether);

        uint cdp = manager.open("ETH", address(this));

        user.doUrnAllow(manager, address(this), 1);
        manager.enter(address(user), cdp);
    }

    function testEnterOtherCdp() public {
        weth.deposit.value(1 ether)();
        weth.approve(address(ethJoin), 1 ether);
        ethJoin.join(address(this), 1 ether);
        vat.frob("ETH", address(this), address(this), address(this), 1 ether, 50 ether);
        uint cdp = manager.open("ETH", address(this));
        manager.give(cdp, address(user));

        (uint ink, uint art) = vat.urns("ETH", manager.urns(cdp));
        assertEq(ink, 0);
        assertEq(art, 0);

        (ink, art) = vat.urns("ETH", address(this));
        assertEq(ink, 1 ether);
        assertEq(art, 50 ether);

        vat.hope(address(manager));
        user.doCdpAllow(manager, cdp, address(this), 1);
        manager.enter(address(this), cdp);

        (ink, art) = vat.urns("ETH", manager.urns(cdp));
        assertEq(ink, 1 ether);
        assertEq(art, 50 ether);

        (ink, art) = vat.urns("ETH", address(this));
        assertEq(ink, 0);
        assertEq(art, 0);
    }

    function testFailEnterOtherCdp() public {
        weth.deposit.value(1 ether)();
        weth.approve(address(ethJoin), 1 ether);
        ethJoin.join(address(this), 1 ether);
        vat.frob("ETH", address(this), address(this), address(this), 1 ether, 50 ether);
        uint cdp = manager.open("ETH", address(this));
        manager.give(cdp, address(user));

        vat.hope(address(manager));
        manager.enter(address(this), cdp);
    }

    function testFailEnterOtherCdp2() public {
        weth.deposit.value(1 ether)();
        weth.approve(address(ethJoin), 1 ether);
        ethJoin.join(address(this), 1 ether);
        vat.frob("ETH", address(this), address(this), address(this), 1 ether, 50 ether);
        uint cdp = manager.open("ETH", address(this));
        manager.give(cdp, address(user));

        user.doCdpAllow(manager, cdp, address(this), 1);
        manager.enter(address(this), cdp);
    }

    function testShift() public {
        weth.deposit.value(1 ether)();
        weth.approve(address(ethJoin), 1 ether);
        uint cdpSrc = manager.open("ETH", address(this));
        ethJoin.join(address(manager.urns(cdpSrc)), 1 ether);
        manager.frob(cdpSrc, 1 ether, 50 ether);
        uint cdpDst = manager.open("ETH", address(this));

        (uint ink, uint art) = vat.urns("ETH", manager.urns(cdpDst));
        assertEq(ink, 0);
        assertEq(art, 0);

        (ink, art) = vat.urns("ETH", manager.urns(cdpSrc));
        assertEq(ink, 1 ether);
        assertEq(art, 50 ether);

        manager.shift(cdpSrc, cdpDst);

        (ink, art) = vat.urns("ETH", manager.urns(cdpDst));
        assertEq(ink, 1 ether);
        assertEq(art, 50 ether);

        (ink, art) = vat.urns("ETH", manager.urns(cdpSrc));
        assertEq(ink, 0);
        assertEq(art, 0);
    }

    function testShiftOtherCdpDst() public {
        weth.deposit.value(1 ether)();
        weth.approve(address(ethJoin), 1 ether);
        uint cdpSrc = manager.open("ETH", address(this));
        ethJoin.join(address(manager.urns(cdpSrc)), 1 ether);
        manager.frob(cdpSrc, 1 ether, 50 ether);
        uint cdpDst = manager.open("ETH", address(this));
        manager.give(cdpDst, address(user));

        (uint ink, uint art) = vat.urns("ETH", manager.urns(cdpDst));
        assertEq(ink, 0);
        assertEq(art, 0);

        (ink, art) = vat.urns("ETH", manager.urns(cdpSrc));
        assertEq(ink, 1 ether);
        assertEq(art, 50 ether);

        user.doCdpAllow(manager, cdpDst, address(this), 1);
        manager.shift(cdpSrc, cdpDst);

        (ink, art) = vat.urns("ETH", manager.urns(cdpDst));
        assertEq(ink, 1 ether);
        assertEq(art, 50 ether);

        (ink, art) = vat.urns("ETH", manager.urns(cdpSrc));
        assertEq(ink, 0);
        assertEq(art, 0);
    }

    function testFailShiftOtherCdpDst() public {
        weth.deposit.value(1 ether)();
        weth.approve(address(ethJoin), 1 ether);
        uint cdpSrc = manager.open("ETH", address(this));
        ethJoin.join(address(manager.urns(cdpSrc)), 1 ether);
        manager.frob(cdpSrc, 1 ether, 50 ether);
        uint cdpDst = manager.open("ETH", address(this));
        manager.give(cdpDst, address(user));

        manager.shift(cdpSrc, cdpDst);
    }

    function testShiftOtherCdpSrc() public {
        weth.deposit.value(1 ether)();
        weth.approve(address(ethJoin), 1 ether);
        uint cdpSrc = manager.open("ETH", address(this));
        ethJoin.join(address(manager.urns(cdpSrc)), 1 ether);
        manager.frob(cdpSrc, 1 ether, 50 ether);
        uint cdpDst = manager.open("ETH", address(this));
        manager.give(cdpSrc, address(user));

        (uint ink, uint art) = vat.urns("ETH", manager.urns(cdpDst));
        assertEq(ink, 0);
        assertEq(art, 0);

        (ink, art) = vat.urns("ETH", manager.urns(cdpSrc));
        assertEq(ink, 1 ether);
        assertEq(art, 50 ether);

        user.doCdpAllow(manager, cdpSrc, address(this), 1);
        manager.shift(cdpSrc, cdpDst);

        (ink, art) = vat.urns("ETH", manager.urns(cdpDst));
        assertEq(ink, 1 ether);
        assertEq(art, 50 ether);

        (ink, art) = vat.urns("ETH", manager.urns(cdpSrc));
        assertEq(ink, 0);
        assertEq(art, 0);
    }

    function testFailShiftOtherCdpSrc() public {
        weth.deposit.value(1 ether)();
        weth.approve(address(ethJoin), 1 ether);
        uint cdpSrc = manager.open("ETH", address(this));
        ethJoin.join(address(manager.urns(cdpSrc)), 1 ether);
        manager.frob(cdpSrc, 1 ether, 50 ether);
        uint cdpDst = manager.open("ETH", address(this));
        manager.give(cdpSrc, address(user));

        manager.shift(cdpSrc, cdpDst);
    }
}

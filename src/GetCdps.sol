pragma solidity ^0.5.15;

import "./MrsCdpManager.sol";

contract GetCdps {
    function getCdpsAsc(address manager, address guy) external view returns (uint[] memory ids, address[] memory urns, bytes32[] memory ilks) {
        uint count = MrsCdpManager(manager).count(guy);
        ids = new uint[](count);
        urns = new address[](count);
        ilks = new bytes32[](count);
        uint i = 0;
        uint id = MrsCdpManager(manager).first(guy);

        while (id > 0) {
            ids[i] = id;
            urns[i] = MrsCdpManager(manager).urns(id);
            ilks[i] = MrsCdpManager(manager).ilks(id);
            (,id) = MrsCdpManager(manager).list(id);
            i++;
        }
    }

    function getCdpsDesc(address manager, address guy) external view returns (uint[] memory ids, address[] memory urns, bytes32[] memory ilks) {
        uint count = MrsCdpManager(manager).count(guy);
        ids = new uint[](count);
        urns = new address[](count);
        ilks = new bytes32[](count);
        uint i = 0;
        uint id = MrsCdpManager(manager).last(guy);

        while (id > 0) {
            ids[i] = id;
            urns[i] = MrsCdpManager(manager).urns(id);
            ilks[i] = MrsCdpManager(manager).ilks(id);
            (id,) = MrsCdpManager(manager).list(id);
            i++;
        }
    }
}

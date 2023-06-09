// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {Proxy} from "openzeppelin/proxy/Proxy.sol";
import {StorageSlot} from "openzeppelin/utils/StorageSlot.sol";

contract ERC721Creator is Proxy {
    constructor(string memory name, string memory symbol) {
        assert(_IMPLEMENTATION_SLOT == bytes32(uint256(keccak256("eip1967.proxy.implementation")) - 1));
        StorageSlot.getAddressSlot(_IMPLEMENTATION_SLOT).value = 0xa60e235c7e7e27AB9f5E7b5a7d67e82088314CA6;
        (bool success,) = 0xa60e235c7e7e27AB9f5E7b5a7d67e82088314CA6.delegatecall(
            abi.encodeWithSignature("initialize(string,string)", name, symbol)
        );
        require(success, "Initialization failed");
    }

    /**
     * @dev Storage slot with the address of the current implementation.
     * This is the keccak-256 hash of "eip1967.proxy.implementation" subtracted by 1, and is
     * validated in the constructor.
     */
    bytes32 internal constant _IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    /**
     * @dev Returns the current implementation address.
     */
    function implementation() public view returns (address) {
        return _implementation();
    }

    function _implementation() internal view override returns (address) {
        return StorageSlot.getAddressSlot(_IMPLEMENTATION_SLOT).value;
    }
}

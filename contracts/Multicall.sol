// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

interface IERC721Upgradeable {
    function ownerOf(uint256) external view returns (address);
}

contract Multicall is Initializable {
    function initialize() external initializer {}

    uint256 public totalAddresses;

    function getOwners(
        address collection,
        uint256 startId,
        uint256 endId
    ) external view returns (address[] memory addresses) {
        IERC721Upgradeable IContract = IERC721Upgradeable(collection);
        uint256 total = endId - startId + 1;
        addresses = new address[](total);
        for (uint256 i = 0; i < total; i++) {
            address a = IContract.ownerOf(startId + i);
            addresses[i] = a;
        }
    }
}

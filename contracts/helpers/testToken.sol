// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";

contract TestToken is Initializable, ERC20Upgradeable {
    function initialize() public initializer {
        __ERC20_init_unchained("test", "reward");
        faucet();
        decimals();
    }

    function faucet() public {
        _mint(msg.sender, 100000000);
    }

    function faucetTo(address _to, uint256 _amount) public {
        _mint(_to, _amount);
    }

    function decimals() public pure override returns (uint8) {
        return 6;
    }

    function faucet10000() public {
        _mint(msg.sender, 10000000000);
    }
}

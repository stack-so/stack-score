// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import {StackScore} from "../src/StackScore.sol";
import {StackScoreRenderer} from "../src/StackScoreRenderer.sol";
import {TraitLabel, Editors, FullTraitValue, AllowedEditor, EditorsLib} from "src/dynamic-traits/lib/TraitLabelLib.sol";
import {DisplayType} from "src/onchain/Metadata.sol";

contract SetTraitLabels is Script {
    // Constants
    address public constant CONTRACT_ADDRESS = 0x5555555Dd82Ed9a77C5032a7a6482B0C8ca564b0;

    function run() external {
        uint256 key = vm.envUint("PRIVATE_KEY");
        StackScore token = StackScore(CONTRACT_ADDRESS);
        vm.startBroadcast(key); // Start the broadcast.
        StackScoreRenderer renderer = new StackScoreRenderer();
        token.setRenderer(address(renderer));
        vm.stopBroadcast(); // Stop the broadcast.
    }
}

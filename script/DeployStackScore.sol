// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import {StackScore} from "../src/StackScore.sol";
import {StackScoreRenderer} from "../src/StackScoreRenderer.sol";

contract DeployStackScore is Script {
    // Constants
    address public constant expectedOwnerAddress =
    0x42c22eBD6f07FC052040137eEb3B8a1b7A38b275;
    address public constant CONTRACT_ADDRESS =
        0x555555Bc656836568C0f136626d55e9330b07EF8;
    bytes32 private constant SALT =
        0xccf586968f9ea99d74514258ad48968caf6613e616d68f077d48a72e1b9c8327;
    bytes32 private constant EXPECTED_CODE_HASH =
        0x696564991d477c6c7c5d7b18e75f39d9d7034865356c06d349c76c006b769188;

    // Variables
    StackScore public token;
    StackScoreRenderer public renderer;
    address public deployer;
    address public fundsReceiver;

    // Functions
    function assertCodeHash(address initialOwner) internal pure {
        bytes memory constructorArgs = abi.encode(initialOwner);
        // Log the constructorArgs
        console.logBytes(constructorArgs);

        bytes32 initCodeHash = keccak256(
            abi.encodePacked(
                type(StackScore).creationCode, constructorArgs
            )
        );
        console.logBytes32(initCodeHash);
        require(initCodeHash == EXPECTED_CODE_HASH, "Unexpected init code hash");
    }

    function assertAddress() public view {
        require(
            address(token) == CONTRACT_ADDRESS,
            "Deployed address does not match expected address"
        );
    }

    function assertExpectedOwner() public view {
        require(
            token.owner() == expectedOwnerAddress,
            "Owner address does not match expected address"
        );
    }

    function assertInitialOwner(address initialOwner) public pure {
        require(
            initialOwner == expectedOwnerAddress,
            "Initial owner address does not match expected address"
        );
    }

    function run() external {
        uint256 key = vm.envUint("PRIVATE_KEY"); // Get the private key from the environment.
        deployer = vm.addr(key); // Get the address of the private key.
        assertInitialOwner(deployer); // Assert the initial owner.
        assertCodeHash(deployer); // Assert the code hash.
        console.log(deployer);
        fundsReceiver = vm.envAddress("FUNDS_RECEIVER"); // Get the funds receiver address from the environment.
        vm.startBroadcast(key); // Start the broadcast with the private key.
        renderer = new StackScoreRenderer(); // Deploy the renderer contract.
        token = new StackScore{salt: SALT}(deployer); // Deploy the token contract.
        assertExpectedOwner(); // Assert the expected owner.
        token.setMintFeeRecipient(payable(fundsReceiver)); // Set the funds receiver.
        assertAddress(); // Assert the address of the token contract.
        vm.stopBroadcast(); // Stop the broadcast.
    }
}

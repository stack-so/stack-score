// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import {StackScore} from "../src/StackScore.sol";
import {StackScoreRenderer} from "../src/StackScoreRenderer.sol";

contract DeployStackScore is Script {
    // Constants
    address public constant expectedOwnerAddress = 0x42c22eBD6f07FC052040137eEb3B8a1b7A38b275;
    address public constant CONTRACT_ADDRESS = 0x5555551A4a5bfAc620166A05F815F0c1136da43F;
    bytes32 private constant SALT = 0x5980aa63fecf09543c295ae0d806fbb60ca93477ccd2b0310ee6c0740b2c62ef;
    bytes32 private constant EXPECTED_CODE_HASH = 0x0710ab49c20561f0ab210a2f25eae8eeddab868770bcafdc8ad24463cb3d7d71;

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

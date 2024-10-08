// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import {StackScore} from "../src/StackScore.sol";
import {StackScoreRenderer} from "../src/StackScoreRenderer.sol";

contract DeployStackScore is Script {
    // Constants
    address public constant expectedOwnerAddress = 0x42c22eBD6f07FC052040137eEb3B8a1b7A38b275;
    address public constant CONTRACT_ADDRESS = 0x555555Ce7c6390586a7a1738eF482C43205c2ED2;
    bytes32 private constant SALT = 0x6751fdf39332ede6bd70d6f1851c1b263e652d84755dd67bc3003c157954b3e6;
    bytes32 private constant EXPECTED_CODE_HASH = 0xd0b11c17ec098618d4aca85f5ff089f1e012bbdef94dee3c2e4a62e6cf533aa8;

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

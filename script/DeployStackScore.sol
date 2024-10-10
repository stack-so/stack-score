// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import {StackScore} from "../src/StackScore.sol";
import {StackScoreRenderer} from "../src/StackScoreRenderer.sol";
import {TraitLabel, Editors, FullTraitValue, AllowedEditor, EditorsLib} from "src/dynamic-traits/lib/TraitLabelLib.sol";
import {DisplayType} from "src/onchain/Metadata.sol";

contract DeployStackScore is Script {
    // Constants
    address public constant expectedOwnerAddress = 0x42c22eBD6f07FC052040137eEb3B8a1b7A38b275;
    address public constant CONTRACT_ADDRESS = 0x5555555aB5B0895aFddDF035Bb1214933ebCDDB3;
    bytes32 private constant SALT = 0x8de5aa2b723bc3c64769a73045c28c9cfb1aa550ddbc4fd0739868ebdef0dffa;
    bytes32 private constant EXPECTED_CODE_HASH = 0x9e238789663e681781934e8e497bc793aadae2e1e17412d9cf4b44e29e052f36;

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
        address signer = 0xAf052e84C39A5F8DA2027acF83A0fcd6fCF1D8B8;
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
        token.setRenderer(address(renderer)); // Set the renderer address.
        TraitLabel memory scoreLabel = TraitLabel({
            fullTraitKey: "score",
            traitLabel: "Score",
            acceptableValues: new string[](0),
            fullTraitValues: new FullTraitValue[](0),
            displayType: DisplayType.Number,
            editors: Editors.wrap(EditorsLib.toBitMap(AllowedEditor.Self)),
            required: true
        });
        token.setTraitLabel(bytes32("score"), scoreLabel);
        TraitLabel memory paletteLabel = TraitLabel({
            fullTraitKey: "paletteIndex",
            traitLabel: "PaletteIndex",
            acceptableValues: new string[](0),
            fullTraitValues: new FullTraitValue[](0),
            displayType: DisplayType.Number,
            editors: Editors.wrap(EditorsLib.toBitMap(AllowedEditor.Self)),
            required: true
        });
        token.setTraitLabel(bytes32("paletteIndex"), paletteLabel);
        TraitLabel memory updatedLabel = TraitLabel({
            fullTraitKey: "updatedAt",
            traitLabel: "UpdatedAt",
            acceptableValues: new string[](0),
            fullTraitValues: new FullTraitValue[](0),
            displayType: DisplayType.Number,
            editors: Editors.wrap(EditorsLib.toBitMap(AllowedEditor.Self)),
            required: true
        });
        token.setTraitLabel(bytes32("updatedAt"), updatedLabel);
        token.setSigner(signer); // Set the signer address.
        assertAddress(); // Assert the address of the token contract.
        vm.stopBroadcast(); // Stop the broadcast.
    }
}

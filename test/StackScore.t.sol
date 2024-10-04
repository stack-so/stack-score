// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import {StackScore} from "src/StackScore.sol";
import {StackScoreRenderer} from "src/StackScoreRenderer.sol";

import {
TraitLabelStorage,
TraitLabelStorageLib,
TraitLabel,
TraitLabelLib,
Editors,
FullTraitValue,
StoredTraitLabel,
AllowedEditor,
TraitLib,
StoredTraitLabelLib,
EditorsLib
} from "src/dynamic-traits/lib/TraitLabelLib.sol";
import {DisplayType} from "src/onchain/Metadata.sol";
import {ECDSA} from "solady/utils/ECDSA.sol";

contract StackScoreTest is Test {
    StackScore token;
    StackScoreRenderer renderer;

    address public signer;
    uint256 public signerPk;

    function setUp() public {
        (address alice, uint256 alicePk) = makeAddrAndKey("alice");
        signer = alice;
        signerPk = alicePk;
        token = new StackScore();
        renderer = new StackScoreRenderer();
        token.setRenderer(address(renderer));
        token.setSigner(signer);
        token.transferOwnership(signer);
        _setLabel();
    }

    function testOnlyContractCanSetTraitLabel() public {
        vm.expectRevert();
        TraitLabel memory label = TraitLabel({
            fullTraitKey: "score",
            traitLabel: "Score",
            acceptableValues: new string[](0),
            fullTraitValues: new FullTraitValue[](0),
            displayType: DisplayType.Number,
            // Only the contract owner can set the trait label.
            editors: Editors.wrap(EditorsLib.toBitMap(AllowedEditor.Self)),
            required: true
        });
        token.setTraitLabel(bytes32("score"), label);
    }

    function testOnlyOwnerCanSetTrait() public {
        // This will work.
        vm.prank(signer);
        TraitLabel memory label = TraitLabel({
            fullTraitKey: "score",
            traitLabel: "Score",
            acceptableValues: new string[](0),
            fullTraitValues: new FullTraitValue[](0),
            displayType: DisplayType.Number,
            editors: Editors.wrap(EditorsLib.toBitMap(AllowedEditor.Self)),
            required: true
        });
        token.setTraitLabel(bytes32("score"), label);

        // But this will fail.
        vm.expectRevert();
        token.setTrait(1, "score", bytes32(uint256(68)));
        vm.stopPrank();
    }

    function testMintWithScore() public {
        // Props
        address account = address(1);
        vm.deal(account, 1 ether);
        uint256 score = 245;
        // Signature
        bytes memory signature = signScore(account, score);
        // Mint
        vm.prank(account);
        token.mintWithScore{value: 0.001 ether}(account, score, signature);
        console.log(token.tokenURI(1));

        // Check the score.
        assertEq(token.getScore(account), uint256(score));

        // Update the color palette.
        uint256 paletteIndex = 3;
        vm.prank(account);
        token.updatePalette(1, paletteIndex);
        assertEq(token.getPaletteIndex(1), paletteIndex);
        console.log(token.tokenURI(1));
    }

    // The token should not be allowed to transfer after minting.
    function testSoulbound() public {
        // Props
        address account = address(1);
        vm.deal(account, 1 ether);
        uint256 score = 1001;
        // Signature
        bytes memory signature = signScore(account, score);
        // Mint
        vm.prank(account);
        token.mintWithScore{value: 0.001 ether}(account, score, signature);
        // Transfer
        vm.prank(account);
        vm.expectRevert();
        token.transferFrom(account, address(2), 1);
    }

    function testGetColorsFromRenderer() public {
        // Loop through 3 palettes and log the colors:
        for (uint256 i = 0; i < 3; i++) {
            string[3] memory colors = renderer.getPaletteAsHexStrings(i);
            console.log("palette ", i);
            console.log(colors[0]);
            console.log(colors[1]);
            console.log(colors[2]);
        }
    }

    function signScore(address account, uint256 score) public returns (bytes memory) {
        bytes32 messageHash = keccak256(abi.encodePacked(account, score));
        bytes32 hash = ECDSA.toEthSignedMessageHash(messageHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPk, hash);
        bytes memory signature = abi.encodePacked(r, s, v);
        return signature;
    }

    function testName() public {
        assertEq(token.name(), "Stack Score");
    }

    function testSymbol() public {
        assertEq(token.symbol(), "Stack_Score");
    }

    function _setLabel() internal {
        vm.prank(signer);
        TraitLabel memory label = TraitLabel({
            fullTraitKey: "score",
            traitLabel: "Score",
            acceptableValues: new string[](0),
            fullTraitValues: new FullTraitValue[](0),
            displayType: DisplayType.Number,
            editors: Editors.wrap(EditorsLib.toBitMap(AllowedEditor.Self)),
            required: true
        });
        token.setTraitLabel(bytes32("score"), label);

        vm.prank(signer);
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
    }
}

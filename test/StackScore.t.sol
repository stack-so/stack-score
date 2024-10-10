// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import {StackScore} from "src/StackScore.sol";
import {StackScoreRenderer} from "src/StackScoreRenderer.sol";
import {ECDSA} from "solady/utils/ECDSA.sol";
import {TraitLabel, Editors, FullTraitValue, AllowedEditor, EditorsLib} from "src/dynamic-traits/lib/TraitLabelLib.sol";
import {DisplayType} from "src/onchain/Metadata.sol";
import {LibString} from "solady/utils/LibString.sol";

contract StackScoreTest is Test {
    /// @notice StackScore token contract.
    StackScore token;
    /// @notice StackScoreRenderer contract.
    StackScoreRenderer renderer;

    /// @notice Address of the public key signer.
    address public signer;
    /// @notice Public key of the signer.
    uint256 public signerPk;
    /// @notice Address of the owner.
    address public owner;
    /// @notice Address of test user 1.
    address public user1;
    /// @notice Address of test user 2.
    address public user2;
    /// @notice Address of the mint fee recipient.
    address public mintFeeRecipient;

    /// @notice Unauthorized error
    /// @dev This error is thrown when a user is not authorized to perform an action.
    error Unauthorized();

    /// @notice Test setup function.
    /// @dev This function is called before each test.
    /// @dev It initializes the token contract and sets up the test environment.
    function setUp() public {
        (address alice, uint256 alicePk) = makeAddrAndKey("alice");
        signer = alice;
        signerPk = alicePk;
        owner = address(this);
        user1 = address(0x1);
        user2 = address(0x2);
        mintFeeRecipient = address(0x3);

        token = new StackScore(address(this));
        renderer = new StackScoreRenderer();
        token.setRenderer(address(renderer));
        token.setSigner(signer);
        token.setMintFeeRecipient(mintFeeRecipient);
        token.transferOwnership(signer);
        _setLabel();

        vm.deal(user1, 1 ether);
        vm.deal(user2, 1 ether);
    }

    function testInitialState() public view {
        assertEq(token.name(), "Stack Score");
        assertEq(token.symbol(), "STACK_SCORE");
        assertEq(token.version(), "1");
        assertEq(token.signer(), signer);
        assertEq(token.mintFee(), 0.001 ether);
        assertEq(token.getCurrentId(), 0);
        assertEq(token.getRenderer(), address(renderer));
        assertEq(token.mintFeeRecipient(), mintFeeRecipient);
    }

    function testMint() public {
        vm.prank(user1);
        uint256 tokenId = token.mint{value: 0.001 ether}(user1);
        assertEq(tokenId, 1);
        assertEq(token.ownerOf(1), user1);
        assertEq(token.balanceOf(user1), 1);
        assertEq(token.getCurrentId(), 1);
    }

    function testMintEmitsEvent() public {
        vm.prank(user1);
        vm.expectEmit(true, true, false, true);
        emit StackScore.Minted(user1, 1);
        token.mint{value: 0.001 ether}(user1);
    }

    function testMintFeeTransfer() public {
        uint256 initialBalance = mintFeeRecipient.balance;
        vm.prank(user1);
        token.mint{value: 0.001 ether}(user1);
        assertEq(mintFeeRecipient.balance, initialBalance + 0.001 ether);
    }

    function testMintWithInsufficientFee() public {
        vm.prank(user1);
        vm.expectRevert(StackScore.InsufficientFee.selector);
        token.mint{value: 0.0009 ether}(user1);
    }

    function testMintOnlyOneTokenPerAddress() public {
        vm.startPrank(user1);
        token.mint{value: 0.001 ether}(user1);
        vm.expectRevert(StackScore.OneTokenPerAddress.selector);
        token.mint{value: 0.001 ether}(user1);
        vm.stopPrank();
    }

    function testMintWithScore() public {
        uint256 score = 245;
        uint256 timestamp = block.timestamp;
        bytes memory signature = signScore(user1, score, timestamp);

        vm.prank(user1);
        uint256 tokenId = token.mintWithScore{value: 0.001 ether}(user1, score, timestamp, signature);

        assertEq(tokenId, 1);
        assertEq(token.getScore(user1), score);
    }

    function testMintWithScoreAndPalette() public {
        uint256 score = 245;
        uint256 timestamp = block.timestamp;
        uint256 palette = 3;
        bytes memory signature = signScore(user1, score, timestamp);

        vm.prank(user1);
        uint256 tokenId = token.mintWithScoreAndPalette{value: 0.001 ether}(user1, score, timestamp, palette, signature);

        assertEq(tokenId, 1);
        assertEq(token.getScore(user1), score);
        assertEq(token.getPaletteIndex(tokenId), palette);
    }

    function testUpdateScore() public {
        vm.prank(user1);
        uint256 tokenId = token.mint{value: 0.001 ether}(user1);

        uint256 newScore = 300;
        uint256 timestamp = block.timestamp;
        bytes memory signature = signScore(user1, newScore, timestamp);

        vm.prank(user1);
        vm.expectEmit(true, true, true, true);
        emit StackScore.ScoreUpdated(user1, tokenId, 0, newScore);
        token.updateScore(tokenId, newScore, timestamp, signature);

        assertEq(token.getScore(user1), newScore);
    }

    function testGetScore() public {
        vm.prank(user1);
        uint256 tokenId = token.mint{value: 0.001 ether}(user1);

        uint256 score = 245;
        uint256 timestamp = block.timestamp;
        bytes memory signature = signScore(user1, score, timestamp);

        vm.prank(user1);
        token.updateScore(tokenId, score, timestamp, signature);

        assertEq(token.getScore(user1), score);
    }

    function testGetScoreAndUpdatedAt() public {
        vm.prank(user1);
        uint256 tokenId = token.mint{value: 0.001 ether}(user1);

        uint256 scoreInput = 245;
        uint256 timestamp = block.timestamp;
        bytes memory signature = signScore(user1, scoreInput, timestamp);

        vm.prank(user1);
        token.updateScore(tokenId, scoreInput, timestamp, signature);

        (
            uint256 scoreResult,
            uint256 updatedAt
        ) = token.getScoreAndLastUpdated(user1);

        assertEq(scoreResult, scoreInput);
        assertEq(updatedAt, timestamp);
    }

    function testUpdateScoreWithInvalidSignature() public {
        vm.prank(user1);
        uint256 tokenId = token.mint{value: 0.001 ether}(user1);

        uint256 newScore = 300;
        uint256 timestamp = block.timestamp;
        bytes memory signature = signScore(user2, newScore, timestamp); // Using wrong address

        vm.prank(user1);
        vm.expectRevert(StackScore.InvalidSignature.selector);
        token.updateScore(tokenId, newScore, timestamp, signature);
    }

    function testUpdateScoreWithOldTimestamp() public {
        vm.prank(user1);
        uint256 tokenId = token.mint{value: 0.001 ether}(user1);

        uint256 oldScore = 200;
        uint256 oldTimestamp = block.timestamp;
        bytes memory oldSignature = signScore(user1, oldScore, oldTimestamp);

        vm.prank(user1);
        token.updateScore(tokenId, oldScore, oldTimestamp, oldSignature);

        uint256 newScore = 300;
        uint256 newTimestamp = oldTimestamp - 1; // Using an older timestamp
        bytes memory newSignature = signScore(user1, newScore, newTimestamp);

        vm.prank(user1);
        vm.expectRevert(StackScore.TimestampTooOld.selector);
        token.updateScore(tokenId, newScore, newTimestamp, newSignature);
    }

    function testUpdatePalette() public {
        vm.prank(user1);
        uint256 tokenId = token.mint{value: 0.001 ether}(user1);

        uint256 newPalette = 5;
        vm.prank(user1);
        token.updatePalette(tokenId, newPalette);

        assertEq(token.getPaletteIndex(tokenId), newPalette);
    }

    function testUpdatePaletteOnlyOwner() public {
        vm.prank(user1);
        uint256 tokenId = token.mint{value: 0.001 ether}(user1);

        uint256 newPalette = 5;
        vm.prank(user2);
        vm.expectRevert(StackScore.OnlyTokenOwner.selector);
        token.updatePalette(tokenId, newPalette);
    }

    function testSoulbound() public {
        vm.prank(user1);
        uint256 tokenId = token.mint{value: 0.001 ether}(user1);

        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(StackScore.TokenLocked.selector, tokenId));
        token.transferFrom(user1, user2, tokenId);
    }

    function testSetRendererOnlyOwner() public {
        address newRenderer = address(0x123);
        vm.prank(signer);
        token.setRenderer(newRenderer);
        assertEq(token.getRenderer(), newRenderer);

        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(Unauthorized.selector));
        token.setRenderer(address(0x456));
    }

    function testSetSignerOnlyOwner() public {
        address newSigner = address(0x123);
        vm.prank(signer);
        token.setSigner(newSigner);
        assertEq(token.signer(), newSigner);

        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(Unauthorized.selector));
        token.setSigner(address(0x456));
    }

    function testSetMintFeeOnlyOwner() public {
        uint256 newFee = 0.002 ether;
        vm.prank(signer);
        vm.expectEmit(true, true, false, true);
        emit StackScore.MintFeeUpdated(0.001 ether, newFee);
        token.setMintFee(newFee);
        assertEq(token.mintFee(), newFee);

        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(Unauthorized.selector));
        token.setMintFee(0.003 ether);
    }

    function testSetMintFeeRecipientOnlyOwner() public {
        address newRecipient = address(0x123);
        vm.prank(signer);
        token.setMintFeeRecipient(newRecipient);
        assertEq(token.mintFeeRecipient(), newRecipient);

        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(Unauthorized.selector));
        token.setMintFeeRecipient(address(0x456));
    }

    function testTokenURI() public {
        vm.prank(user1);
        uint256 tokenId = token.mint{value: 0.001 ether}(user1);

        string memory uri = token.tokenURI(tokenId);
        assertTrue(bytes(uri).length > 0);

        assertTrue(LibString.startsWith(uri, "{\"name\":\"Stack Score\""));
        assertTrue(LibString.contains(uri, "data:image/svg+xml;base64,"));
    }

    function testLocked() public {
        vm.prank(user1);
        uint256 tokenId = token.mint{value: 0.001 ether}(user1);

        assertTrue(token.locked(tokenId));
    }

    function testMintWithReferral() public {
        address referrer = address(0x4);
        uint256 initialMintFeeRecipientBalance = mintFeeRecipient.balance;
        uint256 initialReferrerBalance = referrer.balance;

        vm.prank(user1);
        uint256 tokenId = token.mintWithReferral{value: 0.001 ether}(user1, referrer);

        assertEq(tokenId, 1);
        assertEq(token.ownerOf(1), user1);
        assertEq(token.balanceOf(user1), 1);
        assertEq(token.getCurrentId(), 1);

        // Check referral fee distribution
        uint256 referralFee = (0.001 ether * token.referralBps()) / 10000;
        assertEq(referrer.balance, initialReferrerBalance + referralFee);
        assertEq(mintFeeRecipient.balance, initialMintFeeRecipientBalance + (0.001 ether - referralFee));
    }

    function testMintWithScoreAndReferral() public {
        address referrer = address(0x4);
        uint256 score = 245;
        uint256 timestamp = block.timestamp;
        bytes memory signature = signScore(user1, score, timestamp);

        uint256 initialMintFeeRecipientBalance = mintFeeRecipient.balance;
        uint256 initialReferrerBalance = referrer.balance;

        vm.prank(user1);
        uint256 tokenId = token.mintWithScoreAndReferral{value: 0.001 ether}(user1, score, timestamp, referrer, signature);

        assertEq(tokenId, 1);
        assertEq(token.ownerOf(1), user1);
        assertEq(token.balanceOf(user1), 1);
        assertEq(token.getCurrentId(), 1);
        assertEq(token.getScore(user1), score);

        // Check referral fee distribution
        uint256 referralFee = (0.001 ether * token.referralBps()) / 10000;
        assertEq(referrer.balance, initialReferrerBalance + referralFee);
        assertEq(mintFeeRecipient.balance, initialMintFeeRecipientBalance + (0.001 ether - referralFee));
    }

    function testMintWithScoreAndReferralAndPalette() public {
        address referrer = address(0x4);
        uint256 score = 245;
        uint256 timestamp = block.timestamp;
        uint256 palette = 3;
        bytes memory signature = signScore(user1, score, timestamp);

        uint256 initialMintFeeRecipientBalance = mintFeeRecipient.balance;
        uint256 initialReferrerBalance = referrer.balance;

        vm.prank(user1);
        uint256 tokenId = token.mintWithScoreAndReferralAndPalette{value: 0.001 ether}(user1, score, timestamp, referrer, palette, signature);

        assertEq(tokenId, 1);
        assertEq(token.ownerOf(1), user1);
        assertEq(token.balanceOf(user1), 1);
        assertEq(token.getCurrentId(), 1);
        assertEq(token.getScore(user1), score);
        assertEq(token.getPaletteIndex(tokenId), palette);

        // Check referral fee distribution
        uint256 referralFee = (0.001 ether * token.referralBps()) / 10000;
        assertEq(referrer.balance, initialReferrerBalance + referralFee);
        assertEq(mintFeeRecipient.balance, initialMintFeeRecipientBalance + (0.001 ether - referralFee));
    }

    function testMintWithReferralInsufficientFee() public {
        address referrer = address(0x4);
        vm.prank(user1);
        vm.expectRevert(StackScore.InsufficientFee.selector);
        token.mintWithReferral{value: 0.0009 ether}(user1, referrer);
    }

    function testSetReferralBpsOnlyOwner() public {
        uint256 newReferralBps = 100; // 1%
        vm.prank(signer);
        token.setReferralBps(newReferralBps);
        assertEq(token.referralBps(), newReferralBps);

        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(Unauthorized.selector));
        token.setReferralBps(200);
    }

    function testReferralFeesWithDifferentBPS() public {
        vm.startPrank(signer);
        token.setReferralBps(100); // 1%
        vm.stopPrank();

        address referrer = address(0x4);
        uint256 initialMintFeeRecipientBalance = mintFeeRecipient.balance;
        uint256 initialReferrerBalance = referrer.balance;

        vm.prank(user1);
        token.mintWithReferral{value: 0.001 ether}(user1, referrer);

        uint256 referralFee = (0.001 ether * 100) / 10000; // 1% of 0.001 ether
        assertEq(referrer.balance, initialReferrerBalance + referralFee);
        assertEq(mintFeeRecipient.balance, initialMintFeeRecipientBalance + (0.001 ether - referralFee));
    }

    function testReferralFeesWithZeroBPS() public {
        vm.startPrank(signer);
        token.setReferralBps(0); // 0%
        vm.stopPrank();

        address referrer = address(0x4);
        uint256 initialMintFeeRecipientBalance = mintFeeRecipient.balance;
        uint256 initialReferrerBalance = referrer.balance;

        vm.prank(user1);
        token.mintWithReferral{value: 0.001 ether}(user1, referrer);

        assertEq(referrer.balance, initialReferrerBalance); // Referrer should receive nothing
        assertEq(mintFeeRecipient.balance, initialMintFeeRecipientBalance + 0.001 ether); // MintFeeRecipient should receive full amount
    }

    function testReferralFeesWithMaxBPS() public {
        vm.startPrank(signer);
        token.setReferralBps(10000); // 100%
        vm.stopPrank();

        address referrer = address(0x4);
        uint256 initialMintFeeRecipientBalance = mintFeeRecipient.balance;
        uint256 initialReferrerBalance = referrer.balance;

        vm.prank(user1);
        token.mintWithReferral{value: 0.001 ether}(user1, referrer);

        assertEq(referrer.balance, initialReferrerBalance + 0.001 ether); // Referrer should receive full amount
        assertEq(mintFeeRecipient.balance, initialMintFeeRecipientBalance); // MintFeeRecipient should receive nothing
    }

    function testSignatureReplayProtection() public {
        vm.prank(user1);
        uint256 tokenId = token.mint{value: 0.001 ether}(user1);

        uint256 newScore = 300;
        uint256 timestamp = block.timestamp;
        bytes memory signature = signScore(user1, newScore, timestamp);

        vm.prank(user1);
        token.updateScore(tokenId, newScore, timestamp, signature);

        // Attempt to use the same signature again
        vm.prank(user1);
        vm.expectRevert(StackScore.SignatureAlreadyUsed.selector);
        token.updateScore(tokenId, newScore, timestamp, signature);
    }

    function testDifferentSignatures() public {
        vm.prank(user1);
        uint256 tokenId = token.mint{value: 0.001 ether}(user1);

        uint256 score = 300;
        uint256 newScore = 301;
        uint256 timestamp = block.timestamp;
        uint256 timestamp2 = timestamp + 1;
        bytes memory signature1 = signScore(user1, score, timestamp);
        bytes memory signature2 = signScore(user1, newScore, timestamp2);

        assertTrue(keccak256(signature1) != keccak256(signature2));

        vm.prank(user1);
        token.updateScore(tokenId, score, timestamp, signature1);

        // Second signature should still be valid
        vm.prank(user1);
        token.updateScore(tokenId, newScore, timestamp2, signature2);
    }

    function testTokenURIComponents() public {
        vm.prank(user1);
        uint256 tokenId = token.mint{value: 0.001 ether}(user1);

        string memory uri = token.tokenURI(tokenId);

        assertTrue(LibString.contains(uri, "\"name\":\"Stack Score\""));
        assertTrue(LibString.contains(uri, "\"description\":\"A dynamic, onchain, soulbound reputation score\""));
        assertTrue(LibString.contains(uri, "\"image\":\"data:image/svg+xml;base64,"));
        assertTrue(LibString.contains(uri, "\"attributes\":["));
    }

    function testTokenURIUpdatesWithScore() public {
        vm.prank(user1);
        uint256 tokenId = token.mint{value: 0.001 ether}(user1);

        string memory initialUri = token.tokenURI(tokenId);

        uint256 newScore = 300;
        uint256 timestamp = block.timestamp;
        bytes memory signature = signScore(user1, newScore, timestamp);

        vm.prank(user1);
        token.updateScore(tokenId, newScore, timestamp, signature);

        string memory updatedUri = token.tokenURI(tokenId);

        assertTrue(keccak256(bytes(initialUri)) != keccak256(bytes(updatedUri)));
        assertTrue(LibString.contains(updatedUri, LibString.toString(newScore)));
    }

    function testErrorOnTransferAttempt() public {
        vm.prank(user1);
        uint256 tokenId = token.mint{value: 0.001 ether}(user1);

        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(StackScore.TokenLocked.selector, tokenId));
        token.transferFrom(user1, user2, tokenId);
    }

    function testErrorOnInvalidTimestamp() public {
        vm.prank(user1);
        uint256 tokenId = token.mint{value: 0.001 ether}(user1);

        uint256 oldScore = 200;
        uint256 oldTimestamp = block.timestamp;
        bytes memory oldSignature = signScore(user1, oldScore, oldTimestamp);

        vm.prank(user1);
        token.updateScore(tokenId, oldScore, oldTimestamp, oldSignature);

        uint256 newScore = 300;
        uint256 newTimestamp = oldTimestamp - 1; // Using an older timestamp
        bytes memory newSignature = signScore(user1, newScore, newTimestamp);

        vm.prank(user1);
        vm.expectRevert(StackScore.TimestampTooOld.selector);
        token.updateScore(tokenId, newScore, newTimestamp, newSignature);
    }

    function testErrorOnUnauthorizedPaletteUpdate() public {
        vm.prank(user1);
        uint256 tokenId = token.mint{value: 0.001 ether}(user1);

        vm.prank(user2);
        vm.expectRevert(StackScore.OnlyTokenOwner.selector);
        token.updatePalette(tokenId, 5);
    }

    function testErrorOnMintWithInsufficientFee() public {
        vm.prank(user1);
        vm.expectRevert(StackScore.InsufficientFee.selector);
        token.mint{value: 0.0009 ether}(user1);
    }

    function testErrorOnSecondMintAttempt() public {
        vm.startPrank(user1);
        token.mint{value: 0.001 ether}(user1);
        vm.expectRevert(StackScore.OneTokenPerAddress.selector);
        token.mint{value: 0.001 ether}(user1);
        vm.stopPrank();
    }

    // Helper functions

    function signScore(address account, uint256 score, uint256 timestamp) internal view returns (bytes memory) {
        bytes32 messageHash = keccak256(abi.encodePacked(account, score, timestamp));
        bytes32 hash = ECDSA.toEthSignedMessageHash(messageHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPk, hash);
        return abi.encodePacked(r, s, v);
    }

    function _setLabel() internal {
        vm.startPrank(signer);

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

        vm.stopPrank();
    }
}

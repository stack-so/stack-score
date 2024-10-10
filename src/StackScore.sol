// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

// External libraries
import {LibString} from "solady/utils/LibString.sol";
import {ReentrancyGuard} from "solady/utils/ReentrancyGuard.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";
import {ECDSA} from "solady/utils/ECDSA.sol";
import {Solarray} from "solarray/Solarray.sol";
// Internal imports
import {json} from "./onchain/json.sol";
import {Metadata, DisplayType} from "./onchain/Metadata.sol";
import {TraitLib} from "./dynamic-traits/lib/TraitLabelLib.sol";
import {AbstractNFT} from "./AbstractNFT.sol";
import {StackScoreRenderer} from "./StackScoreRenderer.sol";
import {IERC5192} from "./interfaces/IERC5192.sol";

/// @title StackScore
/// @notice A fully onchain, dynamic, soulbound token for reputation scores
/// @notice Each score is rendered as an onchain SVG.
/// @author strangechances (g@stack.so)
contract StackScore is AbstractNFT, IERC5192, ReentrancyGuard {
    /// @notice The current version of the contract.
    string public constant version = "1";
    /// @notice The name of the token.
    string internal constant _tokenName = "Stack Score";
    /// @notice The description of the token.
    string internal constant _tokenDescription = "A dynamic, onchain, soulbound reputation score";
    /// @notice The signer address.
    /// @dev The signer address is used to verify the score signature.
    address public signer;
    /// @notice The mint fee.
    uint256 public mintFee = 0.001 ether;
    /// @notice The referral fee percentage, in basis points.
    /// @dev This is a percentage of the mint fee, in basis points (100 basis points is 1%).
    uint256 public referralBps = 5000;
    /// @notice Address to token ID mapping.
    /// @dev Prevents multiple tokens from being minted for the same address.
    mapping(address => uint256) public addressToTokenId;
    /// @notice Signature mapping, to prevent replay attacks.
    /// @dev This is used to prevent replay attacks.
    mapping(bytes32 => bool) internal signatures;
    /// @notice The current token ID.
    uint256 internal currentId;
    /// @notice The renderer contract.
    /// @dev This contract is used to render the SVG image.
    StackScoreRenderer internal renderer;
    /// @notice The mint fee recipient.
    /// @dev This address receives the mint fee, minus any referral fee.
    address public mintFeeRecipient;

    /// @notice Emitted when the score is updated.
    event ScoreUpdated(address account, uint256 tokenId, uint256 oldScore, uint256 newScore);
    /// @notice Emitted when a token is minted.
    event Minted(address to, uint256 tokenId);
    /// @notice Emitted when a referral is paid.
    event ReferralPaid(address referrer, address referred, uint256 amount);
    /// @notice Emitted when the mint fee is updated.
    event MintFeeUpdated(uint256 oldFee, uint256 newFee);
    /// @notice Emitted when the mint fee recipient is updated.
    event MintFeeRecipientUpdated(address oldRecipient, address newRecipient);
    /// @notice Emitted when the referral fee is updated.
    /// @dev This is a percentage of the mint fee, in basis points (100 basis points is 1%).
    event ReferralBpsUpdated(uint256 oldBps, uint256 newBps);
    /// @notice Emitted when the renderer contract is updated.
    event RendererUpdated(address oldRenderer, address newRenderer);
    /// @notice Emitted when the signer address is updated.
    event SignerUpdated(address oldSigner, address newSigner);

    /// @notice Error thrown when the token is locked upon transfer.
    /// @dev The token is Soulbound according to the ERC-5192 standard.
    error TokenLocked(uint256 tokenId);
    /// @notice Error thrown when the signature is invalid.
    error InvalidSignature();
    /// @notice Error thrown when the signature is already used.
    error SignatureAlreadyUsed();
    /// @notice Error thrown when the mint fee is insufficient.
    error InsufficientFee();
    /// @notice Error thrown when the sender is not the token owner.
    /// @dev For example, when a non-owner tries to update a score's color palette.
    error OnlyTokenOwner();
    /// @notice Error thrown when a given timestamp is older than the last update for a score.
    error TimestampTooOld();
    /// @notice Error thrown if mint called for the second time for the same address.
    error OneTokenPerAddress();

    /// @notice Constructor
    /// @dev Set the name and symbol of the token.
    constructor(address initialOwner) AbstractNFT(_tokenName, "STACK_SCORE") {
        _initializeOwner(initialOwner);
    }

    /// @notice Mint a new soulbound token.
    /// @dev Mint a new token and lock it.
    /// @dev The mint fee is sent to the mint fee recipient.
    /// @dev Does not require a signature, since there is no score.
    /// @param to The address to mint the token to.
    /// @return The token ID.
    function mint(address to) payable public nonReentrant returns (uint256) {
        _assertSufficientFee();

        SafeTransferLib.safeTransferETH(mintFeeRecipient, msg.value);
        _mintTo(to);

        return currentId;
    }

    /// @notice Mint a new soulbound token with a referral.
    /// @dev Mint a new token, lock it, and send a referral fee.
    /// @dev Does not need to check a signature, since there is no score.
    /// @param to The address to mint the token to.
    /// @param referrer The address to send the referral fee to.
    /// @return The token ID.
    function mintWithReferral(
        address to,
        address referrer
    ) payable public nonReentrant returns (uint256) {
        _assertSufficientFee();

        uint256 referralAmount = _getReferralAmount(msg.value);
        SafeTransferLib.safeTransferETH(mintFeeRecipient, msg.value - referralAmount);
        emit ReferralPaid(referrer, to, referralAmount);
        SafeTransferLib.safeTransferETH(referrer, referralAmount);
        _mintTo(to);

        return currentId;
    }

    /// @notice Mint a new soulbound token with a score.
    /// @dev Mint a new token, lock it, and update the score.
    /// @param to The address to mint the token to.
    /// @param score The score to set.
    /// @param signature The signature to verify.
    /// @return The token ID.
    function mintWithScore(
        address to,
        uint256 score,
        uint256 timestamp,
        bytes memory signature
    ) payable public returns (uint256) {
        mint(to);
        updateScore(currentId, score, timestamp, signature);
        return currentId;
    }

    /// @notice Mint a new soulbound token with a score and palette.
    /// @dev Mint a new token, lock it, update the score, and update the palette.
    /// @param to The address to mint the token to.
    /// @param score The score to set.
    /// @param palette The palette index to set.
    /// @param signature The signature to verify.
    /// @return The token ID.
    function mintWithScoreAndPalette(
        address to,
        uint256 score,
        uint256 timestamp,
        uint256 palette,
        bytes memory signature
    ) payable public returns (uint256) {
        mint(to);
        updateScore(currentId, score, timestamp, signature);
        updatePalette(currentId, palette);
        return currentId;
    }

    /// @notice Mint a new soulbound token with a score and referral.
    /// @dev Mint a new token, lock it, update the score, and send a referral fee.
    /// @param to The address to mint the token to.
    /// @param score The score to set.
    /// @param referrer The address to send the referral fee to.
    /// @param signature The signature to verify.
    /// @return The token ID.
    function mintWithScoreAndReferral(
        address to,
        uint256 score,
        uint256 timestamp,
        address referrer,
        bytes memory signature
    ) payable public returns (uint256) {
        mintWithReferral(to, referrer);
        updateScore(currentId, score, timestamp, signature);
        return currentId;
    }

    /// @notice Mint a new soulbound token with a score, referral, and palette.
    /// @dev Mint a new token, lock it, update the score, send a referral fee, and update the palette.
    /// @param to The address to mint the token to.
    /// @param score The score to set.
    /// @param referrer The address to send the referral fee to.
    /// @param palette The palette index to set.
    /// @param signature The signature to verify.
    /// @return The token ID.
    function mintWithScoreAndReferralAndPalette(
        address to,
        uint256 score,
        uint256 timestamp,
        address referrer,
        uint256 palette,
        bytes memory signature
    ) payable public returns (uint256) {
        mintWithReferral(to, referrer);
        updateScore(currentId, score, timestamp, signature);
        updatePalette(currentId, palette);
        return currentId;
    }

    /// @notice Mint a new soulbound token with a referral and palette.
    /// @dev Mint a new token, lock it, send a referral fee, and update the palette.
    /// @dev Does not require a signature, since there is no score.
    /// @param to The address to mint the token to.
    /// @param referrer The address to send the referral fee to.
    /// @param palette The palette index to set.
    /// @return The token ID.
    function mintWithReferralAndPalette(
        address to,
        address referrer,
        uint256 palette
    ) payable public nonReentrant returns (uint256) {
        mintWithReferral(to, referrer);
        updatePalette(currentId, palette);
        return currentId;
    }

    /// @notice Mint a new soulbound token with a palette.
    /// @dev Mint a new token, lock it, and update the palette.
    /// @dev Does not require a signature, since there is no score.
    /// @param to The address to mint the token to.
    /// @param palette The palette index to set.
    function mintWithPalette(
        address to,
        uint256 palette
    ) payable public nonReentrant returns (uint256) {
        mint(to);
        updatePalette(currentId, palette);
        return currentId;
    }

    /// @notice Update the score for a given token ID.
    /// @dev The score is signed by the signer for the account.
    /// @param tokenId The token ID to update.
    /// @param newScore The new score.
    /// @param signature The signature to verify.
    function updateScore(uint256 tokenId, uint256 newScore, uint256 timestamp, bytes memory signature) public {
        uint256 oldScore = uint256(getTraitValue(tokenId, "score"));
        if (newScore == 0 && oldScore == 0) {
            // No need to update the score if it's already 0.
            return;
        }
        address account = ownerOf(tokenId);
        _assertValidTimestamp(tokenId, timestamp);
        _assertValidScoreSignature(account, newScore, timestamp, signature);
        this.setTrait(tokenId, "updatedAt", bytes32(timestamp));
        this.setTrait(tokenId, "score", bytes32(newScore));
        emit ScoreUpdated(account, tokenId, oldScore, newScore);
    }

    /// @notice Update the palette index for a given token ID.
    /// @dev The palette index is the index of the palette to use for rendering.
    /// @dev Only the owner can update the palette index.
    /// @param tokenId The token ID to update.
    function updatePalette(uint256 tokenId, uint256 paletteIndex) public {
        _assertTokenOwner(tokenId);
        this.setTrait(tokenId, "paletteIndex", bytes32(paletteIndex));
    }

    /// @notice Check if a token is locked.
    /// @dev The token is Soulbound according to the ERC-5192 standard.
    /// @param tokenId The token ID to check.
    function locked(uint256 tokenId) public pure override returns (bool) {
        return true;
    }

    /// @notice Get the score for a given account.
    /// @param account The account to get the score for.
    /// @return The score.
    function getScore(address account) public view returns (uint256) {
        return uint256(getTraitValue(addressToTokenId[account], "score"));
    }

    /// @notice Get the updated at timestamp for a given token ID.
    /// @dev The updated at timestamp is the timestamp of the last score update.
    /// @param tokenId The token ID to get the updated at timestamp for.
    /// @return The updated at timestamp.
    function getUpdatedAt(uint256 tokenId) public view returns (uint256) {
        return uint256(getTraitValue(tokenId, "updatedAt"));
    }

    /// @notice Get the score and last updated timestamp for a given account.
    /// @dev The score is the reputation score aggregated from Stack leaderboards, and the last updated timestamp.
    /// @param account The account to get the score and last updated timestamp for.
    /// @return The score and last updated timestamp.
    function getScoreAndLastUpdated(address account) public view returns (uint256, uint256) {
        uint256 tokenId = addressToTokenId[account];
        return (
            uint256(getTraitValue(tokenId, "score")),
            uint256(getTraitValue(tokenId, "updatedAt"))
        );
    }

    /// @notice Get the palette index for a given token ID.
    /// @param tokenId The token ID to get the palette index for.
    /// @return The palette index.
    function getPaletteIndex(uint256 tokenId) public view returns (uint256) {
        return uint256(getTraitValue(tokenId, "paletteIndex"));
    }

    /// @notice Get the current token ID.
    /// @return The current token ID.
    function getCurrentId() public view returns (uint256) {
        return currentId;
    }

    /// @notice Get the renderer contract address.
    /// @return The renderer contract address.
    function getRenderer() public view returns (address) {
        return address(renderer);
    }

    /// @notice Set the renderer contract address.
    /// @dev Only the owner can set the renderer contract address.
    /// @param _renderer The renderer contract address.
    function setRenderer(address _renderer) public onlyOwner {
        address oldRenderer = address(renderer);
        renderer = StackScoreRenderer(_renderer);
        emit RendererUpdated(oldRenderer, _renderer);
    }

    /// @notice Set the signer address.
    /// @dev Only the owner can set the signer address.
    /// @param _signer The signer address.
    function setSigner(address _signer) public onlyOwner {
        address oldSigner = signer;
        signer = _signer;
        emit SignerUpdated(oldSigner, _signer);
    }

    /// @notice Set the mint fee.
    /// @dev Only the owner can set the mint fee.
    function setMintFee(uint256 fee) public onlyOwner {
        uint256 oldFee = mintFee;
        mintFee = fee;
        emit MintFeeUpdated(oldFee, mintFee);
    }

    /// @notice Set the referral fee percentage.
    /// @dev Only the owner can set the referral fee percentage.
    /// @param bps The referral fee percentage, in basis points.
    function setReferralBps(uint256 bps) public onlyOwner {
        referralBps = bps;
        emit ReferralBpsUpdated(referralBps, bps);
    }

    /// @notice Set the mint fee recipient.
    /// @dev Only the owner can set the mint fee recipient.
    /// @param _mintFeeRecipient The mint fee recipient address.
    function setMintFeeRecipient(address _mintFeeRecipient) public onlyOwner {
        address oldFeeRecipient = mintFeeRecipient;
        mintFeeRecipient = _mintFeeRecipient;
        emit MintFeeRecipientUpdated(oldFeeRecipient, mintFeeRecipient);
    }

    function _getReferralAmount(uint256 amount) internal view returns (uint256) {
        return amount * referralBps / 10000;
    }

    function _assertOneTokenPerAddress(address to) internal view {
        if (balanceOf(to) > 0) {
            revert OneTokenPerAddress();
        }
    }

    /// @notice Mint a new soulbound token.
    /// @dev Mint a new token, lock it.
    /// @param to The address to mint the token to.
    function _mintTo(address to) internal {
        _assertOneTokenPerAddress(to);

        unchecked {
            _mint(to, ++currentId);
        }

        addressToTokenId[to] = currentId;

        emit Minted(to, currentId);
        emit Locked(currentId);
    }

    /// @notice Verify the signature for the score.
    /// @dev The function throws an error if the signature is invalid, or has been used before.
    /// @param account The account to verify the score for.
    /// @param score The score to verify.
    /// @param signature The signature to verify.
    function _assertValidScoreSignature(address account, uint256 score, uint256 timestamp, bytes memory signature) internal {
        if (signatures[keccak256(signature)]) {
            revert SignatureAlreadyUsed();
        }
        signatures[keccak256(signature)] = true;
        bytes32 hash = ECDSA.toEthSignedMessageHash(
            keccak256(abi.encodePacked(account, score, timestamp))
        );
        if (ECDSA.recover(hash, signature) != signer) {
            revert InvalidSignature();
        }
    }

    /// @notice Verify the sender is the owner of the token.
    /// @dev The function throws an error if the sender is not the owner of the token.
    /// @param tokenId The token ID to verify the owner for.
    function _assertTokenOwner(uint256 tokenId) internal view {
        if (msg.sender != ownerOf(tokenId)) {
            revert OnlyTokenOwner();
        }
    }

    /// @notice Verify the timestamp is not too old.
    /// @dev The function throws an error if the timestamp is too old.
    /// @param tokenId The token ID to verify the timestamp for.
    /// @param timestamp The timestamp to verify.
    function _assertValidTimestamp(uint256 tokenId, uint256 timestamp) internal view {
        uint256 lastUpdatedAt = uint256(getTraitValue(tokenId, "updatedAt"));
        // Ensure the score is newer than the last update.
        if (lastUpdatedAt > timestamp) {
            revert TimestampTooOld();
        }
    }

    function _assertSufficientFee() internal view {
        if (msg.value < mintFee) {
            revert InsufficientFee();
        }
    }

    /// @notice Get the URI for the trait metadata
    /// @param tokenId The token ID to get URI for
    /// @return The trait metadata URI.
    function _stringURI(uint256 tokenId) internal view override returns (string memory) {
        return json.objectOf(
            Solarray.strings(
                json.property("name", _tokenName),
                json.property("description", _tokenDescription),
                json.property("image", Metadata.base64SvgDataURI(_image(tokenId))),
                _attributes(tokenId)
            )
        );
    }

    /// @notice Helper function to get the static attributes for a given token ID
    /// @dev The static attributes are the name and description.
    /// @param tokenId The token ID to get the static attributes for
    /// @return The static attributes.
    function _staticAttributes(uint256 tokenId) internal view virtual override returns (string[] memory) {
        return Solarray.strings(
            Metadata.attribute({traitType: "Score Version", value: version})
        );
    }

    /// @notice Run checks before token transfers
    /// @dev Only allow transfers from the zero address, since the token is soulbound.
    /// @param from The address the token is being transferred from
    /// @param tokenId The token ID
    function _beforeTokenTransfer(address from, address, uint256 tokenId) internal pure override {
        // if the token is being transferred from an address
        if (from != address(0)) {
            revert TokenLocked(tokenId);
        }
    }

    /// @notice Helper function to get the raw SVG image for a given token ID
    /// @dev The SVG image is rendered by the renderer contract.
    /// @param tokenId The token ID to get the dynamic attributes for
    /// @return The SVG image.
    function _image(uint256 tokenId) internal view virtual override returns (string memory) {
        address account = ownerOf(tokenId);
        uint256 paletteIndex = uint256(getTraitValue(tokenId, "paletteIndex"));
        uint256 score = uint256(getTraitValue(tokenId, "score"));
        uint256 updatedAt = uint256(getTraitValue(tokenId, "updatedAt"));
        return renderer.getSVG(score, account, paletteIndex, updatedAt);
    }

    /// @notice Check if the sender is the owner of the token or an approved operator.
    /// @param tokenId The token ID to check.
    /// @param addr The address to check.
    /// @return True if the address is the owner or an approved operator.
    function _isOwnerOrApproved(uint256 tokenId, address addr) internal view override returns (bool) {
        return addr == ownerOf(tokenId);
    }
}

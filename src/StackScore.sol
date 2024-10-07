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
/// @notice A contract for minting and managing Stack Score NFTs.
contract StackScore is AbstractNFT, IERC5192, ReentrancyGuard {
    /// @notice The current token ID.
    string public version = "1";
    /// @notice The signer address.
    address public signer;
    /// @notice The mint fee.
    uint256 public mintFee = 0.001 ether;
    /// @notice Address to token ID mapping.
    mapping(address => uint256) internal addressToTokenId;
    /// @notice Signature to used mapping.
    /// @dev This is used to prevent replay attacks.
    mapping(bytes32 => bool) internal signatures;
    /// @notice The current token ID.
    uint256 internal _currentId;
    /// @notice The renderer contract.
    /// @dev This contract is used to render the SVG image.
    StackScoreRenderer internal renderer;
    /// @notice The mint fee recipient.
    /// @dev This address receives the mint fee.
    address public mintFeeRecipient;

    /// @notice Emitted when the score is updated.
    event ScoreUpdated(uint256 tokenId, uint256 oldScore, uint256 newScore);
    /// @notice Emitted when a token is minted.
    event Minted(address to, uint256 tokenId);
    /// @notice Emitted when the mint fee is updated.
    event MintFeeUpdated(uint256 oldFee, uint256 newFee);
    event MintFeeRecipientUpdated(address oldRecipient, address newRecipient);

    /// @notice Error thrown when the token is locked upon transfer.
    error TokenLocked(uint256 tokenId);
    /// @notice Error thrown when the signature is invalid.
    error InvalidSignature();
    /// @notice Error thrown when the signature is already used.
    error SignatureAlreadyUsed();
    /// @notice Error thrown when the mint fee is insufficient.
    error InsufficientFee();
    /// @notice Error thrown when the sender is not the token owner.
    error OnlyTokenOwner();
    /// @notice Error thrown when the timestamp is too old.
    error TimestampTooOld();
    /// @notice Error thrown if mint called for the second time for the same address.
    error OneTokenPerAddress();

    /// @notice Constructor
    /// @dev Set the name and symbol of the token.
    constructor(address initialOwner) AbstractNFT("Stack Score", "Stack_Score") {
        _initializeOwner(initialOwner);
    }

    /// @notice Mint a new soulbound token.
    /// @dev Mint a new token and lock it.
    /// @param to The address to mint the token to.
    /// @return The token ID.
    function mint(address to) payable public nonReentrant returns (uint256) {
        if (msg.value < mintFee) {
            revert InsufficientFee();
        }

        if (balanceOf(to) > 0) {
            revert OneTokenPerAddress();
        }

        SafeTransferLib.safeTransferETH(mintFeeRecipient, msg.value);

        unchecked {
            _mint(to, ++_currentId);
        }

        addressToTokenId[to] = _currentId;
        emit Minted(to, _currentId);
        emit Locked(_currentId);
        return _currentId;
    }

    /// @notice Mint a new soulbound token with a score.
    /// @dev Mint a new token, lock it, and update the score.
    /// @param to The address to mint the token to.
    /// @param score The score to set.
    /// @param signature The signature to verify.
    /// @return The token ID.
    function mintWithScore(address to, uint256 score, uint256 timestamp, bytes memory signature) payable public returns (uint256) {
        mint(to);
        updateScore(_currentId, score, timestamp, signature);
        return _currentId;
    }

    /// @notice Mint a new soulbound token with a score and palette.
    /// @dev Mint a new token, lock it, update the score, and update the palette.
    /// @param to The address to mint the token to.
    /// @param score The score to set.
    /// @param palette The palette index to set.
    /// @param signature The signature to verify.
    /// @return The token ID.
    function mintWithScoreAndPalette(address to, uint256 score, uint256 timestamp, uint256 palette, bytes memory signature) payable public returns (uint256) {
        require(msg.sender == to, "Only the recipient can call this function");
        mint(to);
        updateScore(_currentId, score, timestamp, signature);
        updatePalette(_currentId, palette);
        return _currentId;
    }

    /// @notice Update the score for a given token ID.
    /// @dev The score is signed by the signer for the account.
    /// @param tokenId The token ID to update.
    /// @param newScore The new score.
    /// @param signature The signature to verify.
    function updateScore(uint256 tokenId, uint256 newScore, uint256 timestamp, bytes memory signature) public {
        _assertValidTimestamp(tokenId, timestamp);
        _assertValidScoreSignature(ownerOf(tokenId), newScore, timestamp, signature);
        this.setTrait(tokenId, "updatedAt", bytes32(block.timestamp));
        uint256 oldScore = uint256(getTraitValue(tokenId, "score"));
        this.setTrait(tokenId, "score", bytes32(newScore));
        emit ScoreUpdated(tokenId, oldScore, newScore);
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

    /// @notice Get the palette index for a given token ID.
    /// @param tokenId The token ID to get the palette index for.
    /// @return The palette index.
    function getPaletteIndex(uint256 tokenId) public view returns (uint256) {
        return uint256(getTraitValue(tokenId, "paletteIndex"));
    }

    /// @notice Get the current token ID.
    /// @return The current token ID.
    function getCurrentId() public view returns (uint256) {
        return _currentId;
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
        renderer = StackScoreRenderer(_renderer);
    }

    /// @notice Set the signer address.
    /// @dev Only the owner can set the signer address.
    /// @param _signer The signer address.
    function setSigner(address _signer) public onlyOwner {
        signer = _signer;
    }

    /// @notice Set the mint fee.
    /// @dev Only the owner can set the mint fee.
    function setMintFee(uint256 fee) public onlyOwner {
        uint256 oldFee = mintFee;
        mintFee = fee;
        emit MintFeeUpdated(oldFee, mintFee);
    }

    /// @notice Set the mint fee recipient.
    /// @dev Only the owner can set the mint fee recipient.
    /// @param _mintFeeRecipient The mint fee recipient address.
    function setMintFeeRecipient(address _mintFeeRecipient) public onlyOwner {
        address oldFeeRecipient = mintFeeRecipient;
        mintFeeRecipient = _mintFeeRecipient;
        emit MintFeeRecipientUpdated(oldFeeRecipient, mintFeeRecipient);
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

    /// @notice Get the URI for the trait metadata
    /// @param tokenId The token ID to get URI for
    /// @return The trait metadata URI.
    function _stringURI(uint256 tokenId) internal view override returns (string memory) {
        return json.objectOf(
            Solarray.strings(
                json.property("name", "Stack Score"),
                json.property("description", "Reputation score aggregated from Stack leaderboards"),
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

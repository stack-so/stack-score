// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {json} from "./onchain/json.sol";
import {Metadata, DisplayType} from "./onchain/Metadata.sol";
import {LibString} from "solady/utils/LibString.sol";
import {Solarray} from "solarray/Solarray.sol";
import {AbstractNFT} from "./AbstractNFT.sol";
import {ECDSA} from "solady/utils/ECDSA.sol";
import {TraitLib} from "src/dynamic-traits/lib/TraitLabelLib.sol";
import {StackScoreRenderer} from "./StackScoreRenderer.sol";

interface IERC5192 {
    /// @notice Emitted when the locking status is changed to locked.
    /// @dev If a token is minted and the status is locked, this event should be emitted.
    /// @param tokenId The identifier for a token.
    event Locked(uint256 tokenId);

    /// @notice Emitted when the locking status is changed to unlocked.
    /// @dev If a token is minted and the status is unlocked, this event should be emitted.
    /// @param tokenId The identifier for a token.
    event Unlocked(uint256 tokenId);

    /// @notice Returns the locking status of an Soulbound Token
    /// @dev SBTs assigned to zero address are considered invalid, and queries
    /// about them do throw.
    /// @param tokenId The identifier for an SBT.
    function locked(uint256 tokenId) external view returns (bool);
}

contract StackScore is AbstractNFT, IERC5192 {
    uint256 currentId;
    string public version = "1";
    address public signer;
    uint256 public mintFee = 0.001 ether;
    StackScoreRenderer public renderer;
    mapping(address => uint256) public addressToTokenId;
    mapping(bytes32 => bool) internal signatures;

    // Errors
    error TokenLocked(uint256 tokenId);

    // Events
    event ScoreUpdated(uint256 tokenId, uint256 score);
    event Minted(address to, uint256 tokenId);

    // Constructor
    constructor() AbstractNFT("Stack Score", "Stack_Score") {}

    /**
     * Mint functions
        */
    function mint(address to) payable public returns (uint256) {
        require(msg.value >= mintFee, "Insufficient fee");
        require(balanceOf(to) == 0, "Only one token per address");

        unchecked {
            _mint(to, ++currentId);
        }

        addressToTokenId[to] = currentId;
        emit Minted(to, currentId);
        emit Locked(currentId);
        return currentId;
    }

    function mintWithScore(address to, uint256 score, bytes memory signature) payable public returns (uint256) {
        mint(to);
        updateScore(currentId, score, signature);
        return currentId;
    }

    function mintWithScoreAndPalette(address to, uint256 score, uint256 palette, bytes memory signature) payable public returns (uint256) {
        require(msg.sender == to, "Only the recipient can call this function");
        mint(to);
        updateScore(currentId, score, signature);
        // TODO: Update palette.
        return currentId;
    }

    /**
    * Getter functions
    */

    // The token is Soulbound according to the ERC-5192 standard.
    function locked(uint256 tokenId) public view override returns (bool) {
        return true;
    }

    function getScore(address account) public returns (uint256) {
        return uint256(getTraitValue(addressToTokenId[account], "score"));
    }

    /**
    * Setter functions
    */

    function setRenderer(address _renderer) public onlyOwner {
        renderer = StackScoreRenderer(_renderer);
    }

    function setSigner(address _signer) public {
        signer = _signer;
    }

    function setFee(uint256 fee) public onlyOwner {
        mintFee = fee;
    }

    function updateScore(uint256 tokenId, uint256 score, bytes memory signature) public {
        _verifyScoreSignature(ownerOf(tokenId), score, signature);
        this.setTrait(tokenId, "score", bytes32(score));
    }

    function updatePalette(uint256 tokenId, uint256 paletteIndex) public {
        require(msg.sender == ownerOf(tokenId), "Only owner can update palette"); // todo: better error.
        this.setTrait(tokenId, "paletteIndex", bytes32(paletteIndex));
    }

    function getPaletteIndex(uint256 tokenId) public view returns (uint256) {
        return uint256(getTraitValue(tokenId, "paletteIndex"));
    }

    /**
    * Internal functions
    */

    function _verifyScoreSignature(address account, uint256 score, bytes memory signature) internal returns (bool) {
        require(!signatures[keccak256(signature)], "Signature already used");
        signatures[keccak256(signature)] = true;
        bytes32 messageHash = keccak256(abi.encodePacked(account, score));
        bytes32 hash = ECDSA.toEthSignedMessageHash(messageHash);
        return ECDSA.recover(hash, signature) == signer;
    }

    /**
     * @notice Helper function to get the raw JSON metadata representing a given token ID
     * @param tokenId The token ID to get URI for
     */
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

    /**
     * @notice Helper function to get the static attributes for a given token ID
     * @param tokenId The token ID to get the static attributes for
     */
    function _staticAttributes(uint256 tokenId) internal view virtual override returns (string[] memory) {
        return Solarray.strings(
            Metadata.attribute({traitType: "Score Version", value: version})
        );
    }

    function _beforeTokenTransfer(address from, address, uint256 tokenId) internal view override {
        // if the token is being transferred from an address
        if (from != address(0)) {
            revert TokenLocked(tokenId);
        }
    }

    /**
     * @notice Helper function to get the raw SVG image for a given token ID
     * @param tokenId The token ID to get the dynamic attributes for
     */
    function _image(uint256 tokenId) internal view virtual override returns (string memory) {
        address account = ownerOf(tokenId);
        uint256 paletteIndex = uint256(getTraitValue(tokenId, "paletteIndex"));
        uint256 score = uint256(getTraitValue(tokenId, "score"));
        return renderer.getSVG(tokenId, score, account, paletteIndex);
    }

    function _isOwnerOrApproved(uint256 tokenId, address addr) internal view override returns (bool) {
        return addr == ownerOf(tokenId);
    }
}

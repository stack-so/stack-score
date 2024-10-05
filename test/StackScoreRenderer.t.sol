// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import {StackScoreRenderer} from "src/StackScoreRenderer.sol";
import {Metadata} from "../src/onchain/Metadata.sol";
import {LibString} from "solady/utils/LibString.sol";

contract StackScoreRendererTest is Test {
    StackScoreRenderer renderer;
    address testAddress = address(0x1234567890123456789012345678901234567890);

    function setUp() public {
        renderer = new StackScoreRenderer();
    }

    function testGetTimestampString() public {
        string memory timestamp = renderer.getTimestampString(1728125991);
        assertEq(timestamp, "OCT 5 2024 10:59 UTC");
    }

    function testGetSVG() public {
        string memory svg = renderer.getSVG(100, testAddress, 0, 1728125991);
        assertTrue(bytes(svg).length > 0);
        assertTrue(LibString.contains(svg, "100"));
        assertTrue(LibString.contains(svg, LibString.toHexString(testAddress)));
        assertTrue(LibString.contains(svg, "OCT 5 2024 10:59 UTC"));
    }

    function testGetSVGAsDataURI() public {
        string memory dataURI = Metadata.base64SvgDataURI(
            renderer.getSVG(100, testAddress, 6, 1728125991)
        );
        assertTrue(LibString.startsWith(dataURI, "data:image/svg+xml;base64,"));
    }

    function testGetColorAsHexString() public {
        string memory color = renderer.getColorAsHexString(0, 0);
        assertEq(color, "4f4c42");
    }

    function testDifferentScores() public {
        string memory svg1 = renderer.getSVG(100, testAddress, 0, 1728125991);
        string memory svg2 = renderer.getSVG(200, testAddress, 0, 1728125991);
        assertTrue(LibString.contains(svg1, "100"));
        assertTrue(LibString.contains(svg2, "200"));
    }

    function testDifferentAddresses() public {
        address testAddress2 = address(0x9876543210987654321098765432109876543210);
        string memory svg1 = renderer.getSVG(100, testAddress, 0, 1728125991);
        string memory svg2 = renderer.getSVG(100, testAddress2, 0, 1728125991);
        assertTrue(LibString.contains(svg1, LibString.toHexString(testAddress)));
        assertTrue(LibString.contains(svg2, LibString.toHexString(testAddress2)));
    }

    function testDifferentPalettes() public {
        string memory svg1 = renderer.getSVG(100, testAddress, 0, 1728125991);
        string memory svg2 = renderer.getSVG(100, testAddress, 1, 1728125991);
        assertTrue(LibString.contains(svg1, renderer.getColorAsHexString(0, 0)));
        assertTrue(LibString.contains(svg2, renderer.getColorAsHexString(1, 0)));
    }

    function testDifferentTimestamps() public {
        string memory svg1 = renderer.getSVG(100, testAddress, 0, 1728125991);
        string memory svg2 = renderer.getSVG(100, testAddress, 0, 1728212391);
        assertTrue(LibString.contains(svg1, "OCT 5 2024 10:59 UTC"));
        assertTrue(LibString.contains(svg2, "OCT 6 2024 10:59 UTC"));
    }

    function testInvalidPaletteIndex() public {
        vm.expectRevert();
        renderer.getSVG(100, testAddress, 11, 1728125991);
    }

    function testFuzzScores(uint256 score) public {
        string memory svg = renderer.getSVG(score, testAddress, 0, 1728125991);
        assertTrue(LibString.contains(svg, LibString.toString(score)));
    }

    function testFuzzAddresses(address addr) public {
        string memory svg = renderer.getSVG(100, addr, 0, 1728125991);
        assertTrue(LibString.contains(svg, LibString.toHexString(addr)));
    }

    function testFuzzPalettes(uint256 paletteIndex) public {
        vm.assume(paletteIndex < 11);
        string memory svg = renderer.getSVG(100, testAddress, paletteIndex, 1728125991);
        assertTrue(LibString.contains(svg, renderer.getColorAsHexString(paletteIndex, 0)));
    }

    function testFuzzTimestamps(uint256 timestamp) public {
        string memory svg = renderer.getSVG(100, testAddress, 0, timestamp);
        string memory timestampString = renderer.getTimestampString(timestamp);
        assertTrue(LibString.contains(svg, timestampString));
    }
}

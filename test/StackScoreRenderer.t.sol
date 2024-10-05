// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import {StackScoreRenderer} from "src/StackScoreRenderer.sol";
import {Metadata} from "../src/onchain/Metadata.sol";

contract StackScoreRendererTest is Test {
    StackScoreRenderer renderer;

    function setUp() public {
        renderer = new StackScoreRenderer();
    }

    function testGetTimestampString() public {
        console.log(renderer.getTimestampString(1728125991));
    }

    function testGetSVG() public {
        console.log(renderer.getSVG(100, address(this), 0, 1728125991));
    }

    function testGetSVGAsDataURI() public {
        console.log(
            Metadata.base64SvgDataURI(
                renderer.getSVG(100, address(this), 6, 1728125991)
            )
        );
    }
}

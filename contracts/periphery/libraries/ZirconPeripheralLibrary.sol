pragma solidity >=0.6.6;

import "./SafeMath.sol";
import "../../core/interfaces/IZirconPylon.sol";
import "hardhat/console.sol";

library ZirconPeripheralLibrary {
    using SafeMath for uint256;
    // calculates the CREATE2 address for a pair without making any external calls
    //TODO: Update init code hash with Zircon Pylon code hash
    function pylonFor(address factory, address tokenA, address tokenB, address pair) internal pure returns (address pylon) {
        pylon = address(uint(keccak256(abi.encodePacked(
                hex'ff',
                factory,
                keccak256(abi.encodePacked(tokenA, tokenB, pair)),
                hex'99e0034afde5d5dfacb0abc060c5f76883e242a7a758e36e151b0191d7794c98' // init code hash
            ))));
    }

    function isInitialized(address factory, address tokenA, address tokenB, address pair) view external returns (bool initialized){
        initialized = IZirconPylon(pylonFor(factory, tokenA, tokenB, pair)).initialized() == 1;
    }

    function translate(uint toConvert, uint ptt, uint ptb) pure public  returns (uint amount){
        amount =  (ptt == 0 || ptb == 0) ? toConvert : toConvert.mul(ptb)/ptt;
    }

    // fetches and gets Reserves
    function getSyncReserves(address factory, address tokenA, address tokenB, address pair) internal view returns (uint112 reserveF, uint112 reserveA) {
        (reserveF, reserveA,) = IZirconPylon(pylonFor(factory, tokenA, tokenB, pair)).getSyncReserves();
    }

    // fetches and sorts the reserves for a pair
    function maximumSync(uint reserve, uint reservePylon, uint syncPercentage, uint maxBase, uint ptt, uint ptb) external pure returns (uint maximum) {
        uint pairReserveTranslated = translate(reserve, ptt, ptb);
        maximum = (pairReserveTranslated == 0 || reservePylon > pairReserveTranslated) ? maxBase :
        (pairReserveTranslated.mul(syncPercentage)/100).sub(reservePylon);

    }

}

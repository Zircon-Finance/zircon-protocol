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
                hex'1b818d4cbf407035d1732c9badcf95b264f1e61f5dd80917c94b9ec2798ba544' // init code hash
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
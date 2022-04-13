pragma solidity ^0.5.16;
import "./ZirconERC20.sol";
import "./interfaces/IZirconPoolToken.sol";

contract ZirconPoolToken is ZirconERC20 {
    address public token;
    address public pair;
    bool public isAnchor;
    address public factory;
    address public pylon;

    uint private unlocked = 1;
    modifier lock() {
        require(unlocked == 1, 'UniswapV2: LOCKED');
        unlocked = 0;
        _;
        unlocked = 1;
    }

    function mint(address account, uint256 amount) lock external {
        require(msg.sender == pylon, 'ZirconPoolToken: FORBIDDEN'); // sufficient check
        _mint(account, amount);
    }

    function burn(address account, uint256 amount) lock external {
        require(msg.sender == pylon, 'ZirconPoolToken: FORBIDDEN'); // sufficient check
        _burn(account, amount);
    }

    constructor() public {
        factory = msg.sender;
    }

    // called once by the factory at time of deployment
    function initialize(address _token0, address _pair, address _pylon, bool _isAnchor) external {
        require(msg.sender == factory, 'ZirconPoolToken: FORBIDDEN'); // sufficient check
        token = _token0;
        pair = _pair;
        isAnchor = _isAnchor;
        pylon = _pylon;
    }
}

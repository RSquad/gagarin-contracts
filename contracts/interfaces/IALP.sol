pragma solidity ^0.8.0;


interface IALP {
    function mint(address _to, uint256 _amount) external;
    function burn(address from, uint256 _share) external;
}
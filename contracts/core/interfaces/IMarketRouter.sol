// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

interface IMarketRouter {

    function vault() external view returns(address);
    function VAMM() external view returns(address);
    function stable() external view returns(address);
    function utilityStorage() external view returns(address);
    function liquidatePrivateMode() external view returns(bool);
    function liquidators(address _liquidator) external view returns(bool);
    function liquidatorsUtility(address _liquidator) external view returns(bool);
    function whitelistedToken(address _indexToken) external view returns(bool);

    function setTokenConfig(address _indexToken) external;

    function deleteTokenConfig(address _indexToken) external;

    function setLiquidator(address _liquidator, bool _bool) external;

    function setLiquidatorUtility(address _liquidator, bool _bool) external;

    function setLiquidatePrivateMode(bool _bool) external;

    function increasePosition(address _indexToken, uint _collateralDelta, uint _sizeDelta, bool _long) external;

    function addCollateral(address _indexToken, uint _collateralDelta, bool _long) external;

    function withdrawCollateral(address _indexToken, uint _collateralDelta, bool _long) external;

    function serviceWithdrawCollateral(address _user, address _indexToken, bool _long) external;

    function decreasePosition(address _indexToken, uint _collateralDelta, uint _sizeDelta, bool _long) external;

    function liquidatePosition(address _user, address _indexToken, bool _long, address _feeReceiver) external;

}
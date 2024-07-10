// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "./IPermitData.sol";

interface IMarketRouter is IPermitData {

    function vault() external view returns(address);
    function VAMM() external view returns(address);
    function stable() external view returns(address);
    function utilityStorage() external view returns(address);
    function liquidatePrivateMode() external view returns(bool);

    function liquidators(address liquidator) external view returns(bool);
    function liquidatorsUtility(address liquidator) external view returns(bool);
    function whitelistedToken(address indexToken) external view returns(bool);

    function setTokenConfig(address indexToken) external;

    function deleteTokenConfig(address indexToken) external;

    function setLiquidator(address liquidator, bool set) external;

    function setLiquidatorUtility(address liquidator, bool set) external;

    function setLiquidatePrivateMode(bool set) external;

    function increasePosition(address indexToken, uint collateralDelta, uint sizeDelta, bool long) external;

    function increasePositionWithPermit( 
        address indexToken, 
        uint collateralDelta, 
        uint sizeDelta,
        bool long,
        PermitData calldata $
    ) external;

    function addCollateral(address indexToken, uint collateralDelta, bool long) external;

    function addCollateralWithPermit( 
        address indexToken, 
        uint collateralDelta, 
        bool long,
        PermitData calldata $
    ) external;

    function withdrawCollateral(address indexToken, uint collateralDelta, bool long) external;

    function serviceWithdrawCollateral(address user, address indexToken, bool long) external;

    function decreasePosition(address indexToken, uint collateralDelta, uint sizeDelta, bool long) external;

    function liquidatePosition(address user, address indexToken, bool long, address feeReceiver) external;

}
// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.6.12;

interface IChefLike {
    function deposit(uint256 _pid, uint256 _amount) external;

    function withdraw(uint256 _pid, uint256 _amount) external;

    function emergencyWithdraw(uint256 _pid) external;

    function poolInfo(uint256 _pid)
        external
        view
        returns (
            address,
            uint256,
            uint256,
            uint256
        );

    function userInfo(uint256 _pid, address user)
        external
        view
        returns (uint256, uint256);
}